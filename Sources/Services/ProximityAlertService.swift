import Foundation
import CoreLocation
import UserNotifications

@MainActor
@Observable
final class ProximityAlertService {

    private var cooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 300

    func checkProximity(
        friendPins: [FriendMapPin],
        userLocation: CLLocationCoordinate2D,
        preferences: UserPreferences
    ) {
        guard preferences.proximityAlertsEnabled else { return }

        let now = Date()
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) < cooldownInterval }

        let userPoint = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)

        for friend in friendPins where !friend.isOutOfRange {
            let friendKey = friend.id.uuidString
            if let lastAlertAt = cooldowns[friendKey],
               now.timeIntervalSince(lastAlertAt) < cooldownInterval {
                continue
            }

            let friendPoint = CLLocation(
                latitude: friend.coordinate.latitude,
                longitude: friend.coordinate.longitude
            )
            let distance = userPoint.distance(from: friendPoint)
            guard distance <= 100 else { continue }

            DebugLogger.shared.log(
                "PROXIMITY",
                "Friend \(DebugLogger.redact(friend.displayName)) within 100m"
            )

            let content = UNMutableNotificationContent()
            content.title = "Friend Nearby"
            content.body = "\(friend.displayName) is nearby!"
            content.sound = .default
            content.categoryIdentifier = BlipNotificationCategory.friendNearby.rawValue

            let request = UNNotificationRequest(
                identifier: "friend-nearby-\(friendKey)-\(Int(now.timeIntervalSince1970))",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    Task { @MainActor in
                        DebugLogger.shared.log(
                            "PROXIMITY",
                            "Failed to enqueue nearby alert: \(error.localizedDescription)",
                            isError: true
                        )
                    }
                }
            }

            cooldowns[friendKey] = now
        }
    }
}
