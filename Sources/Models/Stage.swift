import Foundation
import SwiftData

@Model
final class Stage {
    @Attribute(.unique)
    var id: UUID

    var name: String
    var festival: Festival?
    var coordinatesLatitude: Double
    var coordinatesLongitude: Double

    @Relationship
    var channel: Channel?

    @Relationship(deleteRule: .cascade, inverse: \SetTime.stage)
    var schedule: [SetTime] = []

    // MARK: - Computed Properties

    var coordinates: GeoPoint {
        get { GeoPoint(latitude: coordinatesLatitude, longitude: coordinatesLongitude) }
        set {
            coordinatesLatitude = newValue.latitude
            coordinatesLongitude = newValue.longitude
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        festival: Festival? = nil,
        coordinates: GeoPoint,
        channel: Channel? = nil
    ) {
        self.id = id
        self.name = name
        self.festival = festival
        self.coordinatesLatitude = coordinates.latitude
        self.coordinatesLongitude = coordinates.longitude
        self.channel = channel
    }
}
