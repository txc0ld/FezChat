import Foundation
import SwiftData

// MARK: - Enums

enum AppTheme: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

enum PTTMode: String, Codable, CaseIterable {
    case holdToTalk
    case toggleTalk
}

enum MapStyle: String, Codable, CaseIterable {
    case satellite
    case standard
    case hybrid
}

// MARK: - Model

@Model
final class UserPreferences {
    @Attribute(.unique)
    var id: UUID

    var themeRaw: String
    var defaultLocationSharingRaw: String
    var proximityAlertsEnabled: Bool
    var breadcrumbsEnabled: Bool
    var notificationsEnabled: Bool
    var pttModeRaw: String
    var autoJoinNearbyChannels: Bool
    var crowdPulseVisible: Bool
    var friendFinderMapStyleRaw: String
    var lastFestivalID: UUID?

    // MARK: - Computed Properties

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    var defaultLocationSharing: LocationPrecision {
        get { LocationPrecision(rawValue: defaultLocationSharingRaw) ?? .off }
        set { defaultLocationSharingRaw = newValue.rawValue }
    }

    var pttMode: PTTMode {
        get { PTTMode(rawValue: pttModeRaw) ?? .holdToTalk }
        set { pttModeRaw = newValue.rawValue }
    }

    var friendFinderMapStyle: MapStyle {
        get { MapStyle(rawValue: friendFinderMapStyleRaw) ?? .standard }
        set { friendFinderMapStyleRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        theme: AppTheme = .system,
        defaultLocationSharing: LocationPrecision = .off,
        proximityAlertsEnabled: Bool = true,
        breadcrumbsEnabled: Bool = false,
        notificationsEnabled: Bool = true,
        pttMode: PTTMode = .holdToTalk,
        autoJoinNearbyChannels: Bool = true,
        crowdPulseVisible: Bool = true,
        friendFinderMapStyle: MapStyle = .standard,
        lastFestivalID: UUID? = nil
    ) {
        self.id = id
        self.themeRaw = theme.rawValue
        self.defaultLocationSharingRaw = defaultLocationSharing.rawValue
        self.proximityAlertsEnabled = proximityAlertsEnabled
        self.breadcrumbsEnabled = breadcrumbsEnabled
        self.notificationsEnabled = notificationsEnabled
        self.pttModeRaw = pttMode.rawValue
        self.autoJoinNearbyChannels = autoJoinNearbyChannels
        self.crowdPulseVisible = crowdPulseVisible
        self.friendFinderMapStyleRaw = friendFinderMapStyle.rawValue
        self.lastFestivalID = lastFestivalID
    }
}
