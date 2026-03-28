import Foundation
import SwiftData

// MARK: - Enums

enum HeatLevel: String, Codable, CaseIterable {
    case quiet
    case moderate
    case busy
    case packed
}

// MARK: - Model

/// CrowdPulse is transient data representing crowd density at a geohash location.
/// Persisted for short-term caching but frequently updated and evicted.
@Model
final class CrowdPulse {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var geohash: String

    var peerCount: Int
    var lastUpdated: Date
    var heatLevelRaw: String

    // MARK: - Computed Properties

    var heatLevel: HeatLevel {
        get { HeatLevel(rawValue: heatLevelRaw) ?? .quiet }
        set { heatLevelRaw = newValue.rawValue }
    }

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 300 // 5 minutes
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        geohash: String,
        peerCount: Int = 0,
        lastUpdated: Date = Date(),
        heatLevel: HeatLevel = .quiet
    ) {
        self.id = id
        self.geohash = geohash
        self.peerCount = peerCount
        self.lastUpdated = lastUpdated
        self.heatLevelRaw = heatLevel.rawValue
    }
}
