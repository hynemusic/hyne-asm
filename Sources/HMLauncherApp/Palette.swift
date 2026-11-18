import AppKit
import SwiftUI
import HMLauncherCore

/// All colours (and a few shape/type choices) of one theme. Every colour token in the app reads from
/// `Palette.current`, so switching the theme re-colours the settings, the panel and the quick search.
struct Palette {
    var isDark: Bool
    // Settings surfaces, darkest (dark themes) / lightest (light theme) first.
    var canvas: Color
    var sidebar: Color
    var surface: Color
    var raised: Color
    var hover: Color
    var hairline: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    /// Highlights: active marks, folder/star icons, caret, text buttons.
    var accent: Color
    /// Prominent buttons, selection, lit keys. `onAccentStrong` is the text on it.
    var accentStrong: Color
    var onAccentStrong: Color = .white
    /// Text on `accent` (dark on the yellow/orange accents).
    var onAccent: Color = .white
    var success = Color(red: 0.30, green: 0.80, blue: 0.50)
    var warning = Color(red: 1.0, green: 0.75, blue: 0.30)
    // Panel, quick search, folder list.
    var panelSurface: Color
    var panelRow: Color
    var panelStroke: Color
    /// Neutral ink for small tints on surfaces (key caps, chips): white on dark themes, black on the light one.
    var ink: Color
    var keyboardBase: Color
    var keyFill: Color
    /// Retro: the four PlayStation logo colours (stripe on top of the windows, 1–9 key caps).
    var logoColors: [Color] = []
    var radiusScale: CGFloat = 1
    var fontDesign: Font.Design = .default

