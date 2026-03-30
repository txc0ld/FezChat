import SwiftUI

// MARK: - GlassCard

/// A reusable glassmorphism container view.
///
/// Renders a translucent material background with a gradient border, inner glow,
/// frosted noise texture, and rounded corners, matching the Blip design language.
/// Supports both `MaterialThickness` (backward compatible) and `Elevation` presets.
///
/// Usage:
/// ```swift
/// GlassCard {
///     Text("Hello")
/// }
///
/// GlassCard(elevation: .floating) {
///     Text("Elevated card")
/// }
/// ```
struct GlassCard<Content: View>: View {

    /// Controls the blur intensity of the glass material.
    enum MaterialThickness: Sendable {
        case ultraThin
        case regular
        case thick
    }

    /// Elevation presets that bundle material, blur, shadow, and border strength.
    enum Elevation: Sendable {
        /// Subtle raise: ultraThinMaterial, 8pt blur, subtle shadow.
        case raised
        /// Mid-level float: regularMaterial, 16pt blur, medium shadow, stronger border.
        case floating
        /// Full overlay: thickMaterial, 24pt blur, prominent accent-tinted shadow.
        case overlay

        var thickness: MaterialThickness {
            switch self {
            case .raised: return .ultraThin
            case .floating: return .regular
            case .overlay: return .thick
            }
        }

        var borderOpacity: Double {
            switch self {
            case .raised: return 0.15
            case .floating: return 0.25
            case .overlay: return 0.2
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .raised: return 8
            case .floating: return 16
            case .overlay: return 24
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .raised: return 0.15
            case .floating: return 0.25
            case .overlay: return 0.30
            }
        }
    }

    private let thickness: MaterialThickness
    private let elevation: Elevation?
    private let cornerRadius: CGFloat
    private let borderOpacity: Double
    private let padding: EdgeInsets
    @ViewBuilder private let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a glass card with configurable material, corner radius, and content.
    /// - Parameters:
    ///   - thickness: Material blur intensity. Default `.thick`.
    ///   - cornerRadius: Corner radius in points. Default `24`.
    ///   - borderOpacity: Opacity of the gradient border. Default `0.2`.
    ///   - padding: Inner content padding. Default `.blipCard`.
    ///   - content: The card's body content.
    init(
        thickness: MaterialThickness = .thick,
        cornerRadius: CGFloat = BlipCornerRadius.xl,
        borderOpacity: Double = 0.2,
        padding: EdgeInsets = .blipCard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.thickness = thickness
        self.elevation = nil
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
        self.padding = padding
        self.content = content
    }

    /// Creates a glass card using an elevation preset.
    /// - Parameters:
    ///   - elevation: Elevation preset controlling material, shadow, and border.
    ///   - cornerRadius: Corner radius in points. Default `24`.
    ///   - padding: Inner content padding. Default `.blipCard`.
    ///   - content: The card's body content.
    init(
        elevation: Elevation,
        cornerRadius: CGFloat = BlipCornerRadius.xl,
        padding: EdgeInsets = .blipCard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.thickness = elevation.thickness
        self.elevation = elevation
        self.cornerRadius = cornerRadius
        self.borderOpacity = elevation.borderOpacity
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(glassBackground)
            .clipShape(shape)
            .overlay(noiseOverlay)
            .overlay(innerGlowOverlay)
            .overlay(gradientBorderOverlay)
            .shadow(
                color: shadowColor,
                radius: resolvedShadowRadius,
                x: 0,
                y: resolvedShadowRadius * 0.25
            )
    }

    // MARK: - Private

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var glassBackground: some View {
        switch resolvedThickness {
        case .ultraThin:
            shape.fill(.ultraThinMaterial)
        case .regular:
            shape.fill(.regularMaterial)
        case .thick:
            shape.fill(.thickMaterial)
        }
    }

    // MARK: - Gradient border

