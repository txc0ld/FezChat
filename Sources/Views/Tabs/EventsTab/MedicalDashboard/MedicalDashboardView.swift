import SwiftUI

// MARK: - MedicalDashboardView

/// SOS responder dashboard — three states: not a responder, on-duty alert list, active alert detail.
struct MedicalDashboardView: View {

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.theme) private var theme
    @State private var showResolveDialog = false

    private var sosViewModel: SOSViewModel? { coordinator.sosViewModel }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: BlipSpacing.xl) {
                        Spacer().frame(height: BlipSpacing.md)

                        if let vm = sosViewModel, vm.isMedicalResponder {
                            if let accepted = vm.acceptedAlert {
                                activeAlertView(alert: accepted)
                            } else {
                                dutyToggleCard(vm: vm)
                                    .staggeredReveal(index: 0)
                                alertListView(vm: vm)
                                    .staggeredReveal(index: 1)
                            }
                        } else {
                            notResponderView
                                .staggeredReveal(index: 0)
                        }

                        Spacer().frame(height: BlipSpacing.xxl)
                    }
                    .padding(.horizontal, BlipSpacing.md)
                }
            }
            .navigationTitle("Medical Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await sosViewModel?.refreshVisibleAlerts()
        }
    }

    // MARK: - State 1: Not a Responder

    private var notResponderView: some View {
        GlassCard(thickness: .regular) {
            VStack(spacing: BlipSpacing.md) {
                Image(systemName: "cross.case.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(theme.colors.mutedText)

                Text("Not a Responder")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.text)

                Text("You are not registered as a medical responder for this event. Contact the event organizer to get responder access.")
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BlipSpacing.lg)
        }
    }

    // MARK: - State 2: Duty Toggle + Alert List

    private func dutyToggleCard(vm: SOSViewModel) -> some View {
        GlassCard(thickness: .regular) {
            HStack {
                VStack(alignment: .leading, spacing: BlipSpacing.xs) {
                    Text(vm.responderCallsign ?? "Responder")
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.text)

                    Text(vm.isOnDuty ? "On duty" : "Off duty")
                        .font(theme.typography.caption)
                        .foregroundStyle(vm.isOnDuty ? theme.colors.statusGreen : theme.colors.mutedText)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { vm.isOnDuty },
                    set: { _ in Task { await sosViewModel?.toggleOnDuty() } }
                ))
                .tint(.blipAccentPurple)
                .labelsHidden()
                .accessibilityLabel(vm.isOnDuty ? "Go off duty" : "Go on duty")
            }
        }
    }

    private func alertListView(vm: SOSViewModel) -> some View {
        Group {
            if vm.visibleAlerts.isEmpty {
                GlassCard(thickness: .ultraThin) {
                    HStack(spacing: BlipSpacing.sm) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(theme.colors.statusGreen)
                        Text("No active SOS alerts")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BlipSpacing.md)
                }
            } else {
                LazyVStack(spacing: BlipSpacing.sm) {
                    ForEach(vm.visibleAlerts) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
    }

    private func alertRow(_ alert: SOSViewModel.SOSAlertInfo) -> some View {
        GlassCard(thickness: .regular) {
            HStack(spacing: BlipSpacing.sm) {
                Circle().fill(severityColor(alert.severity)).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: BlipSpacing.xs) {
                    Text(alert.severity.rawValue.uppercased())
                        .font(theme.typography.caption).fontWeight(.bold)
                        .foregroundStyle(severityColor(alert.severity))
                    if let distance = alert.distance {
                        Text("~\(Int(distance))m away")
                            .font(theme.typography.secondary).foregroundStyle(theme.colors.text)
                    }
                    Text(elapsedTime(since: alert.createdAt))
                        .font(theme.typography.caption).foregroundStyle(theme.colors.mutedText)
                }
                Spacer()
                Button {
                    Task { await sosViewModel?.acceptAlert(alert) }
                } label: {
                    Text("Accept").font(theme.typography.body).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, BlipSpacing.md).padding(.vertical, BlipSpacing.sm)
                        .background(.blipAccentPurple, in: Capsule())
                }
                .accessibilityLabel("Accept \(alert.severity.rawValue) alert")
            }
        }
    }

    // MARK: - State 3: Active Alert Detail

    private func activeAlertView(alert: SOSAlert) -> some View {
        VStack(spacing: BlipSpacing.md) {
            GlassCard(thickness: .regular) {
                VStack(alignment: .leading, spacing: BlipSpacing.md) {
                    HStack {
                        Circle()
                            .fill(severityColor(alert.severity))
                            .frame(width: 12, height: 12)
                        Text("Active — \(alert.severity.rawValue.uppercased())")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.colors.text)
                    }

                    if let reporter = alert.reporter?.resolvedDisplayName {
                        infoRow(icon: "person.fill", text: reporter)
                    }

                    infoRow(icon: "mappin.and.ellipse", text: alert.fuzzyLocation)

                    infoRow(
                        icon: "location.fill",
                        text: String(format: "%.5f, %.5f", alert.preciseLocationLatitude, alert.preciseLocationLongitude)
                    )

                    if let message = alert.message, !message.isEmpty {
                        infoRow(icon: "text.bubble.fill", text: message)
                    }

                    infoRow(icon: "clock.fill", text: elapsedTime(since: alert.createdAt))
                }
            }

            HStack(spacing: BlipSpacing.sm) {
                Button {
                    let url = URL(string: "maps://?daddr=\(alert.preciseLocationLatitude),\(alert.preciseLocationLongitude)&dirflg=w")
                    if let url { UIApplication.shared.open(url) }
                } label: {
                    Label("Navigate", systemImage: "location.fill").font(theme.typography.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, BlipSpacing.sm)
                }
                .buttonStyle(.borderedProminent).tint(.blipAccentPurple)
                .accessibilityLabel("Navigate to alert location")

                Button { showResolveDialog = true } label: {
                    Label("Resolve", systemImage: "checkmark.circle.fill").font(theme.typography.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, BlipSpacing.sm)
                }
                .buttonStyle(.borderedProminent).tint(theme.colors.statusGreen)
                .accessibilityLabel("Resolve alert")
            }
            .confirmationDialog("Resolve Alert", isPresented: $showResolveDialog, titleVisibility: .visible) {
                Button("Treated on site") { Task { await sosViewModel?.resolveAlert(resolution: .treatedOnSite) } }
                Button("Transported") { Task { await sosViewModel?.resolveAlert(resolution: .transported) } }
                Button("False alarm") { Task { await sosViewModel?.resolveAlert(resolution: .falseAlarm) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Helpers
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BlipSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.mutedText)
                .frame(width: 18)
            Text(text)
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.text)
        }
    }

    private func severityColor(_ severity: SOSSeverity) -> Color {
        switch severity {
        case .red: return theme.colors.statusRed
        case .amber: return theme.colors.statusAmber
        case .green: return theme.colors.statusGreen
        }
    }

    private func elapsedTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m ago"
    }
}

// MARK: - Previews

#Preview("Not a Responder") {
    MedicalDashboardView()
        .preferredColorScheme(.dark)
        .blipTheme()
}
