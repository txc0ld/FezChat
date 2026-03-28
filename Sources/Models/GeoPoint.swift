import Foundation

/// Lightweight value type for geographic coordinates used across models.
/// Not a SwiftData model itself — stored as decomposed lat/lon Doubles on each model.
struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
