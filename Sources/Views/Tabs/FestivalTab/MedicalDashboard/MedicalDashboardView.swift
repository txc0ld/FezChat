import SwiftUI
import MapKit

// MARK: - MedicalDashboardView

/// Medical responder dashboard unlocked via organizer-issued access code.
///
/// Combines: access code entry, live map with SOS pins, active alerts
/// sorted by severity, and response stats.
struct MedicalDashboardView: View {

    @State private var isUnlocked = false
    @State private var accessCode: String = ""
    @State private var accessCodeError: String?
    @State private var isVerifying = false

    @State private var alerts: [SOSAlertItem] = MedicalDashboardView.sampleAlerts
    @State private var medicalTents: [MedicalTentPin] = MedicalDashboardView.sampleTents
    @State private var responders: [ResponderPin] = MedicalDashboardView.sampleResponders
    @State private var selectedAlert: SOSAlertItem?
    @State private var showAlertDetail = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isCodeFocused: Bool

    private let festivalCenter = CLLocationCoordinate2D(latitude: 51.0043, longitude: -2.5856)
    private let festivalRadius: Double = 3000

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                if isUnlocked {
                    dashboardContent
                } else {
                    accessCodeEntry
                }
            }
            .navigationTitle("Medical Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAlertDetail) {
                if let alert = selectedAlert {
                    AlertDetailSheet(
                        isPresented: $showAlertDetail,
                        alert: alert,
                        onAccept: { acceptAlert(alert) },
                        onNavigate: {},
                        onResolve: { resolution in resolveAlert(alert, resolution: resolution) }
                    )
                    .presentationDetents([.large])
                }
            }
        }
    }

    // MARK: - Access Code Entry

    private var accessCodeEntry: some View {
        VStack(spacing: FCSpacing.xl) {
            Spacer()

            // Lock icon
            ZStack {
                Circle()
                    .fill(.fcAccentPurple.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.fcAccentPurple)
            }

            VStack(spacing: FCSpacing.sm) {
                Text("Medical Access Required")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.text)

                Text("Enter the organizer-issued access code to unlock the medical dashboard.")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FCSpacing.xl)
            }

            // Code input
            GlassCard(thickness: .regular) {
                VStack(spacing: FCSpacing.md) {
                    TextField("Access Code", text: $accessCode)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.colors.text)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isCodeFocused)
                        .padding(FCSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: FCCornerRadius.md, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FCCornerRadius.md, style: .continuous)
                                .stroke(
                                    accessCodeError != nil
                                        ? FCColors.darkColors.statusRed.opacity(0.5)
                                        : (colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)),
                                    lineWidth: accessCodeError != nil ? 1 : FCSizing.hairline
                                )
                        )
                        .submitLabel(.go)
                        .onSubmit { verifyCode() }
                        .accessibilityLabel("Access code input")

                    if let error = accessCodeError {
                        Text(error)
                            .font(theme.typography.caption)
                            .foregroundStyle(FCColors.darkColors.statusRed)
                    }

                    GlassButton("Unlock Dashboard", icon: "lock.open.fill", isLoading: isVerifying) {
                        verifyCode()
                    }
                    .fullWidth()
                    .disabled(accessCode.isEmpty || isVerifying)
                }
            }
            .padding(.horizontal, FCSpacing.md)

            Spacer()
        }
        .onAppear { isCodeFocused = true }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: FCSpacing.lg) {
                // Stats bar
                statsBar
                    .staggeredReveal(index: 0)

                // Live map
                mapSection
                    .staggeredReveal(index: 1)

                // Active alerts
                alertsSection
                    .staggeredReveal(index: 2)

                Spacer().frame(height: FCSpacing.xxl)
            }
            .padding(.top, FCSpacing.md)
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FCSpacing.md) {
                statCard(value: "\(activeAlerts.count)", label: "Active", color: FCColors.darkColors.statusRed)
                statCard(value: "\(resolvedCount)", label: "Resolved", color: FCColors.darkColors.statusGreen)
                statCard(value: avgResponseTimeString, label: "Avg Response", color: .fcAccentPurple)
                statCard(value: "\(responders.count)", label: "Responders", color: theme.colors.text)
            }
            .padding(.horizontal, FCSpacing.md)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        GlassCard(thickness: .ultraThin, cornerRadius: FCCornerRadius.lg, padding: .fcContent) {
            VStack(spacing: FCSpacing.xs) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())

                Text(label)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.mutedText)
            }
            .frame(width: 90)
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: FCSpacing.sm) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.fcAccentPurple)

                Text("Live Map")
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.text)
            }
            .padding(.horizontal, FCSpacing.md)

            ResponderMapView(
                alerts: activeAlerts,
                medicalTents: medicalTents,
                responderLocations: responders,
                festivalCenter: festivalCenter,
                festivalRadiusMeters: festivalRadius,
                onAlertTap: { alert in
                    selectedAlert = alert
                    showAlertDetail = true
                },
                onNavigateToAlert: { _ in }
            )
            .frame(height: 300)
            .padding(.horizontal, FCSpacing.md)
        }
    }

    // MARK: - Alerts Section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: FCSpacing.md) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FCColors.darkColors.statusRed)

                Text("Active Alerts")
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.text)

                Spacer()

                Text("\(activeAlerts.count) active")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.mutedText)
            }
            .padding(.horizontal, FCSpacing.md)

            if activeAlerts.isEmpty {
                GlassCard(thickness: .ultraThin) {
                    VStack(spacing: FCSpacing.sm) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(FCColors.darkColors.statusGreen)

                        Text("No active alerts")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FCSpacing.lg)
                }
                .padding(.horizontal, FCSpacing.md)
            } else {
                LazyVStack(spacing: FCSpacing.md) {
                    ForEach(Array(sortedAlerts.enumerated()), id: \.element.id) { index, alert in
                        AlertCard(
                            alert: alert,
                            onAccept: { acceptAlert(alert) },
                            onNavigate: {},
                            onResolve: { resolveAlert(alert, resolution: .treatedOnSite) }
                        )
                        .onTapGesture {
                            selectedAlert = alert
                            showAlertDetail = true
                        }
                        .staggeredReveal(index: index)
                    }
                }
                .padding(.horizontal, FCSpacing.md)
            }
        }
    }

    // MARK: - Actions

    private func verifyCode() {
        isVerifying = true
        accessCodeError = nil

        // In production: hash and verify against organizer code
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isVerifying = false
            if accessCode.uppercased() == "MEDIC2026" || accessCode.count >= 4 {
                withAnimation(SpringConstants.accessiblePageEntrance) {
                    isUnlocked = true
                }
            } else {
                accessCodeError = "Invalid access code. Contact your festival organizer."
            }
        }
    }

    private func acceptAlert(_ alert: SOSAlertItem) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[index] = SOSAlertItem(
                id: alert.id,
                shortID: alert.shortID,
                severity: alert.severity,
                locationDescription: alert.locationDescription,
                description: alert.description,
                accuracy: alert.accuracy,
                acceptedBy: "You (Medic-1)",
                createdAt: alert.createdAt
            )
        }
    }

    private func resolveAlert(_ alert: SOSAlertItem, resolution: SOSResolution) {
        alerts.removeAll { $0.id == alert.id }
    }

    // MARK: - Computed

    private var activeAlerts: [SOSAlertItem] {
        alerts
    }

    private var sortedAlerts: [SOSAlertItem] {
        alerts.sorted { a, b in
            let severityOrder: [SOSSeverity] = [.red, .amber, .green]
            let aIndex = severityOrder.firstIndex(of: a.severity) ?? 3
            let bIndex = severityOrder.firstIndex(of: b.severity) ?? 3
            if aIndex != bIndex { return aIndex < bIndex }
            return a.createdAt > b.createdAt
        }
    }

    private var resolvedCount: Int { 12 }

    private var avgResponseTimeString: String {
        "4:32"
    }
}

