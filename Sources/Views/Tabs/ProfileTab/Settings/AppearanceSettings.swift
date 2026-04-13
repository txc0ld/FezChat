import SwiftUI

private enum AppearanceSettingsL10n {
    static let title = String(localized: "profile.settings.appearance.title", defaultValue: "Appearance")
    static let themeTitle = String(localized: "profile.settings.appearance.theme.title", defaultValue: "Theme")
    static let themeAccessibility = String(localized: "profile.settings.appearance.theme.accessibility", defaultValue: "Theme")
}

// MARK: - AppearanceSettings

/// Theme picker section for settings.
struct AppearanceSettings: View {

    @Binding var appTheme: AppTheme

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: AppearanceSettingsL10n.title, icon: "paintbrush.fill", theme: theme) {
            VStack(spacing: BlipSpacing.md) {
                SettingsComponents.settingsRow(title: AppearanceSettingsL10n.themeTitle, theme: theme) {
                    Picker(AppearanceSettingsL10n.themeTitle, selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { themeOption in
                            Label(themeOption.label, systemImage: themeOption.icon)
                                .tag(themeOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(AppearanceSettingsL10n.themeAccessibility)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Appearance Settings") {
    ZStack {
        GradientBackground()

        AppearanceSettings(appTheme: .constant(.system))
            .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