    private static func hex(_ v: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: alpha)
    }

    static func make(_ theme: AppTheme) -> Palette {
        switch theme {
        case .original:
            return Palette(isDark: true,
                           canvas: Color(white: 0.105), sidebar: Color(white: 0.135), surface: Color(white: 0.145),
                           raised: Color(white: 0.195), hover: Color(white: 0.235), hairline: Color.white.opacity(0.07),
                           textPrimary: Color(white: 0.94), textSecondary: Color(white: 0.68), textTertiary: Color(white: 0.56),
                           accent: hex(0xFF6B57), accentStrong: hex(0x3D5AFE),
                           panelSurface: Color(white: 0.115), panelRow: Color(white: 0.17), panelStroke: Color.white.opacity(0.09),
                           ink: .white, keyboardBase: Color(white: 0.075), keyFill: Color(white: 0.2))
        case .ableton:
            // Live 12's neutral dark greys with its orange highlight and light-blue selection.
            return Palette(isDark: true,
                           canvas: hex(0x1E1E1E), sidebar: hex(0x262626), surface: hex(0x2C2C2C),
                           raised: hex(0x3A3A3A), hover: hex(0x464646), hairline: Color.white.opacity(0.08),
                           textPrimary: hex(0xE6E6E6), textSecondary: hex(0xB3B3B3), textTertiary: hex(0x8C8C8C),
                           accent: hex(0xFFA529), accentStrong: hex(0xFF8C1A), onAccentStrong: hex(0x111111), onAccent: hex(0x111111),
                           panelSurface: hex(0x242424), panelRow: hex(0x363636), panelStroke: Color.white.opacity(0.10),
                           ink: .white, keyboardBase: hex(0x161616), keyFill: hex(0x3A3A3A))
        case .hyne:
            // From "HYNE Theme Final.ask": SurfaceArea #171717, Desktop #222222, SurfaceBackground #2a2a2a,
            // DetailViewBackground #3a3a3a, SurfaceHighlight #424242, ChosenDefault #3cabf7, ViewControlOn #ffb901.
            return Palette(isDark: true,
                           canvas: hex(0x171717), sidebar: hex(0x222222), surface: hex(0x2A2A2A),
                           raised: hex(0x3A3A3A), hover: hex(0x424242), hairline: Color.white.opacity(0.07),
                           textPrimary: .white, textSecondary: hex(0xC9C9C9), textTertiary: hex(0x8C8C8C),
                           accent: hex(0xFFB901), accentStrong: hex(0x3CABF7), onAccentStrong: hex(0x0D0D0D), onAccent: hex(0x0D0D0D),
                           warning: hex(0xF34C40),
                           panelSurface: hex(0x1F1F1F), panelRow: hex(0x2A2A2A), panelStroke: Color.white.opacity(0.09),
                           ink: .white, keyboardBase: hex(0x131313), keyFill: hex(0x3A3A3A))
        case .light:
            return Palette(isDark: false,
                           canvas: hex(0xF5F5F7), sidebar: hex(0xEBEBEE), surface: .white,
                           raised: hex(0xF0F0F3), hover: hex(0xE4E4E9), hairline: Color.black.opacity(0.09),
                           textPrimary: hex(0x1D1D1F), textSecondary: hex(0x55555C), textTertiary: hex(0x7A7A82),
                           accent: hex(0xE0442F), accentStrong: hex(0x3D5AFE),
                           success: hex(0x1F9D55), warning: hex(0xC77700),
                           panelSurface: .white, panelRow: hex(0xF2F2F5), panelStroke: Color.black.opacity(0.10),
                           ink: .black, keyboardBase: hex(0xDADADF), keyFill: .white)
        case .retro:
            // PS1: light grey console plastic (lighter lid, darker side modules and seams), turquoise like the
            // "POWER" label, blue like "OPEN", the green power LED, and the four PlayStation logo colours
            // (red #DF0024, yellow #F3C300, teal #00AC9F, blue #2E6DB4) on the stripe and the 1–9 keys.
            let red = hex(0xDF0024), yellow = hex(0xF3C300), teal = hex(0x00AC9F), blue = hex(0x2E6DB4)
            return Palette(isDark: false,
                           canvas: hex(0xBFBFC1), sidebar: hex(0xA9A9AC), surface: hex(0xCBCBCD),
                           raised: hex(0xD6D6D8), hover: hex(0xDFDFE1), hairline: Color.black.opacity(0.16),
                           textPrimary: hex(0x1C1C20), textSecondary: hex(0x45454C), textTertiary: hex(0x5E5E66),
                           accent: hex(0x0E8C87), accentStrong: hex(0x2D6FB7),
                           success: hex(0x3DA516), warning: hex(0xB07A00),
                           panelSurface: hex(0xC2C2C4), panelRow: hex(0xD3D3D5), panelStroke: Color.black.opacity(0.22),
                           ink: .black, keyboardBase: hex(0x9C9C9F), keyFill: hex(0xD3D3D5),
                           logoColors: [red, yellow, teal, blue],
                           radiusScale: 0.5, fontDesign: .monospaced)
        }
    }

    /// Read from every view's body (main thread); written only by `apply`.
    nonisolated(unsafe) static private(set) var current = Palette.make(.original)
    nonisolated(unsafe) static private(set) var theme: AppTheme = .original

    /// Switches the palette and the window appearance (menus, alerts, text fields follow light/dark).
    @MainActor static func apply(_ theme: AppTheme) {
        guard theme != self.theme || NSApp.appearance == nil else { return }
        self.theme = theme
        current = make(theme)
        NSApp.appearance = NSAppearance(named: current.isDark ? .darkAqua : .aqua)
    }
}

extension Font {
    /// System font in the theme's design (monospaced in Retro).
    static func themed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: Palette.current.fontDesign)
    }
}

extension CGFloat {
    /// A corner radius scaled for the theme (blockier in Retro).
    var themedRadius: CGFloat { self * Palette.current.radiusScale }
}

/// The PlayStation-logo stripe of the Retro theme (nothing in the other themes).
struct LogoStripe: View {
    var height: CGFloat = 3
    var body: some View {
        if !Palette.current.logoColors.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(Palette.current.logoColors.enumerated()), id: \.offset) { _, c in Rectangle().fill(c) }
            }
            .frame(height: height)
        }
    }
}
