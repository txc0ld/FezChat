import SwiftUI

// MARK: - ElasticCounter

/// Animated number transitions with overshoot and settle.
/// Uses `contentTransition(.numericText())` with the elastic spring
/// and a scale pop effect (1.0 -> 1.15 -> 1.0) on change.
/// Suited for unread counts, peer counts, and similar numeric indicators.
struct ElasticCounter: View {

    // MARK: - Configuration

    /// The numeric value to display.
    private let value: Int

    /// The font used for the counter text.
    private let font: Font

    /// The text color.
    private let color: Color

    // MARK: - State

    @State private var scale: CGFloat = 1.0

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    init(
        value: Int,
        font: Font = .title2.weight(.bold),
        color: Color = .white
    ) {
        self.value = value
        self.font = font
        self.color = color
    }

    // MARK: - Body

    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .scaleEffect(scale)
            .animation(
                reduceMotion ? .linear(duration: 0.01) : SpringConstants.elasticAnimation,
                value: value
            )
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                triggerScalePop()
            }
    }

    // MARK: - Scale Pop

    private func triggerScalePop() {
        scale = 1.15
        withAnimation(SpringConstants.elasticAnimation) {
            scale = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Elastic Counter") {
    ElasticCounterPreview()
        .preferredColorScheme(.dark)
}

private struct ElasticCounterPreview: View {
    @State private var count = 3

    var body: some View {
        VStack(spacing: 30) {
            ElasticCounter(value: count, font: .largeTitle.weight(.bold), color: .white)

            ElasticCounter(value: count, font: .caption.weight(.semibold), color: Color("AccentPurple"))

            HStack(spacing: 20) {
                Button("- 1") { count = max(0, count - 1) }
                    .buttonStyle(.bordered)
                Button("+ 1") { count += 1 }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.black)
    }
}
