import Foundation

public enum Language: String, Codable, CaseIterable, Sendable {
    case de, en

    /// An explicit choice wins; otherwise German if the system prefers German, else English.
    public static func resolve(_ choice: Language?, preferred: [String] = Locale.preferredLanguages) -> Language {
        if let choice { return choice }
        return preferred.first?.hasPrefix("de") == true ? .de : .en
    }
}

/// Two-language UI text: `Loc.t("Deutsch", "English")`. The app sets `language` from the config.
public enum Loc {
    nonisolated(unsafe) public static var language: Language = .de

    public static func t(_ de: String, _ en: String) -> String {
        language == .de ? de : en
    }
}
