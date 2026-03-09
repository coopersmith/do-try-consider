import SwiftUI

// MARK: - Adaptive Color Helper

private func adaptiveColor(light: UInt, dark: UInt) -> Color {
    #if canImport(UIKit)
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark))
            : UIColor(Color(hex: light))
    })
    #else
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(Color(hex: dark))
            : NSColor(Color(hex: light))
    })
    #endif
}

// MARK: - App Theme

enum AppTheme {

    // MARK: Colors — Flexoki by Steph Ango (https://stephango.com/flexoki)

    // Base palette
    static let black      = Color(hex: 0x100F0F)
    static let paper      = Color(hex: 0xFFFCF0)
    static let base950    = Color(hex: 0x1C1B1A)
    static let base900    = Color(hex: 0x282726)
    static let base850    = Color(hex: 0x343331)
    static let base800    = Color(hex: 0x403E3C)
    static let base600    = Color(hex: 0x6F6E69)
    static let base500    = Color(hex: 0x878580)
    static let base300    = Color(hex: 0xB7B5AC)
    static let base200    = Color(hex: 0xCECDC3)
    static let base150    = Color(hex: 0xDAD8CE)
    static let base100    = Color(hex: 0xE6E4D9)
    static let base50     = Color(hex: 0xF2F0E5)

    /// Accent — Flexoki Orange
    static let accent = adaptiveColor(light: 0xBC5215, dark: 0xDA702C)

    /// Adaptive background — paper / base-950
    static let adaptiveBackground = adaptiveColor(light: 0xFFFCF0, dark: 0x1C1B1A)

    /// Adaptive card surface — base-50 / base-900
    static let adaptiveCard = adaptiveColor(light: 0xF2F0E5, dark: 0x282726)

    /// Adaptive secondary surface — base-100 / base-850
    static let adaptiveSecondary = adaptiveColor(light: 0xE6E4D9, dark: 0x343331)

    /// Primary text — black / base-200
    static let textPrimary = adaptiveColor(light: 0x100F0F, dark: 0xCECDC3)

    /// Secondary text — base-600 / base-500
    static let textSecondary = adaptiveColor(light: 0x6F6E69, dark: 0x878580)

    // Urgency palette — Flexoki semantic colors (600 light / 400 dark)
    static let urgencyRed    = adaptiveColor(light: 0xAF3029, dark: 0xD14D41)
    static let urgencyOrange = adaptiveColor(light: 0xBC5215, dark: 0xDA702C)
    static let urgencyGreen  = adaptiveColor(light: 0x66800B, dark: 0x879A39)

    // Badge colors — Flexoki accents (600 light / 400 dark)
    static let badgeGranola  = adaptiveColor(light: 0x5E409D, dark: 0x8B7EC8) // Purple
    static let badgeLocal    = adaptiveColor(light: 0x24837B, dark: 0x3AA99F) // Cyan
    static let badgeCalendar = adaptiveColor(light: 0x205EA6, dark: 0x4385BE) // Blue

    // MARK: Typography — System Serif ("New York")

    /// Large display — briefing greeting, screen heroes
    static let largeTitleFont: Font = .system(.largeTitle, design: .serif, weight: .bold)
    /// Standard title — card headings, detail view names
    static let titleFont: Font = .system(.title2, design: .serif, weight: .bold)
    /// Smaller title — detail headers, meeting titles
    static let title3Font: Font = .system(.title3, design: .serif, weight: .semibold)
    /// Section headers — card labels, section dividers
    static let sectionHeaderFont: Font = .system(.subheadline, design: .serif, weight: .semibold)
    /// Headline — inline emphasis within body
    static let headlineFont: Font = .system(.headline, design: .serif)
    /// Body text — notes, descriptions, content
    static let bodyFont: Font = .system(.body, design: .serif)
    /// Standard text — row items, labels
    static let subheadlineFont: Font = .system(.subheadline, design: .serif)
    /// Small text — timestamps, metadata
    static let captionFont: Font = .system(.caption, design: .serif)
    /// Smaller caption — tertiary labels
    static let caption2Font: Font = .system(.caption2, design: .serif)

    // MARK: Spacing & Radii

    static let cornerRadiusSmall: CGFloat = 10
    static let cornerRadiusMedium: CGFloat = 14
    static let cornerRadiusCard: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
}

// MARK: - Color Hex Init

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