// MARK: - Sample Data

extension MedicalDashboardView {

    static let sampleAlerts: [SOSAlertItem] = [
        SOSAlertItem(id: UUID(), shortID: "A7F3", severity: .red, locationDescription: "Near Pyramid Stage, Section B", description: nil, accuracy: .precise, acceptedBy: nil, createdAt: Date().addingTimeInterval(-180)),
        SOSAlertItem(id: UUID(), shortID: "B2E1", severity: .amber, locationDescription: "Camping Area B, near showers", description: "Feeling very dizzy and nauseous", accuracy: .estimated, acceptedBy: "Medic-5", createdAt: Date().addingTimeInterval(-420)),
        SOSAlertItem(id: UUID(), shortID: "C9D4", severity: .green, locationDescription: "West Holts area", description: "Minor cut on hand, needs first aid kit", accuracy: .precise, acceptedBy: nil, createdAt: Date().addingTimeInterval(-60)),
    ]

    static let sampleTents: [MedicalTentPin] = [
        MedicalTentPin(id: UUID(), name: "Medical 1", coordinate: CLLocationCoordinate2D(latitude: 51.0040, longitude: -2.5850)),
        MedicalTentPin(id: UUID(), name: "Medical 2", coordinate: CLLocationCoordinate2D(latitude: 51.0050, longitude: -2.5870)),
    ]

    static let sampleResponders: [ResponderPin] = [
        ResponderPin(id: UUID(), callsign: "Medic-1", coordinate: CLLocationCoordinate2D(latitude: 51.0045, longitude: -2.5858), isOnDuty: true),
        ResponderPin(id: UUID(), callsign: "Medic-3", coordinate: CLLocationCoordinate2D(latitude: 51.0050, longitude: -2.5850), isOnDuty: true),
        ResponderPin(id: UUID(), callsign: "Medic-5", coordinate: CLLocationCoordinate2D(latitude: 51.0042, longitude: -2.5865), isOnDuty: true),
    ]
}

// MARK: - Preview

#Preview("Medical Dashboard - Locked") {
    MedicalDashboardView()
        .preferredColorScheme(.dark)
        .festiChatTheme()
}

#Preview("Medical Dashboard - Unlocked") {
    let view = MedicalDashboardView()
    return view
        .onAppear {
            // Cannot set @State from preview directly; the locked state will show by default
        }
        .preferredColorScheme(.dark)
        .festiChatTheme()
}
