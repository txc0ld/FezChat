import SwiftUI

// MARK: - FestiChat Theme

/// Unified theme object that bundles colors, typography, and spacing tokens.
/// Injected into the SwiftUI environment for consistent access across all views.
struct Theme: Sendable {

    /// Adaptive color palette.
    let colors: FCColors

    /// Typography scale.
    let typography: FCTypography

    /// Singleton shared instance using adaptive (asset-catalog-backed) colors
    /// and auto-resolved typography (custom font with system fallback).
    static let shared = Theme(
        colors: .adaptive,
        typography: FCFontRegistration.resolved
    )

    /// Returns a theme resolved for an explicit color scheme.
    static func resolved(for scheme: ColorScheme) -> Theme {
        Theme(
            colors: .resolved(for: scheme),
            typography: FCFontRegistration.resolved
        )
    }
}

// MARK: - Environment key

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = Theme.shared
}

extension EnvironmentValues {
    /// The current FestiChat theme.
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Convenience view extension

extension View {
    /// Injects a FestiChat theme into the environment.
    func festiChatTheme(_ theme: Theme = .shared) -> some View {
        environment(\.theme, theme)
    }
}
