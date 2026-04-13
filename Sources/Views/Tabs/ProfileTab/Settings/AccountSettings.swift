import SwiftUI

// MARK: - AccountSettings

/// Sign out, export data, and delete account section.
struct AccountSettings: View {

    @Binding var showSignOutConfirm: Bool
    let isExporting: Bool
    let isDeleting: Bool
    let onExportData: () -> Void
    let onDeleteAccount: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsComponents.settingsGroup(title: "Account", icon: "person.crop.circle", theme: theme) {
            VStack(alignment: .leading, spacing: BlipSpacing.md) {
                actionRow(
                    title: "Sign Out",
                    subtitle: "Clear local session and return to setup",
                    icon: "rectangle.portrait.and.arrow.right"
                ) {
                    showSignOutConfirm = true
                }
                .accessibilityLabel("Sign out")

                Divider()
                    .opacity(0.15)

                actionRow(
                    title: "Export My Data",
                    subtitle: isExporting
                        ? "Preparing your JSON export..."
                        : "Create a JSON archive of profile, messages, friends, and saved events",
                    icon: "square.and.arrow.up",
                    showsProgress: isExporting,
                    isDisabled: isExporting || isDeleting,
                    action: onExportData
                )
                .accessibilityLabel("Export my data")

                actionRow(
                    title: "Delete Account & Data",
                    subtitle: isDeleting
                        ? "Deleting your account..."
                        : "Permanently remove your Blip account from the server and this device",
                    icon: "trash",
                    isDestructive: true,
                    showsProgress: isDeleting,
                    isDisabled: isExporting || isDeleting,
                    action: onDeleteAccount
                )
                .accessibilityLabel("Delete account and data")
            }
        }
    }

    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        isDestructive: Bool = false,
        showsProgress: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BlipSpacing.sm) {
                VStack(alignment: .leading, spacing: BlipSpacing.xs) {
                    Text(title)
                        .font(theme.typography.body)
                        .foregroundStyle(
                            isDestructive ? theme.colors.statusRed : theme.colors.text
                        )

                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if showsProgress {
                    ProgressView()
                        .tint(isDestructive ? theme.colors.statusRed : .blipAccentPurple)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isDestructive ? theme.colors.statusRed : theme.colors.mutedText
                        )
                }
            }
            .frame(minHeight: BlipSizing.minTapTarget)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview("Account Settings") {
    ZStack {
        GradientBackground()

        AccountSettings(
            showSignOutConfirm: .constant(false),
            isExporting: false,
            isDeleting: false,
            onExportData: {},
            onDeleteAccount: {}
        )
            .padding()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}
