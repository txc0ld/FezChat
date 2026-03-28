import SwiftUI

// MARK: - ScrollReveal

/// ViewModifier that triggers a fade + translate reveal when the view
/// scrolls into the visible area.
///
/// Uses `onAppear` for the trigger. When the view enters the viewport:
/// - Normal motion: Fade + translateY(20pt) with the reveal animation.
/// - Reduced motion: Simple instant fade-in.
///
/// Usage:
/// ```swift
/// ScrollView {
///     ForEach(items) { item in
///         ItemView(item: item)
///             .scrollReveal()
///     }
/// }
/// ```
struct ScrollRevealModifier: ViewModifier {

    /// Vertical translation offset before reveal.
    let translateY: CGFloat

    /// Horizontal translation offset before reveal (used for directional reveals).
    let translateX: CGFloat

    /// Fade start opacity.
    let startOpacity: Double

    /// Optional scale factor before reveal (1.0 = no scale change).
    let startScale: CGFloat

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1.0 : startOpacity)
            .offset(
                x: hasAppeared ? 0 : effectiveTranslateX,
                y: hasAppeared ? 0 : effectiveTranslateY
            )
            .scaleEffect(hasAppeared ? 1.0 : effectiveScale)
            .onAppear {
                guard !hasAppeared else { return }
                let animation = SpringConstants.isReduceMotionEnabled
                    ? Animation.easeIn(duration: SpringConstants.fadeDuration)
                    : SpringConstants.revealAnimation
                withAnimation(animation) {
                    hasAppeared = true
                }
            }
    }

    // MARK: - Private

    private var effectiveTranslateY: CGFloat {
        SpringConstants.isReduceMotionEnabled ? 0 : translateY
    }

    private var effectiveTranslateX: CGFloat {
        SpringConstants.isReduceMotionEnabled ? 0 : translateX
    }

    private var effectiveScale: CGFloat {
        SpringConstants.isReduceMotionEnabled ? 1.0 : startScale
    }
}

// MARK: - View extension

extension View {

    /// Applies a scroll-triggered reveal animation.
    /// - Parameters:
    ///   - translateY: Vertical offset before reveal. Default `20`.
    ///   - translateX: Horizontal offset before reveal. Default `0`.
    ///   - startOpacity: Starting opacity. Default `0`.
    ///   - startScale: Starting scale. Default `1.0`.
    func scrollReveal(
        translateY: CGFloat = 20,
        translateX: CGFloat = 0,
        startOpacity: Double = 0,
        startScale: CGFloat = 1.0
    ) -> some View {
        modifier(ScrollRevealModifier(
            translateY: translateY,
            translateX: translateX,
            startOpacity: startOpacity,
            startScale: startScale
        ))
    }

    /// Scroll reveal with a directional slide from the left (message from other user).
    func scrollRevealFromLeft() -> some View {
        scrollReveal(translateY: 0, translateX: -30)
    }

    /// Scroll reveal with a directional slide from the right (own message).
    func scrollRevealFromRight() -> some View {
        scrollReveal(translateY: 0, translateX: 30)
    }

    /// Scroll reveal with a subtle scale-up effect.
    func scrollRevealScale() -> some View {
        scrollReveal(translateY: 10, startScale: 0.95)
    }
}
