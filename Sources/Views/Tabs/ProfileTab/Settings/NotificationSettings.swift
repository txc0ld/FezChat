import SwiftUI

private enum NotificationSettingsL10n {
    static let title = String(localized: "profile.settings.notifications.title", defaultValue: "Notifications")
    static let pushNotifications = String(localized: "profile.settings.notifications.push.title", defaultValue: "Push Notifications")
    static let pushNotificationsSubtitle = String(localized: "profile.settings.notifications.push.subtitle", defaultValue: "Receive notifications for messages")
    static let autoJoinChannels = String(localized: "profile.settings.notifications.auto_join.title", defaultValue: "Auto-Join Channels")
    static let autoJoinChannelsSubtitle = String(localized: "profile.settings.notifications.auto_join.subtitle", defaultValue: "Automatically join nearby location channels")
}

// MARK: - NotificationSettings

/// Push notifications and auto-join channels section.
struct NotificationSettings: View {

    @Binding var pushNotifications: Bool
    @Binding var autoJoinChannels: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: NotificationSettingsL10n.title, icon: "bell.fill", theme: theme) {
            VStack(spacing: BlipSpacing.md) {
                SettingsComponents.settingsToggleRow(
                    title: NotificationSettingsL10n.pushNotifications,
                    subtitle: NotificationSettingsL10n.pushNotificationsSubtitle,
                    isOn: $pushNotifications,
                    theme: theme
                )

                SettingsComponents.settingsToggleRow(
                    title: NotificationSettingsL10n.autoJoinChannels,
                    subtitle: NotificationSettingsL10n.autoJoinChannelsSubtitle,
                    isOn: $autoJoinChannels,
                    theme: theme
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Notification Settings") {
    ZStack {
        GradientBackground()

        NotificationSettings(
            pushNotifications: .constant(true),
            autoJoinChannels: .constant(true)
        )
        .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
