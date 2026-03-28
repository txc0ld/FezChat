import Foundation
@preconcurrency import CoreBluetooth
import FestiChatProtocol
import os.log

/// Dual-role BLE transport for the FestiChat mesh network (spec Section 5.2).
///
/// Operates simultaneously as a `CBCentralManager` (scanner/client) and
/// `CBPeripheralManager` (advertiser/server). Supports state restoration
/// for background BLE operation on iOS.
public final class BLEService: NSObject, Transport, @unchecked Sendable {

    // MARK: - Transport conformance

    public weak var delegate: (any TransportDelegate)?

    public private(set) var state: TransportState = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.transport(self, didChangeState: state)
        }
    }

    public var connectedPeers: [PeerID] {
        lock.withLock {
            Array(peripheralToPeerID.values)
        }
    }

    // MARK: - Core Bluetooth managers

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    // MARK: - BLE service & characteristic

    private var service: CBMutableService?
    private var characteristic: CBMutableCharacteristic?

    // MARK: - Peer tracking

    /// Maps discovered CBPeripheral identifiers to their peer IDs.
    private var peripheralToPeerID: [UUID: PeerID] = [:]

    /// Reverse mapping: PeerID -> CBPeripheral for sending.
    private var peerIDToPeripheral: [PeerID: CBPeripheral] = [:]

    /// Maps peripheral UUID to the writable characteristic discovered on that peripheral.
    private var peripheralCharacteristics: [UUID: CBCharacteristic] = [:]

    /// Set of peripheral UUIDs currently being connected to (to avoid duplicates).
    private var connectingPeripherals: Set<UUID> = []

    /// Peripherals that recently timed out, with the timestamp of the timeout.
    private var timedOutPeripherals: [UUID: Date] = [:]

    /// Centrals subscribed to our characteristic (for notify).
    private var subscribedCentrals: [CBCentral] = []

    /// Maps subscribed CBCentral identifiers to peer IDs.
    private var centralToPeerID: [UUID: PeerID] = [:]

    /// Strong references to connected peripherals to prevent deallocation.
    private var connectedPeripheralRefs: [UUID: CBPeripheral] = [:]

    // MARK: - Concurrency

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.festichat.ble", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.festichat", category: "BLE")

    // MARK: - Scanning control

    private var isScanning = false
    private var scanTimer: DispatchSourceTimer?

    // MARK: - Local peer ID

    /// The local device's PeerID, derived from its Noise public key.
    public let localPeerID: PeerID

    // MARK: - Init

    /// Create a BLE service with the local device's peer ID.
    ///
    /// - Parameter localPeerID: This device's PeerID (derived from Noise public key).
    public init(localPeerID: PeerID) {
        self.localPeerID = localPeerID
        super.init()
    }

    // MARK: - Transport lifecycle

    public func start() {
        guard state == .idle || state == .stopped else { return }
        state = .starting

        centralManager = CBCentralManager(
            delegate: self,
            queue: queue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralRestorationID,
                CBCentralManagerOptionShowPowerAlertKey: true,
            ]
        )

        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: queue,
            options: [
                CBPeripheralManagerOptionRestoreIdentifierKey: BLEConstants.peripheralRestorationID,
            ]
        )
    }

    public func stop() {
        state = .stopped

        stopScanning()

        if peripheralManager?.isAdvertising == true {
            peripheralManager.stopAdvertising()
        }

        lock.withLock {
            for (_, peripheral) in connectedPeripheralRefs {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            peripheralToPeerID.removeAll()
            peerIDToPeripheral.removeAll()
            peripheralCharacteristics.removeAll()
            connectingPeripherals.removeAll()
            connectedPeripheralRefs.removeAll()
            subscribedCentrals.removeAll()
            centralToPeerID.removeAll()
        }

        if let service = service {
            peripheralManager?.remove(service)
        }
    }

    public func send(data: Data, to peerID: PeerID) throws {
        guard state == .running else {
            throw TransportError.notStarted
        }
        guard data.count <= BLEConstants.effectiveMTU else {
            throw TransportError.payloadTooLarge(size: data.count, max: BLEConstants.effectiveMTU)
        }

        var sent = false

        // Try sending via central connection (write to peripheral's characteristic)
        lock.lock()
        if let peripheral = peerIDToPeripheral[peerID],
           let char = peripheralCharacteristics[peripheral.identifier] {
            lock.unlock()
            peripheral.writeValue(data, for: char, type: .withResponse)
            sent = true
        } else {
            lock.unlock()
        }

        // Try sending via peripheral manager (notify subscribed central)
        if !sent {
            lock.lock()
            let matchingCentral = centralToPeerID.first(where: { $0.value == peerID })?.key
            let central = subscribedCentrals.first(where: { $0.identifier == matchingCentral })
            lock.unlock()

            if let central = central, let char = characteristic {
                peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: [central])
                sent = true
            }
        }

        if !sent {
            throw TransportError.peerNotConnected(peerID)
        }
    }

    public func broadcast(data: Data) {
        guard state == .running else { return }

        // Notify all subscribed centrals via peripheral manager
        if let char = characteristic, !subscribedCentrals.isEmpty {
            peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: subscribedCentrals)
        }

        // Write to all connected peripherals via central manager
        lock.lock()
        let peripherals = Array(connectedPeripheralRefs.values)
        let chars = peripheralCharacteristics
        lock.unlock()

        for peripheral in peripherals {
            if let char = chars[peripheral.identifier] {
                peripheral.writeValue(data, for: char, type: .withoutResponse)
            }
        }
    }

    // MARK: - Scanning

    private func startScanning() {
        guard centralManager?.state == .poweredOn else { return }
        guard !isScanning else { return }

        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false,
            ]
        )
        logger.info("BLE scanning started")

        scheduleScanCycle()
    }

    private func stopScanning() {
        isScanning = false
        scanTimer?.cancel()
        scanTimer = nil
        centralManager?.stopScan()
    }

    /// Alternate between scanning and pausing to conserve power.
    private func scheduleScanCycle() {
        scanTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + BLEConstants.foregroundScanDuration,
            repeating: .never
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.isScanning {
                self.centralManager?.stopScan()
                // Pause, then resume
                let resumeTimer = DispatchSource.makeTimerSource(queue: self.queue)
                resumeTimer.schedule(
                    deadline: .now() + BLEConstants.foregroundScanPause,
                    repeating: .never
                )
                resumeTimer.setEventHandler { [weak self] in
                    guard let self = self, self.isScanning else { return }
                    self.centralManager?.scanForPeripherals(
                        withServices: [BLEConstants.serviceUUID],
                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                    )
                    self.scheduleScanCycle()
                }
                resumeTimer.resume()
                self.scanTimer = resumeTimer
            }
        }
        timer.resume()
        scanTimer = timer
    }

    // MARK: - Advertising

    private func startAdvertising() {
        guard peripheralManager?.state == .poweredOn else { return }

        let mutableCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.characteristicUUID,
            properties: [.write, .writeWithoutResponse, .notify, .read],
            value: nil,
            permissions: [.writeable, .readable]
        )
        self.characteristic = mutableCharacteristic

        let mutableService = CBMutableService(
            type: BLEConstants.serviceUUID,
            primary: true
        )
        mutableService.characteristics = [mutableCharacteristic]
        self.service = mutableService

        peripheralManager.add(mutableService)
    }

    private func beginAdvertising() {
        guard peripheralManager?.state == .poweredOn else { return }
        guard peripheralManager?.isAdvertising == false else { return }

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "FestiChat",
        ])
        logger.info("BLE advertising started")
    }

    // MARK: - Connection management

    private func shouldConnect(to peripheral: CBPeripheral, rssi: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Already connected or connecting
        if connectedPeripheralRefs[peripheral.identifier] != nil { return false }
        if connectingPeripherals.contains(peripheral.identifier) { return false }

        // Recently timed out — backoff
        if let timeoutDate = timedOutPeripherals[peripheral.identifier],
           Date().timeIntervalSince(timeoutDate) < BLEConstants.reconnectBackoff {
            return false
        }

        // RSSI threshold
        let threshold = connectedPeripheralRefs.isEmpty
            ? BLEConstants.isolatedRSSIThreshold
            : BLEConstants.defaultRSSIThreshold
        if rssi < threshold { return false }

        // Connection count limit
        let currentCount = connectedPeripheralRefs.count
        let maxConnections = BLEConstants.maxCentralConnectionsNormal
        if currentCount >= maxConnections { return false }

        return true
    }

    // MARK: - Helpers

    /// Derive a temporary PeerID from a peripheral identifier until the real one is exchanged.
    private func temporaryPeerID(from uuid: UUID) -> PeerID {
        let data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        return PeerID(noisePublicKey: data)
    }

    /// Clean up stale timed-out entries.
    private func pruneTimedOutPeripherals() {
        let now = Date()
        timedOutPeripherals = timedOutPeripherals.filter { _, date in
            now.timeIntervalSince(date) < BLEConstants.reconnectBackoff
        }
    }

    /// Update the peer ID mapping once the real announcement is received.
    public func updatePeerID(_ peerID: PeerID, forPeripheralUUID uuid: UUID) {
        lock.withLock {
            let oldPeerID = peripheralToPeerID[uuid]
            peripheralToPeerID[uuid] = peerID

            if let peripheral = connectedPeripheralRefs[uuid] {
                if let old = oldPeerID {
                    peerIDToPeripheral.removeValue(forKey: old)
                }
                peerIDToPeripheral[peerID] = peripheral
            }
        }
    }

    /// Update the peer ID mapping for a subscribed central.
    public func updatePeerID(_ peerID: PeerID, forCentralUUID uuid: UUID) {
        lock.withLock {
            centralToPeerID[uuid] = peerID
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("Central powered on")
            updateRunningState()
            startScanning()
        case .poweredOff:
            logger.warning("Central powered off")
            state = .failed("Bluetooth powered off")
        case .unauthorized:
            logger.error("Central unauthorized")
            state = .failed("Bluetooth unauthorized")
        case .unsupported:
            logger.error("Central unsupported")
            state = .failed("Bluetooth unsupported")
        case .resetting:
            logger.warning("Central resetting")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        logger.info("Central restoring state")

        // Restore connected peripherals from state restoration.
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                peripheral.delegate = self
                lock.withLock {
                    connectedPeripheralRefs[peripheral.identifier] = peripheral
                    let tempID = temporaryPeerID(from: peripheral.identifier)
                    peripheralToPeerID[peripheral.identifier] = tempID
                    peerIDToPeripheral[tempID] = peripheral
                }
                // Re-discover services to find our characteristic.
                peripheral.discoverServices([BLEConstants.serviceUUID])
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue != 127 else { return } // 127 means RSSI unavailable.

        pruneTimedOutPeripherals()

        guard shouldConnect(to: peripheral, rssi: rssiValue) else { return }

        lock.withLock {
            connectingPeripherals.insert(peripheral.identifier)
            connectedPeripheralRefs[peripheral.identifier] = peripheral
        }

        logger.info("Connecting to peripheral \(peripheral.identifier), RSSI: \(rssiValue)")
        peripheral.delegate = self
        central.connect(peripheral, options: nil)

        // Connection timeout.
        queue.asyncAfter(deadline: .now() + BLEConstants.connectionTimeout) { [weak self] in
            guard let self = self else { return }
            let isStillConnecting = self.lock.withLock {
                self.connectingPeripherals.contains(peripheral.identifier)
            }
            if isStillConnecting {
                self.logger.warning("Connection timeout for \(peripheral.identifier)")
                central.cancelPeripheralConnection(peripheral)
                self.lock.withLock {
                    self.connectingPeripherals.remove(peripheral.identifier)
                    self.connectedPeripheralRefs.removeValue(forKey: peripheral.identifier)
                    self.timedOutPeripherals[peripheral.identifier] = Date()
                }
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        logger.info("Connected to peripheral \(peripheral.identifier)")

        lock.withLock {
            connectingPeripherals.remove(peripheral.identifier)
            connectedPeripheralRefs[peripheral.identifier] = peripheral

            let peerID = temporaryPeerID(from: peripheral.identifier)
            peripheralToPeerID[peripheral.identifier] = peerID
            peerIDToPeripheral[peerID] = peripheral
        }

        // Request larger MTU on iOS 16+.
        if #available(iOS 16.0, macOS 13.0, *) {
            peripheral.delegate = self
        }

        peripheral.discoverServices([BLEConstants.serviceUUID])

        let peerID = lock.withLock { peripheralToPeerID[peripheral.identifier]! }
        delegate?.transport(self, didConnect: peerID)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect to \(peripheral.identifier): \(error?.localizedDescription ?? "unknown")")

        lock.withLock {
            connectingPeripherals.remove(peripheral.identifier)
            connectedPeripheralRefs.removeValue(forKey: peripheral.identifier)
            timedOutPeripherals[peripheral.identifier] = Date()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.info("Disconnected from \(peripheral.identifier)")

        let peerID: PeerID? = lock.withLock {
            let pid = peripheralToPeerID.removeValue(forKey: peripheral.identifier)
            if let pid = pid {
                peerIDToPeripheral.removeValue(forKey: pid)
            }
            peripheralCharacteristics.removeValue(forKey: peripheral.identifier)
            connectedPeripheralRefs.removeValue(forKey: peripheral.identifier)
            connectingPeripherals.remove(peripheral.identifier)
            return pid
        }

        if let peerID = peerID {
            delegate?.transport(self, didDisconnect: peerID)
        }
    }

    private func updateRunningState() {
        if centralManager?.state == .poweredOn || peripheralManager?.state == .poweredOn {
            if state != .running {
                state = .running
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            logger.error("Service discovery error: \(error!.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEConstants.serviceUUID {
            peripheral.discoverCharacteristics(
                [BLEConstants.characteristicUUID],
                for: service
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            logger.error("Characteristic discovery error: \(error!.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == BLEConstants.characteristicUUID {
            lock.withLock {
                peripheralCharacteristics[peripheral.identifier] = char
            }

            // Subscribe for notifications.
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else {
            logger.error("Value update error: \(error!.localizedDescription)")
            return
        }

        guard let data = characteristic.value, !data.isEmpty else { return }

        let peerID: PeerID = lock.withLock {
            peripheralToPeerID[peripheral.identifier] ?? temporaryPeerID(from: peripheral.identifier)
        }

        delegate?.transport(self, didReceiveData: data, from: peerID)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Write error to \(peripheral.identifier): \(error.localizedDescription)")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Notification state error: \(error.localizedDescription)")
        } else {
            logger.info("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") on \(peripheral.identifier)")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didReadRSSI RSSI: NSNumber,
        error: Error?
    ) {
        // RSSI updates handled by PeerManager.
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEService: CBPeripheralManagerDelegate {

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("Peripheral manager powered on")
            updateRunningState()
            startAdvertising()
        case .poweredOff:
            logger.warning("Peripheral manager powered off")
        case .unauthorized:
            logger.error("Peripheral manager unauthorized")
        case .unsupported:
            logger.error("Peripheral manager unsupported")
        case .resetting:
            logger.warning("Peripheral manager resetting")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String: Any]
    ) {
        logger.info("Peripheral manager restoring state")

        // Restore advertised services.
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for svc in services {
                self.service = svc
                if let chars = svc.characteristics {
                    for char in chars {
                        if char.uuid == BLEConstants.characteristicUUID,
                           let mutableChar = char as? CBMutableCharacteristic {
                            self.characteristic = mutableChar
                        }
                    }
                }
            }
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error = error {
            logger.error("Failed to add service: \(error.localizedDescription)")
        } else {
            logger.info("Service added, beginning advertising")
            beginAdvertising()
        }
    }

    public func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: Error?
    ) {
        if let error = error {
            logger.error("Advertising failed: \(error.localizedDescription)")
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        logger.info("Central subscribed: \(central.identifier)")

        let tempPeerID = temporaryPeerID(from: central.identifier)

        lock.withLock {
            if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                subscribedCentrals.append(central)
            }
            centralToPeerID[central.identifier] = tempPeerID
        }

        delegate?.transport(self, didConnect: tempPeerID)
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        logger.info("Central unsubscribed: \(central.identifier)")

        let peerID: PeerID? = lock.withLock {
            subscribedCentrals.removeAll { $0.identifier == central.identifier }
            return centralToPeerID.removeValue(forKey: central.identifier)
        }

        if let peerID = peerID {
            delegate?.transport(self, didDisconnect: peerID)
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            if let data = request.value, !data.isEmpty {
                let peerID: PeerID = lock.withLock {
                    centralToPeerID[request.central.identifier]
                        ?? temporaryPeerID(from: request.central.identifier)
                }
                delegate?.transport(self, didReceiveData: data, from: peerID)
            }

            // Respond to write-with-response.
            peripheral.respond(to: request, withResult: .success)
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        // Respond with the local peer ID bytes for identification.
        request.value = localPeerID.bytes
        peripheral.respond(to: request, withResult: .success)
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Queue was full, now ready to send again. The caller should retry pending notifications.
        logger.debug("Peripheral manager ready to update subscribers")
    }
}
