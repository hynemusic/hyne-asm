import Foundation

/// The look of the settings window, the panel and the quick search.
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case original, ableton, hyne, light, retro

    public var title: String {
        switch self {
        case .original: return "Original"
        case .ableton: return "Ableton"
        case .hyne: return "HYNE"
        case .light: return Loc.t("Hell", "Light")
        case .retro: return "Retro PS2"
        }
    }

    public var subtitle: String {
        switch self {
        case .original: return Loc.t("Dunkel mit Blau und Koralle", "Dark with blue and coral")
        case .ableton: return Loc.t("Lives Grau mit Orange", "Live's grey with orange")
        case .hyne: return Loc.t("Aus deinem Live-Theme", "From your Live theme")
        case .light: return Loc.t("Weiß und klar", "White and clean")
        case .retro: return Loc.t("PS2-Schwarz & -Blau, PlayStation-Logofarben", "PS2 black & blue, PlayStation logo colours")
        }
    }
}
