import SwiftUI

// MARK: - AlertCard

/// Glass card for a single SOS alert in the medical dashboard.
///
/// Shows severity color, elapsed time, location description, and
/// Accept/Navigate/Resolve action buttons.
struct AlertCard: View {

    let alert: SOSAlertItem
    var onAccept: (() -> Void)?
    var onNavigate: (() -> Void)?
    var onResolve: (() -> Void)?

    @State private var elapsedText: String = ""
    @State private var isPulsing = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassCard(thickness: .regular, cornerRadius: FCCornerRadius.xl) {
            VStack(alignment: .leading, spacing: FCSpacing.md) {
                // Header: severity + time
                headerRow

                // Location
                locationRow

                // Description
                if let description = alert.description {
                    Text(description)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.mutedText)
                        .lineLimit(2)
                }

                // Status badge
                if let acceptedBy = alert.acceptedBy {
                    acceptedBadge(callsign: acceptedBy)
                }

                // Actions
                actionButtons
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: FCCornerRadius.xl, style: .continuous)
                .stroke(severityColor.opacity(0.3), lineWidth: 1.5)
        )
        .onAppear {
            updateElapsed()
            startPulseIfCritical()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: FCSpacing.sm) {
            // Severity indicator
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.2))
                    .frame(width: 36, height: 36)

                Circle()
                    .fill(severityColor)
                    .frame(width: 12, height: 12)

                if alert.severity == .red && !SpringConstants.isReduceMotionEnabled {
                    Circle()
                        .stroke(severityColor.opacity(0.5), lineWidth: 1)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isPulsing ? 1.4 : 1.0)
                        .opacity(isPulsing ? 0 : 0.5)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(severityLabel)
                    .font(theme.typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(severityColor)

                Text("Alert #\(alert.shortID)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.mutedText)
            }

            Spacer()

            // Elapsed time
            VStack(alignment: .trailing, spacing: 1) {
                Text(elapsedText)
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.text)
                    .monospacedDigit()

                Text("elapsed")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.mutedText)
            }
        }
    }

    // MARK: - Location Row

    private var locationRow: some View {
        HStack(spacing: FCSpacing.sm) {
            Image(systemName: "location.fill")
                .font(.system(size: 12))
                .foregroundStyle(severityColor)

            Text(alert.locationDescription)
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.text)

            Spacer()

            // Accuracy indicator
            accuracyBadge
        }
    }

    private var accuracyBadge: some View {
        HStack(spacing: FCSpacing.xs) {
            Image(systemName: alert.accuracy.iconName)
                .font(.system(size: 10))
                .foregroundStyle(alert.accuracy.color)

            Text(alert.accuracy.label)
                .font(theme.typography.caption)
                .foregroundStyle(alert.accuracy.color)
        }
        .padding(.horizontal, FCSpacing.sm)
        .padding(.vertical, 2)
        .background(Capsule().fill(alert.accuracy.color.opacity(0.12)))
    }

    // MARK: - Accepted Badge

    private func acceptedBadge(callsign: String) -> some View {
        HStack(spacing: FCSpacing.sm) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 14))
                .foregroundStyle(.fcAccentPurple)

            Text("Accepted by \(callsign)")
                .font(theme.typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(.fcAccentPurple)
        }
        .padding(.horizontal, FCSpacing.md)
        .padding(.vertical, FCSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: FCCornerRadius.sm, style: .continuous)
                .fill(.fcAccentPurple.opacity(0.1))
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: FCSpacing.sm) {
            if alert.acceptedBy == nil {
                Button(action: { onAccept?() }) {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(theme.typography.secondary)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, FCSpacing.md)
                        .padding(.vertical, FCSpacing.sm)
                        .background(
                            Capsule()
                                .fill(LinearGradient.fcAccent)
                        )
                }
                .frame(minHeight: FCSizing.minTapTarget)
                .accessibilityLabel("Accept this alert")
            }

            Button(action: { onNavigate?() }) {
                Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(theme.typography.secondary)
                    .fontWeight(.medium)
                    .foregroundStyle(.fcAccentPurple)
                    .padding(.horizontal, FCSpacing.md)
                    .padding(.vertical, FCSpacing.sm)
                    .background(
                        Capsule()
                            .fill(.fcAccentPurple.opacity(0.12))
                    )
            }
            .frame(minHeight: FCSizing.minTapTarget)
            .accessibilityLabel("Navigate to alert location")

            Spacer()

            if alert.acceptedBy != nil {
                Button(action: { onResolve?() }) {
                    Label("Resolve", systemImage: "checkmark.seal.fill")
                        .font(theme.typography.secondary)
                        .fontWeight(.medium)
                        .foregroundStyle(FCColors.darkColors.statusGreen)
                        .padding(.horizontal, FCSpacing.md)
                        .padding(.vertical, FCSpacing.sm)
                        .background(
                            Capsule()
                                .fill(FCColors.darkColors.statusGreen.opacity(0.12))
                        )
                }
                .frame(minHeight: FCSizing.minTapTarget)
                .accessibilityLabel("Resolve this alert")
            }
        }
    }

    // MARK: - Helpers

    private var severityColor: Color {
        switch alert.severity {
        case .green: return FCColors.darkColors.statusGreen
        case .amber: return FCColors.darkColors.statusAmber
        case .red: return FCColors.darkColors.statusRed
        }
    }

    private var severityLabel: String {
        switch alert.severity {
        case .green: return "NON-URGENT"
        case .amber: return "URGENT"
        case .red: return "CRITICAL"
        }
    }

    private func updateElapsed() {
        let interval = Date().timeIntervalSince(alert.createdAt)
        let minutes = Int(interval / 60)
        let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
        elapsedText = String(format: "%02d:%02d", minutes, seconds)
    }

    private func startPulseIfCritical() {
        guard alert.severity == .red, !SpringConstants.isReduceMotionEnabled else { return }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }

    private var accessibilityDescription: String {
        "\(severityLabel) alert, \(elapsedText) elapsed, \(alert.locationDescription)"
    }
}

