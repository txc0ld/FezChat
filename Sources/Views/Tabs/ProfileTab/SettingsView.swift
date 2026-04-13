import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SettingsView

/// App settings coordinator. All `@AppStorage` lives here and is passed
/// as `@Binding` to individual section views under `Settings/`.
struct SettingsView: View {

    var profileViewModel: ProfileViewModel? = nil
    var onSignOut: (() -> Bool)? = nil

    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    @AppStorage("locationPrecision") private var locationSharing: String = LocationPrecision.fuzzy.rawValue
    @AppStorage("pushNotifications") private var notificationsEnabled: Bool = true
    @AppStorage("proximityAlerts") private var proximityAlerts: Bool = true
    @AppStorage("pttMode") private var pttModeRaw: String = PTTMode.holdToTalk.rawValue
    @AppStorage("autoJoinChannels") private var autoJoinChannels: Bool = true
    @AppStorage("crowdPulse") private var crowdPulseVisible: Bool = true
    @AppStorage("breadcrumbTrails") private var breadcrumbs: Bool = false
    @AppStorage("transportMode") private var transportModeRaw: String = TransportMode.allRadios.rawValue
    @State private var showSignOutConfirm: Bool = false
    @State private var showDeleteAccountConfirm: Bool = false
    @State private var showDeleteAccountTextPrompt: Bool = false
    @State private var deleteConfirmationText: String = ""
    @State private var isExportingAccountData = false
    @State private var isDeletingAccount = false
    @State private var exportFileURL: URL?
    @State private var actionErrorMessage: String?
    @State private var isHydratingPreferences = false

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BlipSpacing.lg) {
                    AppearanceSettings(appTheme: themeBinding)
                        .staggeredReveal(index: 0)

                    NetworkSettings(transportMode: $transportModeRaw)
                        .staggeredReveal(index: 1)

                    LocationSettings(
                        locationSharing: locationSharingBinding,
                        proximityAlerts: proximityAlertsBinding,
                        breadcrumbs: breadcrumbsBinding,
                        crowdPulse: crowdPulseBinding
                    )
                    .staggeredReveal(index: 2)

                    NotificationSettings(
                        pushNotifications: notificationsBinding,
                        autoJoinChannels: autoJoinChannelsBinding
                    )
                    .staggeredReveal(index: 3)

                    ChatSettings(pttMode: pttModeBinding)
                        .staggeredReveal(index: 4)

                    SecuritySettings()
                        .staggeredReveal(index: 5)

                    AboutSettings()
                        .staggeredReveal(index: 6)

                    AccountSettings(
                        showSignOutConfirm: $showSignOutConfirm,
                        isExporting: isExportingAccountData,
                        isDeleting: isDeletingAccount,
                        onExportData: startAccountExport,
                        onDeleteAccount: { showDeleteAccountConfirm = true }
                    )
                        .staggeredReveal(index: 7)

                    Spacer().frame(height: BlipSpacing.xxl)
                }
                .padding(BlipSpacing.md)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await profileViewModel?.loadProfile()
            hydrateFromPreferences()
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                if let onSignOut, onSignOut() {
                    dismiss()
                } else if onSignOut == nil {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    dismiss()
                } else {
                    actionErrorMessage = "Failed to clear local account data."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local identity on this device, wipes local data, and returns you to setup. Remote account restore is not available yet.")
        }
        .alert("Delete your account?", isPresented: $showDeleteAccountConfirm) {
            Button("Delete", role: .destructive) {
                deleteConfirmationText = ""
                showDeleteAccountTextPrompt = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove your account from Blip servers and wipe this device after the server deletion succeeds.")
        }
        .alert("Type DELETE to confirm", isPresented: $showDeleteAccountTextPrompt) {
            TextField("DELETE", text: $deleteConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            .disabled(deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")
            Button("Cancel", role: .cancel) {
                deleteConfirmationText = ""
            }
        } message: {
            Text("Enter DELETE to confirm permanent account deletion.")
        }
        .alert("Account Action Failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown account error occurred.")
        }
        .sheet(isPresented: Binding(
            get: { exportFileURL != nil },
            set: { if !$0 { exportFileURL = nil } }
        )) {
            if let exportFileURL {
                AccountExportShareSheet(fileURL: exportFileURL)
            }
        }
    }

    // MARK: - Actions

    private func hydrateFromPreferences() {
        guard let preferences = profileViewModel?.preferences else { return }

        isHydratingPreferences = true
        selectedTheme = preferences.theme
        locationSharing = preferences.defaultLocationSharing.rawValue
        notificationsEnabled = preferences.notificationsEnabled
        proximityAlerts = preferences.proximityAlertsEnabled
        pttModeRaw = preferences.pttMode.rawValue
        autoJoinChannels = preferences.autoJoinNearbyChannels
        crowdPulseVisible = preferences.crowdPulseVisible
        breadcrumbs = preferences.breadcrumbsEnabled
        isHydratingPreferences = false
    }

    private func startAccountExport() {
        guard !isExportingAccountData else { return }

        Task {
            isExportingAccountData = true
            defer { isExportingAccountData = false }

            guard let profileViewModel else {
                actionErrorMessage = "Profile data is not available yet."
                return
            }

            do {
                let export = try await profileViewModel.exportAccountData()
                exportFileURL = export.url
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }

        isDeletingAccount = true
        defer {
            isDeletingAccount = false
            deleteConfirmationText = ""
        }

        guard let profileViewModel else {
            actionErrorMessage = "Profile data is not available yet."
            return
        }

        do {
            try await profileViewModel.deleteAccountRemotely()
        } catch {
            actionErrorMessage = "Server deletion failed. Try again later. \(error.localizedDescription)"
            return
        }

        guard let onSignOut else {
            actionErrorMessage = "Account was deleted on the server, but this build cannot reset local state automatically."
            return
        }

        if onSignOut() {
            dismiss()
        } else {
            actionErrorMessage = "Account was deleted on the server, but local data cleanup failed."
        }
    }

    // MARK: - Preference Bindings

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { profileViewModel?.preferences?.theme ?? selectedTheme },
            set: { newValue in
                selectedTheme = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(theme: newValue)
            }
        )
    }

    private var locationSharingBinding: Binding<String> {
        Binding(
            get: { profileViewModel?.preferences?.defaultLocationSharing.rawValue ?? locationSharing },
            set: { newValue in
                locationSharing = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(defaultLocationSharing: LocationPrecision(rawValue: newValue) ?? .off)
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { profileViewModel?.preferences?.notificationsEnabled ?? notificationsEnabled },
            set: { newValue in
                notificationsEnabled = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(notificationsEnabled: newValue)
            }
        )
    }

    private var proximityAlertsBinding: Binding<Bool> {
        Binding(
            get: { profileViewModel?.preferences?.proximityAlertsEnabled ?? proximityAlerts },
            set: { newValue in
                proximityAlerts = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(proximityAlertsEnabled: newValue)
            }
        )
    }

    private var breadcrumbsBinding: Binding<Bool> {
        Binding(
            get: { profileViewModel?.preferences?.breadcrumbsEnabled ?? breadcrumbs },
            set: { newValue in
                breadcrumbs = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(breadcrumbsEnabled: newValue)
            }
        )
    }

    private var crowdPulseBinding: Binding<Bool> {
        Binding(
            get: { profileViewModel?.preferences?.crowdPulseVisible ?? crowdPulseVisible },
            set: { newValue in
                crowdPulseVisible = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(crowdPulseVisible: newValue)
            }
        )
    }

    private var pttModeBinding: Binding<String> {
        Binding(
            get: { profileViewModel?.preferences?.pttMode.rawValue ?? pttModeRaw },
            set: { newValue in
                pttModeRaw = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(pttMode: PTTMode(rawValue: newValue) ?? .holdToTalk)
            }
        )
    }

    private var autoJoinChannelsBinding: Binding<Bool> {
        Binding(
            get: { profileViewModel?.preferences?.autoJoinNearbyChannels ?? autoJoinChannels },
            set: { newValue in
                autoJoinChannels = newValue
                guard !isHydratingPreferences else { return }
                profileViewModel?.updatePreferences(autoJoinNearbyChannels: newValue)
            }
        )
    }
}

#if canImport(UIKit)
private struct AccountExportShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
private struct AccountExportShareSheet: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: BlipSpacing.md) {
            Text("Account export saved")
                .font(.headline)
            Text(fileURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
#endif

// MARK: - Preview

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
    .blipTheme()
}

#Preview("Settings - Light") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.light)
    .blipTheme()
}