    private var gradientBorderOverlay: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: gradientBorderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: BlipSizing.hairline
            )
    }

    private var gradientBorderColors: [Color] {
        if colorScheme == .dark {
            return [
                .white.opacity(resolvedBorderOpacity * 1.5),
                .white.opacity(resolvedBorderOpacity * 0.3)
            ]
        } else {
            return [
                .black.opacity(resolvedBorderOpacity * 0.3),
                .black.opacity(resolvedBorderOpacity * 1.2)
            ]
        }
    }

    // MARK: - Inner glow

    private var innerGlowOverlay: some View {
        shape
            .stroke(innerGlowColor, lineWidth: 1)
            .padding(0.5)
            .clipShape(shape)
    }

    private var innerGlowColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.04)
            : .black.opacity(0.03)
    }

    // MARK: - Frosted noise texture

    private var noiseOverlay: some View {
        Canvas { context, size in
            // Deterministic noise using a simple hash-based pattern
            let step: CGFloat = 4
            let cols = Int(size.width / step)
            let rows = Int(size.height / step)

            for row in 0..<rows {
                for col in 0..<cols {
                    // Simple deterministic hash for pseudo-random placement
                    let hash = (col &* 2654435761) ^ (row &* 2246822519)
                    let normalized = Double(hash & 0xFFFF) / Double(0xFFFF)

                    // Only draw ~30% of cells for subtle speckle
                    guard normalized < 0.3 else { continue }

                    let x = CGFloat(col) * step + step * 0.5
                    let y = CGFloat(row) * step + step * 0.5
                    let dotSize: CGFloat = 1.0

                    let rect = CGRect(
                        x: x - dotSize * 0.5,
                        y: y - dotSize * 0.5,
                        width: dotSize,
                        height: dotSize
                    )

                    let dotColor = colorScheme == .dark
                        ? Color.white
                        : Color.black

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(dotColor)
                    )
                }
            }
        }
        .opacity(colorScheme == .dark ? 0.025 : 0.02)
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    // MARK: - Shadow

    private var shadowColor: Color {
        if let elev = elevation, elev == .overlay {
            return Color(red: 0.4, green: 0.0, blue: 1.0).opacity(0.04)
        }
        return colorScheme == .dark
            ? .black.opacity(resolvedShadowOpacity)
            : .black.opacity(resolvedShadowOpacity * 0.5)
    }

    // MARK: - Resolved values

    private var resolvedThickness: MaterialThickness {
        if let elev = elevation {
            return elev.thickness
        }
        return thickness
    }

    private var resolvedBorderOpacity: Double {
        if let elev = elevation {
            return elev.borderOpacity
        }
        return borderOpacity
    }

    private var resolvedShadowRadius: CGFloat {
        if let elev = elevation {
            return elev.shadowRadius
        }
        return 4
    }

    private var resolvedShadowOpacity: Double {
        if let elev = elevation {
            return elev.shadowOpacity
        }
        return 0.1
    }
}

// MARK: - Convenience view modifier

/// Wraps a view in a GlassCard container.
struct GlassCardModifier: ViewModifier {

    let thickness: GlassCard<EmptyView>.MaterialThickness
    let cornerRadius: CGFloat
    let borderOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.blipCard)
            .background(glassBackground)
            .clipShape(shape)
            .overlay(noiseOverlay)
            .overlay(innerGlowOverlay)
            .overlay(gradientBorderOverlay)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var glassBackground: some View {
        switch thickness {
        case .ultraThin:
            shape.fill(.ultraThinMaterial)
        case .regular:
            shape.fill(.regularMaterial)
        case .thick:
            shape.fill(.thickMaterial)
        }
    }

    private var gradientBorderOverlay: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: gradientBorderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: BlipSizing.hairline
            )
    }

    private var gradientBorderColors: [Color] {
        if colorScheme == .dark {
            return [
                .white.opacity(borderOpacity * 1.5),
                .white.opacity(borderOpacity * 0.3)
            ]
        } else {
            return [
                .black.opacity(borderOpacity * 0.3),
                .black.opacity(borderOpacity * 1.2)
            ]
        }
    }

    private var innerGlowOverlay: some View {
        shape
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.04)
                    : Color.black.opacity(0.03),
                lineWidth: 1
            )
            .padding(0.5)
            .clipShape(shape)
    }

    private var noiseOverlay: some View {
        Canvas { context, size in
            let step: CGFloat = 4
            let cols = Int(size.width / step)
            let rows = Int(size.height / step)

            for row in 0..<rows {
                for col in 0..<cols {
                    let hash = (col &* 2654435761) ^ (row &* 2246822519)
                    let normalized = Double(hash & 0xFFFF) / Double(0xFFFF)
                    guard normalized < 0.3 else { continue }

                    let x = CGFloat(col) * step + step * 0.5
                    let y = CGFloat(row) * step + step * 0.5
                    let dotSize: CGFloat = 1.0
                    let rect = CGRect(
                        x: x - dotSize * 0.5,
                        y: y - dotSize * 0.5,
                        width: dotSize,
                        height: dotSize
                    )
                    let dotColor: Color = colorScheme == .dark ? .white : .black
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
        .opacity(colorScheme == .dark ? 0.025 : 0.02)
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Wraps the view in a glass material container.
    func glassCard(
        thickness: GlassCard<EmptyView>.MaterialThickness = .thick,
        cornerRadius: CGFloat = BlipCornerRadius.xl,
        borderOpacity: Double = 0.2
    ) -> some View {
        modifier(GlassCardModifier(
            thickness: thickness,
            cornerRadius: cornerRadius,
            borderOpacity: borderOpacity
        ))
    }
}

// MARK: - Preview

#Preview("GlassCard — Material Thickness") {
    ZStack {
        GradientBackground()

        VStack(spacing: BlipSpacing.md) {
            GlassCard(thickness: .ultraThin) {
                Text("Ultra Thin")
                    .foregroundStyle(.white)
            }

            GlassCard(thickness: .regular) {
                Text("Regular")
                    .foregroundStyle(.white)
            }

            GlassCard(thickness: .thick) {
                Text("Thick")
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("GlassCard — Elevation") {
    ZStack {
        GradientBackground()

        VStack(spacing: BlipSpacing.md) {
            GlassCard(elevation: .raised) {
                Text("Raised")
                    .foregroundStyle(.white)
            }

            GlassCard(elevation: .floating) {
                Text("Floating")
                    .foregroundStyle(.white)
            }

            GlassCard(elevation: .overlay) {
                Text("Overlay")
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