// MARK: - SOSAlertItem

/// View-level data for an SOS alert card.
struct SOSAlertItem: Identifiable {
    let id: UUID
    let shortID: String
    let severity: SOSSeverity
    let locationDescription: String
    let description: String?
    let accuracy: LocationAccuracy
    let acceptedBy: String?
    let createdAt: Date
}

enum LocationAccuracy {
    case precise
    case estimated
    case lastKnown

    var iconName: String {
        switch self {
        case .precise: return "location.fill"
        case .estimated: return "location.circle"
        case .lastKnown: return "location.slash"
        }
    }

    var label: String {
        switch self {
        case .precise: return "GPS Lock"
        case .estimated: return "Estimated"
        case .lastKnown: return "Last Known"
        }
    }

    var color: Color {
        switch self {
        case .precise: return FCColors.darkColors.statusGreen
        case .estimated: return FCColors.darkColors.statusAmber
        case .lastKnown: return FCColors.darkColors.statusRed
        }
    }
}

// MARK: - Preview

#Preview("Alert Cards") {
    ZStack {
        GradientBackground()
        ScrollView {
            VStack(spacing: FCSpacing.md) {
                AlertCard(alert: SOSAlertItem(
                    id: UUID(),
                    shortID: "A7F3",
                    severity: .red,
                    locationDescription: "Near Pyramid Stage, Section B",
                    description: nil,
                    accuracy: .precise,
                    acceptedBy: nil,
                    createdAt: Date().addingTimeInterval(-180)
                ))

                AlertCard(alert: SOSAlertItem(
                    id: UUID(),
                    shortID: "B2E1",
                    severity: .amber,
                    locationDescription: "Camping Area B, near showers",
                    description: "Feeling very dizzy and nauseous",
                    accuracy: .estimated,
                    acceptedBy: "Medic-5",
                    createdAt: Date().addingTimeInterval(-420)
                ))

                AlertCard(alert: SOSAlertItem(
                    id: UUID(),
                    shortID: "C9D4",
                    severity: .green,
                    locationDescription: "West Holts area",
                    description: "Minor cut, need first aid",
                    accuracy: .lastKnown,
                    acceptedBy: nil,
                    createdAt: Date().addingTimeInterval(-60)
                ))
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
    .festiChatTheme()
}
