import Foundation
import SwiftData

@Model
final class FriendLocation {
    @Attribute(.unique)
    var id: UUID

    var friend: Friend?
    var precisionLevelRaw: String
    var latitude: Double?
    var longitude: Double?
    var geohash: String?
    var areaName: String?
    var accuracy: Double
    var timestamp: Date

    @Relationship(deleteRule: .cascade, inverse: \BreadcrumbPoint.friendLocation)
    var breadcrumbs: [BreadcrumbPoint] = []

    // MARK: - Computed Properties

    var precisionLevel: LocationPrecision {
        get { LocationPrecision(rawValue: precisionLevelRaw) ?? .off }
        set { precisionLevelRaw = newValue.rawValue }
    }

    var coordinate: GeoPoint? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    var hasPreciseLocation: Bool {
        precisionLevel == .precise && latitude != nil && longitude != nil
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        friend: Friend? = nil,
        precisionLevel: LocationPrecision = .off,
        latitude: Double? = nil,
        longitude: Double? = nil,
        geohash: String? = nil,
        areaName: String? = nil,
        accuracy: Double = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.friend = friend
        self.precisionLevelRaw = precisionLevel.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.geohash = geohash
        self.areaName = areaName
        self.accuracy = accuracy
        self.timestamp = timestamp
    }
}
