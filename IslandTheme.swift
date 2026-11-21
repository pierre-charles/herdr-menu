import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// Catppuccin Macchiato (dark) and Latte (light)
struct Theme {
    let base, surface, overlay, subtext, text: Color
    let red, peach, yellow, green, blue, mauve, pink, lavender: Color

    static let macchiato = Theme(
        base: Color(hex: 0x24273a), surface: Color(hex: 0x363a4f), overlay: Color(hex: 0x6e738d),
        subtext: Color(hex: 0xa5adcb), text: Color(hex: 0xcad3f5),
        red: Color(hex: 0xed8796), peach: Color(hex: 0xf5a97f), yellow: Color(hex: 0xeed49f), green: Color(hex: 0xa6da95),
        blue: Color(hex: 0x8aadf4), mauve: Color(hex: 0xc6a0f6), pink: Color(hex: 0xf5bde6), lavender: Color(hex: 0xb7bdf8))

    static let latte = Theme(
        base: Color(hex: 0xeff1f5), surface: Color(hex: 0xccd0da), overlay: Color(hex: 0x9ca0b0),
        subtext: Color(hex: 0x6c6f85), text: Color(hex: 0x4c4f69),
        red: Color(hex: 0xd20f39), peach: Color(hex: 0xfe640b), yellow: Color(hex: 0xdf8e1d), green: Color(hex: 0x40a02b),
        blue: Color(hex: 0x1e66f5), mauve: Color(hex: 0x8839ef), pink: Color(hex: 0xea76cb), lavender: Color(hex: 0x7287fd))

    static func current(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .macchiato : .latte }

    /// The Catppuccin colour whose hue is nearest the macOS accent colour (graphite gets lavender)
    var accent: Color {
        let system = NSColor.controlAccentColor.usingColorSpace(.sRGB)!
        if system.saturationComponent < 0.2 { return lavender }
        func distance(_ c: Color) -> CGFloat {
            let d = abs(NSColor(c).usingColorSpace(.sRGB)!.hueComponent - system.hueComponent)
            return min(d, 1 - d)
        }
        return [red, peach, yellow, green, blue, mauve, pink].min { distance($0) < distance($1) }!
    }

    func color(for state: String) -> Color {
        switch state {
        case "blocked": peach
        case "working": accent
        case "done": green
        case "error": red
        default: overlay
        }
    }
}
