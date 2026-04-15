import Foundation
import CoreLocation
import SwiftUI
import SwiftData
import CryptoKit
import BlipProtocol
import BlipMesh
import BlipCrypto
import os.log

/// Bridges real mesh location data to FriendFinderMapView.
///
/// Listens for `.didReceiveLocationPacket` notifications from MessageService,
/// deserializes LocationPayloads, and publishes live [FriendMapPin] state.
/// Also handles broadcasting the user's own location and "I'm Here" beacons.
@MainActor
@Observable
final class FriendFinderViewModel {

    // MARK: - Published State

    /// Live friend locations for the map.
    var friends: [FriendMapPin] = []

    /// Active beacons (user's + received).
    var beacons: [BeaconPin] = []

    /// User's current location.
    var userLocation: CLLocationCoordinate2D?

    /// Whether the user is actively sharing their location.
    var isSharingLocation = false

    // MARK: - Dependencies

    private let locationService: LocationService
    private let modelContainer: ModelContainer
    private let proximityAlertService: ProximityAlertService
    private let logger = Logger(subsystem: "com.blip", category: "FriendFinder")

    /// Tracked peer locations: PeerID hex → most recent location data.
    private var peerLocations: [String: PeerLocationEntry] = [:]

    @ObservationIgnored nonisolated(unsafe) private var locationObservation: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var beaconObservation: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var cleanupTimer: Timer?

    private struct PeerLocationEntry {
        let peerID: PeerID
        let payload: LocationPayload
        let receivedAt: Date
    }

    // MARK: - Init

    init(
        locationService: LocationService = LocationService(),
        modelContainer: ModelContainer,
        proximityAlertService: ProximityAlertService
    ) {
        self.locationService = locationService
        self.modelContainer = modelContainer
        self.proximityAlertService = proximityAlertService
        setupObservers()
        startCleanupTimer()
    }

    deinit {
        if let obs = locationObservation {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = beaconObservation {
            NotificationCenter.default.removeObserver(obs)
        }
        cleanupTimer?.invalidate()
    }

    // MARK: - Observers

    private func setupObservers() {
        locationObservation = NotificationCenter.default.addObserver(
            forName: .didReceiveLocationPacket,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let packet = notification.userInfo?["packet"] as? Packet,
                  let peerID = notification.userInfo?["peerID"] as? PeerID else { return }

            Task { @MainActor in
                self?.handleLocationPacket(packet, from: peerID)
            }
        }
    }

    // MARK: - Location Packet Handling

    private func handleLocationPacket(_ packet: Packet, from peerID: PeerID) {
        switch packet.type {
        case .proximityPing:
            handleProximityPing(packet, from: peerID)
        default:
            guard let payload = LocationPayload.deserialize(from: packet.payload) else {
                logger.warning("Failed to deserialize location payload from \(peerID)")
                return
            }

            let key = peerID.description

            if payload.isBeacon {
                handleBeacon(payload, from: peerID)
                return
            }

            // Update or insert peer location.
            peerLocations[key] = PeerLocationEntry(
                peerID: peerID,
                payload: payload,
                receivedAt: Date()
            )

            rebuildFriendPins()
        }
    }

    private func handleProximityPing(_ packet: Packet, from peerID: PeerID) {
        guard ProximityPingPayload.deserialize(from: packet.payload) != nil else { return }

        let key = peerID.description
        if let entry = peerLocations[key] {
            peerLocations[key] = PeerLocationEntry(
                peerID: entry.peerID,
                payload: entry.payload,
                receivedAt: Date()
            )
            rebuildFriendPins()
        }
    }

    private func handleBeacon(_ payload: LocationPayload, from peerID: PeerID) {
        let beacon = BeaconPin(
            id: UUID(),
            label: "I'm here!",
            coordinate: CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude),
            createdBy: peerID.description,
            expiresAt: Date().addingTimeInterval(LocationPayload.beaconTTL)
        )

        // Replace existing beacon from same peer or append.
        beacons.removeAll { $0.createdBy == peerID.description }
        beacons.append(beacon)
    }

    // MARK: - Pin Building

    private func rebuildFriendPins() {
        let userCoord = userLocation

        friends = peerLocations.values.map { entry in
            let peerInfo = PeerStore.shared.findPeer(byPeerIDBytes: entry.peerID.bytes)
            let coord = CLLocationCoordinate2D(
                latitude: entry.payload.latitude,
                longitude: entry.payload.longitude
            )
            let accuracy = Double(entry.payload.accuracy)
            let distance: Double? = userCoord.map { user in
                CLLocation(latitude: user.latitude, longitude: user.longitude)
                    .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            }
            let rssiMeters: Double? = {
                guard let peerInfo, peerInfo.hasSignalData else { return nil }
                return RSSIDistance.meters(fromRSSI: peerInfo.rssi)
            }()

            let precision: LocationPinPrecision
            if accuracy < 20 {
                precision = .precise
            } else if accuracy < 100 {
                precision = .fuzzy
            } else {
                precision = .off
            }

            return FriendMapPin(
                id: stableUUID(for: entry.peerID),
                displayName: peerInfo?.username
                    ?? String(entry.peerID.description.prefix(8)),
                coordinate: coord,
                precision: precision,
                color: stableColor(for: entry.peerID),
                lastUpdated: entry.receivedAt,
                accuracyMeters: accuracy,
                distanceFromUser: distance,
                rssiMeters: rssiMeters,
                isOutOfRange: entry.payload.age > LocationPayload.updateInterval * 3
            )
        }

        evaluateProximityAlerts()
    }

