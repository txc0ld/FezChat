import SwiftUI

// MARK: - GradientBackground

/// Animated mesh gradient background for Blip.
///
/// Uses the surface hierarchy colors as the base with subtle accent ambient washes.
/// Slowly shifts between deep purple, midnight blue, and dark teal orbs (dark mode).
/// Light mode uses clean surface gradients with soft ambient color touches.
/// Respects `UIAccessibility.isReduceMotionEnabled` by disabling the animation.
struct GradientBackground: View {

    @State private var animationPhase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    /// Duration of one full animation cycle in seconds.
    private let cycleDuration: Double = 12.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                baseLayer
                ambientWashLayer
                if colorScheme == .dark {
                    animatedOrbsLayer(size: geometry.size)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimationIfAllowed()
        }
    }

    // MARK: - Layers

    /// Base layer using the surface hierarchy colors.
    private var baseLayer: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [.blipSurfaceBaseDark, .black]
                : [.blipSurfaceBaseLight, .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Subtle ambient color washes using the new accent glow colors.
    private var ambientWashLayer: some View {
        ZStack {
            // Purple ambient wash — top area
            RadialGradient(
                colors: [
                    Color.blipAmbientPurple,
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )

            // Cyan ambient wash — bottom trailing
            RadialGradient(
                colors: [
                    Color.blipAmbientCyan,
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 350
            )
        }
        .blendMode(colorScheme == .dark ? .screen : .multiply)
    }

    /// Animated gradient orbs that drift slowly behind content (dark mode only).
    @ViewBuilder
    private func animatedOrbsLayer(size: CGSize) -> some View {
        let width = size.width
        let height = size.height

        Canvas { context, canvasSize in
            let time = animationPhase

            // Deep purple orb — top left, drifts right
            let purpleCenter = CGPoint(
                x: width * (0.2 + 0.15 * sin(time * 0.7)),
                y: height * (0.15 + 0.10 * cos(time * 0.5))
            )
            let purpleRadius = min(width, height) * 0.5
            drawRadialGlow(
                in: context,
                center: purpleCenter,
                radius: purpleRadius,
                color: Color.blipGradientDeepPurple
            )

            // Midnight blue orb — center, drifts diagonally
            let blueCenter = CGPoint(
                x: width * (0.55 + 0.12 * cos(time * 0.6)),
                y: height * (0.5 + 0.15 * sin(time * 0.8))
            )
            let blueRadius = min(width, height) * 0.55
            drawRadialGlow(
                in: context,
                center: blueCenter,
                radius: blueRadius,
                color: Color.blipGradientMidnightBlue
            )

            // Dark teal orb — bottom right, drifts left
            let tealCenter = CGPoint(
                x: width * (0.8 - 0.10 * sin(time * 0.9)),
                y: height * (0.85 - 0.10 * cos(time * 0.6))
            )
            let tealRadius = min(width, height) * 0.45
            drawRadialGlow(
                in: context,
                center: tealCenter,
                radius: tealRadius,
                color: Color.blipGradientDarkTeal
            )
        }
        .opacity(0.8)
        .blendMode(.screen)
    }

    // MARK: - Drawing helpers

    private func drawRadialGlow(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        let gradient = Gradient(colors: [
            color.opacity(0.6),
            color.opacity(0.3),
            color.opacity(0.0)
        ])

        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .radialGradient(
                gradient,
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    // MARK: - Animation

    private func startAnimationIfAllowed() {
        guard !isReduceMotionEnabled else { return }

        withAnimation(
            .linear(duration: cycleDuration)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = 2 * .pi
        }
    }

    private var isReduceMotionEnabled: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}

// MARK: - Static gradient fallback

extension GradientBackground {
    /// A non-animated gradient for use in contexts where animation is undesirable.
    /// Uses surface hierarchy colors with ambient accent washes.
    static var staticGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .blipSurfaceBaseDark,
                    .blipGradientDeepPurple.opacity(0.3),
                    .blipGradientMidnightBlue.opacity(0.2),
                    .blipSurfaceBaseDark
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle ambient purple wash
            RadialGradient(
                colors: [
                    Color.blipAmbientPurple,
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 300
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview("GradientBackground — Dark") {
    GradientBackground()
        .preferredColorScheme(.dark)
}

#Preview("GradientBackground — Light") {
    GradientBackground()
        .preferredColorScheme(.light)
}
