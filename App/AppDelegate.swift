import UIKit
import CoreBluetooth

// MARK: - AppDelegate

/// Handles BLE state restoration for background operation.
/// When iOS relaunches the app after suspension/termination due to a BLE event,
/// the delegate receives restoration state and rebuilds the peer table.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - State restoration keys

    /// Restoration identifier for the BLE central manager.
    static let centralRestorationID = "app.blip.central"

    /// Restoration identifier for the BLE peripheral manager.
    static let peripheralRestorationID = "app.blip.peripheral"

    // MARK: - Restored state

    /// Peripherals restored by iOS after background relaunch.
    private(set) var restoredPeripherals: [CBPeripheral] = []

    /// Central scan services restored by iOS after background relaunch.
    private(set) var restoredScanServices: [CBUUID] = []

    /// Peripheral advertising state restored by iOS after background relaunch.
    private(set) var restoredAdvertisementData: [String: Any] = [:]

    // MARK: - UIApplicationDelegate

    /// Background task service — registered once at launch.
    let backgroundTaskService = BackgroundTaskService()

    weak var coordinator: AppCoordinator? {
        didSet {
            flushPendingPushWakeIfNeeded()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register BGTaskScheduler handlers before any tasks can fire.
        backgroundTaskService.registerTasks()

        // Check if launched due to BLE event
        if let bleOptions = launchOptions?[.bluetoothCentrals] as? [String] {
            handleCentralRestoration(identifiers: bleOptions)
        }
        if let blePeripherals = launchOptions?[.bluetoothPeripherals] as? [String] {
            handlePeripheralRestoration(identifiers: blePeripherals)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    // MARK: - Remote Notifications

    private enum RemotePushKind: String {
        case alertOnly = "alert_only"
        case silent = "silent"
        case alertAndSilent = "alert_and_silent"

        var shouldWakeRelay: Bool {
            switch self {
            case .alertOnly:
                return false
            case .silent, .alertAndSilent:
                return true
            }
        }
    }

    private struct PendingPushWake {
        let id = UUID()
        let kind: RemotePushKind
        let completionHandler: (UIBackgroundFetchResult) -> Void
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushTokenManager.shared.didRegisterToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushTokenManager.shared.didFailToRegister(error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let pushKind = classifyRemotePush(userInfo: userInfo)
        guard pushKind.shouldWakeRelay else {
            completionHandler(.noData)
            return
        }

        let pendingWake = PendingPushWake(kind: pushKind, completionHandler: completionHandler)
        if dispatchPushWake(pendingWake) {
            return
        }

        pendingPushWake?.completionHandler(.failed)
        pendingPushWake = pendingWake
        schedulePendingPushWakeTimeout(for: pendingWake.id)
    }

    private var pendingPushWake: PendingPushWake?

    private func classifyRemotePush(userInfo: [AnyHashable: Any]) -> RemotePushKind {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let hasAlert = aps?["alert"] != nil
        let contentAvailable = (aps?["content-available"] as? NSNumber)?.intValue == 1
            || (aps?["content-available"] as? Int) == 1
            || (aps?["content-available"] as? String) == "1"

        switch (hasAlert, contentAvailable) {
        case (true, true):
            return .alertAndSilent
        case (false, true):
            return .silent
        default:
            return .alertOnly
        }
    }

    private func dispatchPushWake(_ pendingWake: PendingPushWake) -> Bool {
        guard let coordinator, coordinator.isReady else { return false }
        coordinator.handlePushWakeUp(
            source: pendingWake.kind.rawValue,
            completionHandler: pendingWake.completionHandler
        )
        return true
    }

    private func flushPendingPushWakeIfNeeded() {
        guard let pendingPushWake else { return }
        guard dispatchPushWake(pendingPushWake) else { return }
        self.pendingPushWake = nil
    }

    private func schedulePendingPushWakeTimeout(for pendingID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self,
                  let pendingPushWake = self.pendingPushWake,
                  pendingPushWake.id == pendingID else { return }
            self.pendingPushWake = nil
            DebugLogger.emit("PUSH", "Push wake timed out before coordinator could drain relay", isError: true)
            pendingPushWake.completionHandler(.failed)
        }
    }

    // MARK: - BLE State Restoration

    /// Handles central manager state restoration.
    /// Called when iOS relaunches the app after a BLE central event in background.
    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        // Restore connected/connecting peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            restoredPeripherals = peripherals
        }

        // Restore scan services
        if let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            restoredScanServices = services
        }

        // Post notification so the mesh layer can rebuild peer table
        NotificationCenter.default.post(
            name: .bleCentralStateRestored,
            object: nil,
            userInfo: [
                "peripherals": restoredPeripherals,
                "scanServices": restoredScanServices
            ]
        )
    }

    /// Handles peripheral manager state restoration.
    /// Called when iOS relaunches the app after a BLE peripheral event in background.
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String: Any]
    ) {
        // Restore advertisement data
        if let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any] {
            restoredAdvertisementData = advertisementData
        }

        // Restore services
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            NotificationCenter.default.post(
                name: .blePeripheralStateRestored,
                object: nil,
                userInfo: [
                    "advertisementData": restoredAdvertisementData,
                    "services": services
                ]
            )
        }
    }

    // MARK: - Private

    private func handleCentralRestoration(identifiers: [String]) {
        guard identifiers.contains(Self.centralRestorationID) else { return }
        // Central manager will be re-created with the same restoration ID
        // by the mesh service layer, triggering willRestoreState
    }

    private func handlePeripheralRestoration(identifiers: [String]) {
        guard identifiers.contains(Self.peripheralRestorationID) else { return }
        // Peripheral manager will be re-created with the same restoration ID
        // by the mesh service layer, triggering willRestoreState
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when BLE central manager state is restored from background.
    static let bleCentralStateRestored = Notification.Name("Blip.bleCentralStateRestored")

    /// Posted when BLE peripheral manager state is restored from background.
    static let blePeripheralStateRestored = Notification.Name("Blip.blePeripheralStateRestored")
}