    // MARK: - Stale Cleanup

    private func startCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStalePeers()
            }
        }
    }

    private func cleanupStalePeers() {
        let staleThreshold = LocationPayload.updateInterval * 3 // 90s
        let now = Date()

        let before = peerLocations.count
        peerLocations = peerLocations.filter { _, entry in
            now.timeIntervalSince(entry.receivedAt) < staleThreshold
        }

        // Clean expired beacons.
        beacons.removeAll { $0.expiresAt < now }

        if peerLocations.count != before {
            rebuildFriendPins()
        }
    }

    // MARK: - Broadcast Own Location

    /// Broadcast user's location over the mesh. Called when sharing is enabled.
    func broadcastLocation() {
        guard isSharingLocation,
              let location = locationService.currentLocation else { return }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: Float(location.horizontalAccuracy)
        )

        let data = payload.serialize()
        NotificationCenter.default.post(
            name: .shouldBroadcastPacket,
            object: nil,
            userInfo: ["data": buildLocationPacketData(payload: data, type: .locationShare)]
        )
    }

    /// Drop an "I'm Here" beacon at the user's current location.
    func dropBeacon() {
        guard let location = locationService.currentLocation else { return }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: Float(location.horizontalAccuracy),
            isBeacon: true
        )

        let data = payload.serialize()
        NotificationCenter.default.post(
            name: .shouldBroadcastPacket,
            object: nil,
            userInfo: ["data": buildLocationPacketData(payload: data, type: .iAmHereBeacon)]
        )

        // Add to local beacons too.
        beacons.append(BeaconPin(
            id: UUID(),
            label: "I'm here!",
            coordinate: location.coordinate,
            createdBy: "You",
            expiresAt: Date().addingTimeInterval(LocationPayload.beaconTTL)
        ))
    }

    func sendProximityPing() {
        do {
            guard let identity = try KeyManager.shared.loadIdentity() else {
                DebugLogger.shared.log("PEER", "Failed to send proximity ping: missing identity", isError: true)
                return
            }
            let payload = ProximityPingPayload()
            let packet = Packet(
                type: .proximityPing,
                ttl: 2,
                timestamp: Packet.currentTimestamp(),
                flags: PacketFlags(),
                senderID: identity.peerID,
                payload: payload.serialize()
            )
            let data = try PacketSerializer.encode(packet)
            NotificationCenter.default.post(
                name: .shouldBroadcastPacket,
                object: nil,
                userInfo: ["data": data]
            )
        } catch {
            DebugLogger.shared.log("PEER", "Failed to send proximity ping: \(error)", isError: true)
        }
    }

    // MARK: - Helpers

    private func buildLocationPacketData(payload: Data, type: BlipProtocol.MessageType) -> Data {
        guard let identity = try? KeyManager.shared.loadIdentity() else {
            logger.error("No identity for location broadcast")
            return Data()
        }

        let packet = Packet(
            type: type,
            ttl: 3,
            timestamp: Packet.currentTimestamp(),
            flags: PacketFlags(),
            senderID: identity.peerID,
            payload: payload
        )

        do {
            return try PacketSerializer.encode(packet)
        } catch {
            logger.error("Failed to encode location packet: \(error.localizedDescription)")
            return Data()
        }
    }

    /// Update user's own coordinate from LocationService.
    func updateUserLocation(_ location: CLLocation) {
        userLocation = location.coordinate
        evaluateProximityAlerts()
    }

    private func evaluateProximityAlerts() {
        guard let userLocation else { return }

        do {
            let context = ModelContext(modelContainer)
            let preferences = try context.fetch(FetchDescriptor<UserPreferences>()).first ?? UserPreferences()
            proximityAlertService.checkProximity(
                friendPins: friends,
                userLocation: userLocation,
                preferences: preferences
            )
        } catch {
            DebugLogger.shared.log(
                "PROXIMITY",
                "Failed to load preferences for proximity alerts: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func stableUUID(for peerID: PeerID) -> UUID {
        let digest = SHA256.hash(data: peerID.bytes)
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func stableColor(for peerID: PeerID) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint]
        return palette[Int(peerID.bytes[0]) % palette.count]
    }
}

// Notification names (.didReceiveLocationPacket, .didReceivePTTAudio)
// are defined in MessageService.swift
