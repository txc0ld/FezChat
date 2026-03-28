import Foundation
import SwiftData

@Model
final class BreadcrumbPoint {
    @Attribute(.unique)
    var id: UUID

    var friendLocation: FriendLocation?
    var latitude: Double
    var longitude: Double
    var timestamp: Date

    // MARK: - Computed Properties

    var coordinate: GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        friendLocation: FriendLocation? = nil,
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.friendLocation = friendLocation
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}
