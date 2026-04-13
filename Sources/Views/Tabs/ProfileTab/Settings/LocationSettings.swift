import SwiftUI

private enum LocationSettingsL10n {
    static let title = String(localized: "settings.location.title", defaultValue: "Location")
    static let defaultSharing = String(localized: "settings.location.default_sharing", defaultValue: "Default Sharing")
    static let precision = String(localized: "settings.location.precision", defaultValue: "Precision")
    static let precise = String(localized: "settings.location.precise", defaultValue: "Precise")
    static let fuzzy = String(localized: "settings.location.fuzzy", defaultValue: "Fuzzy")
    static let off = String(localized: "common.off", defaultValue: "Off")
    static let precisionAccessibility = String(localized: "settings.location.precision_accessibility_label", defaultValue: "Location sharing precision")
    static let proximityAlerts = String(localized: "settings.location.proximity_alerts", defaultValue: "Proximity Alerts")
    static let proximityAlertsSubtitle = String(localized: "settings.location.proximity_alerts.subtitle", defaultValue: "Get notified when friends are nearby")
    static let breadcrumbTrails = String(localized: "settings.location.breadcrumbs", defaultValue: "Breadcrumb Trails")
    static let breadcrumbTrailsSubtitle = String(localized: "settings.location.breadcrumbs.subtitle", defaultValue: "Track friend movement (opt-in, auto-deleted)")
    static let crowdPulse = String(localized: "settings.location.crowd_pulse", defaultValue: "Crowd Pulse")
    static let crowdPulseSubtitle = String(localized: "settings.location.crowd_pulse.subtitle", defaultValue: "Show crowd density heatmap")
}

// MARK: - LocationSettings

/// Location precision, proximity alerts, breadcrumbs, and crowd pulse section.
struct LocationSettings: View {

    @Binding var locationSharing: String
    @Binding var proximityAlerts: Bool
    @Binding var breadcrumbs: Bool
    @Binding var crowdPulse: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: LocationSettingsL10n.title, icon: "location.fill", theme: theme) {
            VStack(spacing: BlipSpacing.md) {
                SettingsComponents.settingsRow(title: LocationSettingsL10n.defaultSharing, theme: theme) {
                    Picker(LocationSettingsL10n.precision, selection: $locationSharing) {
                        Text(LocationSettingsL10n.precise).tag(LocationPrecision.precise.rawValue)
                        Text(LocationSettingsL10n.fuzzy).tag(LocationPrecision.fuzzy.rawValue)
                        Text(LocationSettingsL10n.off).tag(LocationPrecision.off.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(LocationSettingsL10n.precisionAccessibility)
                }

                SettingsComponents.settingsToggleRow(
                    title: LocationSettingsL10n.proximityAlerts,
                    subtitle: LocationSettingsL10n.proximityAlertsSubtitle,
                    isOn: $proximityAlerts,
                    theme: theme
                )

                SettingsComponents.settingsToggleRow(
                    title: LocationSettingsL10n.breadcrumbTrails,
                    subtitle: LocationSettingsL10n.breadcrumbTrailsSubtitle,
                    isOn: $breadcrumbs,
                    theme: theme
                )

                SettingsComponents.settingsToggleRow(
                    title: LocationSettingsL10n.crowdPulse,
                    subtitle: LocationSettingsL10n.crowdPulseSubtitle,
                    isOn: $crowdPulse,
                    theme: theme
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Location Settings") {
    ZStack {
        GradientBackground()

        LocationSettings(
            locationSharing: .constant(LocationPrecision.fuzzy.rawValue),
            proximityAlerts: .constant(true),
            breadcrumbs: .constant(false),
            crowdPulse: .constant(true)
        )
        .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
