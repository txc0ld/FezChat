import SwiftUI

// MARK: - GlassButton

/// A glass-styled button with accent purple gradient fill.
/// Provides visual feedback for hover (macOS) and press states with spring animations.
/// Enforces minimum 44pt tap target for accessibility.
struct GlassButton: View {

    /// Visual style of the button.
    enum Style: Sendable {
        /// Filled with accent gradient. Primary actions.
        case primary
        /// Glass material background. Secondary actions.
        case secondary
        /// Transparent with border only. Tertiary actions.
        case outline
    }

    /// Size preset affecting padding and font.
    enum Size: Sendable {
        case small
        case regular
        case large

        var verticalPadding: CGFloat {
            switch self {
            case .small: return BlipSpacing.sm
            case .regular: return BlipSpacing.md - 2
            case .large: return BlipSpacing.md
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return BlipSpacing.md
            case .regular: return BlipSpacing.lg
            case .large: return BlipSpacing.xl
            }
        }

        var font: Font {
            switch self {
            case .small: return .custom(BlipFontName.medium, size: 13, relativeTo: .footnote)
            case .regular: return .custom(BlipFontName.semiBold, size: 15, relativeTo: .body)
            case .large: return .custom(BlipFontName.semiBold, size: 17, relativeTo: .body)
            }
        }
    }

    let title: String
    let icon: String?
    let style: Style
    let size: Size
    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var pressScale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    /// Creates a glass button.
    /// - Parameters:
    ///   - title: Button label text.
    ///   - icon: Optional SF Symbol name shown before the title.
    ///   - style: Visual style. Default `.primary`.
    ///   - size: Size preset. Default `.regular`.
    ///   - isLoading: Shows a spinner and disables interaction. Default `false`.
    ///   - action: Closure executed on tap.
    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        size: Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            action()
        }) {
            HStack(spacing: BlipSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon)
                        .font(size.font)
                }

                Text(title)
                    .font(size.font)
            }
            .foregroundStyle(foregroundColor)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: BlipSizing.minTapTarget)
            .background(background)
            .clipShape(buttonShape)
            .overlay(borderOverlay)
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.65)) {
                        pressScale = 0.985
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    // Overshoot to 1.002 then settle to 1.0
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.5)) {
                        pressScale = 1.002
                    }
                    // Settle back to 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                            pressScale = 1.0
                        }
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Private

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BlipCornerRadius.lg, style: .continuous)
    }

    // MARK: - Style resolution

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            LinearGradient.blipAccent
                .opacity(isPressed ? 0.85 : 1.0)
                .overlay(
                    isPressed
                        ? Color.white.opacity(0.10)
                        : Color.clear
                )
        case .secondary:
            buttonShape
                .fill(.ultraThinMaterial)
                .overlay(
                    buttonShape
                        .fill(isPressed ? brightenedFill : Color.clear)
                )
        case .outline:
            Color.clear
                .overlay(
                    buttonShape
                        .fill(isPressed ? brightenedFill : Color.clear)
                )
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch style {
        case .primary:
            EmptyView()
        case .secondary:
            buttonShape
                .stroke(
                    LinearGradient(
                        colors: gradientBorderColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: BlipSizing.hairline
                )
        case .outline:
            buttonShape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.blipAccentPurple.opacity(0.8),
                            Color.blipAccentPurple.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var gradientBorderColors: [Color] {
        if colorScheme == .dark {
            return [
                .white.opacity(isPressed ? 0.25 : 0.15),
                .white.opacity(isPressed ? 0.08 : 0.04)
            ]
        } else {
            return [
                .black.opacity(isPressed ? 0.05 : 0.03),
                .black.opacity(isPressed ? 0.15 : 0.10)
            ]
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary, .outline:
            return colorScheme == .dark ? .white : .black
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.15)
            : .black.opacity(0.10)
    }

    private var hoverFill: Color {
        colorScheme == .dark
            ? .white.opacity(0.05)
            : .black.opacity(0.05)
    }

    /// Brightened fill for press state — 10% more opacity than hover.
    private var brightenedFill: Color {
        colorScheme == .dark
            ? .white.opacity(0.10)
            : .black.opacity(0.08)
    }
}

// MARK: - SpringConstants helper for button

private extension SpringConstants {
    static let buttonPress: Animation = .spring(
        response: 0.25,
        dampingFraction: 0.7
    )
}

// MARK: - Full-width variant

extension GlassButton {
    /// Returns this button stretched to fill the available width.
    func fullWidth() -> some View {
        self.frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("GlassButton Styles") {
    ZStack {
        GradientBackground()

        VStack(spacing: BlipSpacing.md) {
            GlassButton("Primary Action", icon: "bolt.fill", style: .primary) { }

            GlassButton("Secondary", icon: "gear", style: .secondary) { }

            GlassButton("Outline", icon: "arrow.right", style: .outline) { }

            GlassButton("Loading", style: .primary, isLoading: true) { }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
