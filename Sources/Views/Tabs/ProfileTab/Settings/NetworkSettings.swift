import SwiftUI

private enum NetworkSettingsL10n {
    static let title = String(localized: "profile.settings.network.title", defaultValue: "Network")
    static let transportMode = String(localized: "profile.settings.network.transport_mode.title", defaultValue: "Transport Mode")
    static let transportModeAccessibility = String(localized: "profile.settings.network.transport_mode.accessibility", defaultValue: "Transport mode")
}

// MARK: - NetworkSettings

/// Transport mode picker section for settings.
struct NetworkSettings: View {

    @Binding var transportMode: String

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: NetworkSettingsL10n.title, icon: "network", theme: theme) {
            VStack(spacing: BlipSpacing.md) {
                VStack(alignment: .leading, spacing: BlipSpacing.sm) {
                    Text(NetworkSettingsL10n.transportMode)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.text)

                    Picker(NetworkSettingsL10n.transportMode, selection: $transportMode) {
                        ForEach(TransportMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(NetworkSettingsL10n.transportModeAccessibility)

                    let currentMode = TransportMode(rawValue: transportMode) ?? .allRadios
                    Text(currentMode.caption)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Network Settings") {
    ZStack {
        GradientBackground()

        NetworkSettings(transportMode: .constant(TransportMode.allRadios.rawValue))
            .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
