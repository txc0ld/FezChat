import SwiftUI

// MARK: - Blip Typography

/// Typography system using Plus Jakarta Sans with system font fallback.
/// Supports Dynamic Type scaling for accessibility.
struct BlipTypography: Sendable {

    // MARK: Display

    /// Hero / splash text — Bold 40pt
    let display: Font

    // MARK: Titles

    /// Screen titles — Bold 34pt
    let largeTitle: Font

    /// Section titles — Bold 28pt
    let title2: Font

    /// Sub-section titles — SemiBold 20pt
    let title3: Font

    // MARK: Body-adjacent

    /// Section headers — SemiBold 22pt
    let headline: Font

    /// Emphasized subtext — SemiBold 15pt
    let subheadline: Font

    /// Primary body — Regular 17pt
    let body: Font

    /// Supporting body — Regular 16pt
    let callout: Font

    // MARK: Small

    /// Secondary / metadata — Regular 13pt
    let secondary: Font

    /// Fine print — Regular 12pt
    let footnote: Font

    /// Captions — Medium 11pt
    let caption: Font

    /// Smallest labels — Medium 10pt
    let captionSmall: Font

    // MARK: - Default instance

    /// Standard typography set using Plus Jakarta Sans with Dynamic Type scaling.
    static let standard = BlipTypography(
        display:      .custom(BlipFontName.bold,     size: 40, relativeTo: .largeTitle),
        largeTitle:   .custom(BlipFontName.bold,     size: 34, relativeTo: .largeTitle),
        title2:       .custom(BlipFontName.bold,     size: 28, relativeTo: .title2),
        title3:       .custom(BlipFontName.semiBold, size: 20, relativeTo: .title3),
        headline:     .custom(BlipFontName.semiBold, size: 22, relativeTo: .headline),
        subheadline:  .custom(BlipFontName.semiBold, size: 15, relativeTo: .subheadline),
        body:         .custom(BlipFontName.regular,  size: 17, relativeTo: .body),
        callout:      .custom(BlipFontName.regular,  size: 16, relativeTo: .callout),
        secondary:    .custom(BlipFontName.regular,  size: 13, relativeTo: .footnote),
        footnote:     .custom(BlipFontName.regular,  size: 12, relativeTo: .footnote),
        caption:      .custom(BlipFontName.medium,   size: 11, relativeTo: .caption2),
        captionSmall: .custom(BlipFontName.medium,   size: 10, relativeTo: .caption2)
    )

    /// System font fallback if Plus Jakarta Sans is not registered.
    static let system = BlipTypography(
        display:      .system(size: 40, weight: .bold,     design: .rounded),
        largeTitle:   .system(size: 34, weight: .bold,     design: .rounded),
        title2:       .system(size: 28, weight: .bold,     design: .rounded),
        title3:       .system(size: 20, weight: .semibold, design: .rounded),
        headline:     .system(size: 22, weight: .semibold, design: .rounded),
        subheadline:  .system(size: 15, weight: .semibold, design: .default),
        body:         .system(size: 17, weight: .regular,  design: .default),
        callout:      .system(size: 16, weight: .regular,  design: .default),
        secondary:    .system(size: 13, weight: .regular,  design: .default),
        footnote:     .system(size: 12, weight: .regular,  design: .default),
        caption:      .system(size: 11, weight: .medium,   design: .default),
        captionSmall: .system(size: 10, weight: .medium,   design: .default)
    )
}

// MARK: - Font name constants

/// PostScript names for Plus Jakarta Sans font files.
/// The actual .ttf files must be added to Resources/Fonts/ and registered in Info.plist.
enum BlipFontName {
    static let regular = "PlusJakartaSans-Regular"
    static let medium = "PlusJakartaSans-Medium"
    static let semiBold = "PlusJakartaSans-SemiBold"
    static let bold = "PlusJakartaSans-Bold"
}

// MARK: - Font registration helper

enum BlipFontRegistration {

    /// Checks if Plus Jakarta Sans is available in the system.
    static var isCustomFontAvailable: Bool {
        #if canImport(UIKit)
        let families = UIFont.familyNames
        return families.contains("Plus Jakarta Sans")
        #elseif canImport(AppKit)
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.contains("Plus Jakarta Sans")
        #else
        return false
        #endif
    }

    /// Returns the appropriate typography based on font availability.
    static var resolved: BlipTypography {
        isCustomFontAvailable ? .standard : .system
    }
}

// MARK: - View modifier for consistent text styling

/// Applies Blip typography styles to text views.
struct BlipTextStyle: ViewModifier {

    enum Style {
        // Display
        case display
        // Titles
        case largeTitle
        case title2
        case title3
        // Body-adjacent
        case headline
        case subheadline
        case body
        case callout
        // Small
        case secondary
        case footnote
        case caption
        case captionSmall
    }

    let style: Style
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let font: Font = switch style {
        case .display:      theme.typography.display
        case .largeTitle:   theme.typography.largeTitle
        case .title2:       theme.typography.title2
        case .title3:       theme.typography.title3
        case .headline:     theme.typography.headline
        case .subheadline:  theme.typography.subheadline
        case .body:         theme.typography.body
        case .callout:      theme.typography.callout
        case .secondary:    theme.typography.secondary
        case .footnote:     theme.typography.footnote
        case .caption:      theme.typography.caption
        case .captionSmall: theme.typography.captionSmall
        }
        return content.font(font)
    }
}

extension View {
    /// Applies a Blip text style.
    func blipTextStyle(_ style: BlipTextStyle.Style) -> some View {
        modifier(BlipTextStyle(style: style))
    }
}
