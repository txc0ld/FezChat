import SwiftUI

private enum SecuritySettingsL10n {
    static let title = String(localized: "profile.settings.security.title", defaultValue: "Security")
    static let recoveryKitExport = String(localized: "profile.settings.security.recovery_kit_export", defaultValue: "Recovery Kit Export")
    static let recoveryKitSubtitle = String(localized: "profile.settings.security.recovery_kit_export.subtitle", defaultValue: "Unavailable in this build until file export is wired")
}

// MARK: - SecuritySettings

/// Recovery kit export section (currently disabled).
struct SecuritySettings: View {

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: SecuritySettingsL10n.title, icon: "lock.fill", theme: theme) {
            // The entire section is currently planned work — lead with the
            // "Coming Soon" header so the card doesn't read as a shipped
            // feature. TODO: BDEV-136 — wire recovery kit export with
            // password-protected file.
            VStack(alignment: .leading, spacing: BlipSpacing.sm) {
                SettingsComponents.comingSoonHeader(theme: theme)

                SettingsComponents.settingsDisabledRow(
                    title: SecuritySettingsL10n.recoveryKitExport,
                    subtitle: SecuritySettingsL10n.recoveryKitSubtitle,
                    icon: "square.and.arrow.up",
                    theme: theme
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Security Settings") {
    ZStack {
        GradientBackground()

        SecuritySettings()
            .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
