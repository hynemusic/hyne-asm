public enum CloseShortcutAction: Equatable, Sendable { case closeFocused, closeAll, quickSearch }

/// Exact match on key code and modifiers (⌘⌥W is not ⌘W).
public struct ShortcutMatcher {
    public let settings: ShortcutSettings

    public init(settings: ShortcutSettings) { self.settings = settings }

    public func match(keyCode: UInt16, modifiers: ModifierSet) -> CloseShortcutAction? {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        if settings.closeFocused == combo { return .closeFocused }
        if settings.closeAll.contains(combo) { return .closeAll }
        if settings.quickSearch.contains(combo) { return .quickSearch }
        return nil
    }
}
