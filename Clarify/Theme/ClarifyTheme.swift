import SwiftUI

struct ClarifyTheme: Equatable {
    let name: String
    let background: Color
    let headline: Color
    let body: Color
    let tertiary: Color
    let surface: Color
    let button: Color
    let buttonText: Color
    let shimmer: Color
    let useVibrancy: Bool
    let error: Color
    let success: Color
    let info: Color

    // MARK: - Palettes

    static let system = ClarifyTheme(
        name: "System",
        background: .clear,
        headline: .primary,
        body: .primary,
        tertiary: .secondary,
        surface: Color(.quaternaryLabelColor),
        button: .accentColor,
        buttonText: .white,
        shimmer: .white,
        useVibrancy: true,
        error: Color(hex: 0xFF9F0A),
        success: Color(hex: 0x30D158),
        info: Color(hex: 0x0A84FF)
    )

    static let darkViolet = ClarifyTheme(
        name: "Dark Violet",
        background: Color(hex: 0x16161A),
        headline: Color.white,
        body: Color.white.opacity(0.85),
        tertiary: Color.white.opacity(0.55),
        surface: Color.white.opacity(0.08),
        button: Color(hex: 0x7F5AF0),
        buttonText: Color.white,
        shimmer: Color(hex: 0x7F5AF0).opacity(0.4),
        useVibrancy: false,
        error: Color(hex: 0xFFBD2E),
        success: Color(hex: 0x2CB67D),
        info: Color(hex: 0x7F5AF0).opacity(0.8)
    )

    static let warmCream = ClarifyTheme(
        name: "Warm Cream",
        background: Color(hex: 0xFEF6E4),
        headline: Color(hex: 0x001858),
        body: Color(hex: 0x001858).opacity(0.85),
        tertiary: Color(hex: 0x001858).opacity(0.55),
        surface: Color(hex: 0x001858).opacity(0.08),
        button: Color(hex: 0xF582AE),
        buttonText: Color.white,
        shimmer: Color(hex: 0xF582AE).opacity(0.4),
        useVibrancy: false,
        error: Color(hex: 0xE16162),
        success: Color(hex: 0x2CB67D),
        info: Color(hex: 0x3DA9FC)
    )

    static let allThemes: [ClarifyTheme] = [.system, .darkViolet, .warmCream]

    static func named(_ name: String) -> ClarifyTheme {
        allThemes.first { $0.name == name } ?? .system
    }

    /// Accent-tinted user bubble background.
    var userBubble: Color { button.opacity(0.22) }
    /// Neutral assistant bubble background.
    var assistantBubble: Color { surface }
    /// Divider color that's visible on all themes.
    var divider: Color { tertiary.opacity(0.3) }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - SwiftUI Environment

private struct ClarifyThemeKey: EnvironmentKey {
    static let defaultValue: ClarifyTheme = .system
}

extension EnvironmentValues {
    var clarifyTheme: ClarifyTheme {
        get { self[ClarifyThemeKey.self] }
        set { self[ClarifyThemeKey.self] = newValue }
    }
}
