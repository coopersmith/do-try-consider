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

    // MARK: Colors

    /// Terracotta accent — primary brand color
    static let accent = Color(hex: 0xD4654A)

    /// Adaptive background — cream in light, warm charcoal in dark
    static let adaptiveBackground = adaptiveColor(light: 0xFAF6F1, dark: 0x1C1816)

    /// Adaptive card surface
    static let adaptiveCard = adaptiveColor(light: 0xFFFDF9, dark: 0x2A2420)

    /// Adaptive secondary surface (section fills, dividers)
    static let adaptiveSecondary = adaptiveColor(light: 0xF3EDE5, dark: 0x332C26)

    /// Primary text — near-black warm tone
    static let textPrimary = adaptiveColor(light: 0x2C2420, dark: 0xF5F0EB)

    /// Secondary text
    static let textSecondary = adaptiveColor(light: 0x8A7E74, dark: 0x9E9389)

    // Urgency palette
    static let urgencyRed = adaptiveColor(light: 0xC44B3F, dark: 0xE06558)
    static let urgencyOrange = adaptiveColor(light: 0xD4854A, dark: 0xE09A60)
    static let urgencyGreen = adaptiveColor(light: 0x5A9E6F, dark: 0x6DB882)

    // Badge colors
    static let badgeGranola = adaptiveColor(light: 0x9B59B6, dark: 0xB070CC)
    static let badgeLocal = adaptiveColor(light: 0x2A9D8F, dark: 0x3AB8A8)
    static let badgeCalendar = adaptiveColor(light: 0x3478F6, dark: 0x5A9CF6)

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
