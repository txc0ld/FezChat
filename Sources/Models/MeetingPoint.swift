import Foundation
import SwiftData

@Model
final class MeetingPoint {
    @Attribute(.unique)
    var id: UUID

    var creator: User?
    var channel: Channel?
    var coordinatesLatitude: Double
    var coordinatesLongitude: Double
    var label: String
    var expiresAt: Date

    // MARK: - Computed Properties

    var coordinates: GeoPoint {
        get { GeoPoint(latitude: coordinatesLatitude, longitude: coordinatesLongitude) }
        set {
            coordinatesLatitude = newValue.latitude
            coordinatesLongitude = newValue.longitude
        }
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        creator: User? = nil,
        channel: Channel? = nil,
        coordinates: GeoPoint,
        label: String,
        expiresAt: Date
    ) {
        self.id = id
        self.creator = creator
        self.channel = channel
        self.coordinatesLatitude = coordinates.latitude
        self.coordinatesLongitude = coordinates.longitude
        self.label = label
        self.expiresAt = expiresAt
    }
}
