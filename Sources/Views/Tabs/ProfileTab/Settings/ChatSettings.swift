import SwiftUI

private enum ChatSettingsL10n {
    static let title = String(localized: "profile.settings.chat.title", defaultValue: "Chat")
    static let pttMode = String(localized: "profile.settings.chat.ptt_mode.title", defaultValue: "Push-to-Talk Mode")
    static let pttModePicker = String(localized: "profile.settings.chat.ptt_mode.picker", defaultValue: "PTT Mode")
    static let hold = String(localized: "profile.settings.chat.ptt_mode.hold", defaultValue: "Hold")
    static let toggle = String(localized: "profile.settings.chat.ptt_mode.toggle", defaultValue: "Toggle")
    static let pttModeAccessibility = String(localized: "profile.settings.chat.ptt_mode.accessibility", defaultValue: "Push-to-Talk mode")
}

// MARK: - ChatSettings

/// Push-to-talk mode picker section.
struct ChatSettings: View {

    @Binding var pttMode: String

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: ChatSettingsL10n.title, icon: "message.fill", theme: theme) {
            VStack(spacing: BlipSpacing.md) {
                SettingsComponents.settingsRow(title: ChatSettingsL10n.pttMode, theme: theme) {
                    Picker(ChatSettingsL10n.pttModePicker, selection: $pttMode) {
                        Text(ChatSettingsL10n.hold).tag(PTTMode.holdToTalk.rawValue)
                        Text(ChatSettingsL10n.toggle).tag(PTTMode.toggleTalk.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .accessibilityLabel(ChatSettingsL10n.pttModeAccessibility)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Chat Settings") {
    ZStack {
        GradientBackground()

        ChatSettings(pttMode: .constant(PTTMode.holdToTalk.rawValue))
            .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
