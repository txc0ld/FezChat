import SwiftUI

// MARK: - StaggeredReveal

/// ViewModifier that reveals content with a fade + translate animation,
/// staggered by item index for list-like entrances.
///
/// - Normal motion: Fade from 0 to 1, translate Y from 20pt to 0pt,
///   using the page entrance spring with 50ms stagger between items.
/// - Reduced motion: Simple immediate fade from 0 to 1, no translation.
///
/// Usage:
/// ```swift
/// ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
///     ItemView(item: item)
///         .staggeredReveal(index: index)
/// }
/// ```
struct StaggeredRevealModifier: ViewModifier {

    /// The index of this item in the list (used for stagger delay).
    let index: Int

    /// The vertical translation distance in points.
    let translateY: CGFloat

    /// Maximum number of items to stagger (items beyond this animate simultaneously).
    let maxStagger: Int

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(y: isVisible ? 0 : effectiveTranslateY)
            .onAppear {
                let delay = effectiveDelay
                if SpringConstants.isReduceMotionEnabled {
                    withAnimation(.easeIn(duration: SpringConstants.fadeDuration).delay(delay)) {
                        isVisible = true
                    }
                } else {
                    withAnimation(
                        SpringConstants.pageEntranceAnimation.delay(delay)
                    ) {
                        isVisible = true
                    }
                }
            }
    }

    // MARK: - Private

    private var effectiveTranslateY: CGFloat {
        SpringConstants.isReduceMotionEnabled ? 0 : translateY
    }

    private var effectiveDelay: Double {
        let clampedIndex = min(index, maxStagger)
        return Double(clampedIndex) * SpringConstants.staggerDelay
    }
}

// MARK: - View extension

extension View {

    /// Applies a staggered reveal animation to this view.
    /// - Parameters:
    ///   - index: Position in the list for calculating stagger delay.
    ///   - translateY: Vertical offset before reveal. Default `20`.
    ///   - maxStagger: Maximum stagger index. Default `20`.
    func staggeredReveal(
        index: Int,
        translateY: CGFloat = 20,
        maxStagger: Int = 20
    ) -> some View {
        modifier(StaggeredRevealModifier(
            index: index,
            translateY: translateY,
            maxStagger: maxStagger
        ))
    }
}

// MARK: - StaggeredRevealContainer

/// A container that automatically applies staggered reveal to its children.
/// Useful when you want a group of views to animate in sequence without
/// manually tracking indices.
struct StaggeredRevealContainer<Content: View>: View {

    let content: Content

    @State private var isVisible = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(SpringConstants.accessiblePageEntrance) {
                    isVisible = true
                }
            }
    }
}
