import SwiftUI

// MARK: - SOSButton

/// Persistent floating SOS pill visible on every screen.
/// Subtle glass material in default state, red accent on press.
/// Tap opens SOSConfirmationSheet.
struct SOSButton: View {

    @State private var isPressed = false
    @State private var showSOSSheet = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme

    /// Minimum tap target is 60pt for SOS (larger than standard 44pt).
    private let buttonHeight: CGFloat = 36
    private let minTapTarget: CGFloat = 60

    var body: some View {
        Button {
            showSOSSheet = true
        } label: {
            HStack(spacing: FCSpacing.xs) {
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 14, weight: .bold))

                Text("SOS")
                    .font(.custom(FCFontName.bold, size: 13, relativeTo: .caption))
            }
            .foregroundStyle(isPressed ? .white : theme.colors.statusRed)
            .padding(.horizontal, FCSpacing.md)
            .padding(.vertical, FCSpacing.sm)
            .frame(minHeight: buttonHeight)
            .background(buttonBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isPressed
                            ? theme.colors.statusRed.opacity(0.8)
                            : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)),
                        lineWidth: FCSizing.hairline
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(SpringConstants.bouncyAnimation, value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .frame(minWidth: minTapTarget, minHeight: minTapTarget)
        .contentShape(Rectangle())
        .accessibilityLabel("SOS Emergency")
        .accessibilityHint("Double tap to open emergency options")
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(1)
        .sheet(isPresented: $showSOSSheet) {
            SOSConfirmationPlaceholder()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var buttonBackground: some View {
        if isPressed {
            Capsule()
                .fill(theme.colors.statusRed)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - SOSConfirmationPlaceholder

/// Placeholder for SOSConfirmationSheet (built in Phase 12).
private struct SOSConfirmationPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            GradientBackground()
                .ignoresSafeArea()

            VStack(spacing: FCSpacing.lg) {
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.colors.statusRed)

                Text("SOS Emergency")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.text)

                Text("Emergency confirmation flow will appear here.")
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.mutedText)
                    .multilineTextAlignment(.center)

                GlassButton("Cancel", style: .secondary) {
                    dismiss()
                }
            }
            .padding(FCSpacing.xl)
        }
    }
}

// MARK: - Preview

#Preview("SOS Button - Default") {
    ZStack {
        GradientBackground()
        SOSButton()
    }
    .environment(\.theme, Theme.shared)
}

#Preview("SOS Button - Light") {
    ZStack {
        Color.white.ignoresSafeArea()
        SOSButton()
    }
    .environment(\.theme, Theme.resolved(for: .light))
    .preferredColorScheme(.light)
}
