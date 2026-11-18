import Foundation

/// The typed text of the panel filter and the quick search, edited the way a macOS text field is:
/// ⌘A selects everything (the next character replaces it, ⌫ clears it), ⌥⌫ deletes the last word,
/// ⌘⌫ deletes to the start.
public struct TextInput: Equatable, Sendable {
    public private(set) var text = ""
    /// ⌘A was pressed: the whole text is selected.
    public private(set) var isAllSelected = false

    public init(_ text: String = "") { self.text = text }

    public var isEmpty: Bool { text.isEmpty }

    /// Applies an editing key. Returns false for keys that don't edit text (navigation, insert, close).
    public mutating func apply(_ key: PanelKey) -> Bool {
        switch key {
        case .character(let c): type(String(c))
        case .digit(let d): type(String(d))
        case .backspace:
            if isAllSelected { text = "" } else if !text.isEmpty { text.removeLast() }
        case .deleteWord:
            if isAllSelected { text = "" } else { text = Self.droppingLastWord(text) }
        case .deleteToStart:
            text = ""
        case .selectAll:
            isAllSelected = !text.isEmpty
            return true
        default:
            return false
        }
        isAllSelected = false
        return true
    }

    /// Any other key (arrows, tabs) ends the selection, like clicking into a text field.
    public mutating func deselect() { isAllSelected = false }

    private mutating func type(_ s: String) {
        text = isAllSelected ? s : text + s
    }

    /// "pro q 4" → "pro q ", "pro q " → "pro ": trailing spaces, then the word before them.
    static func droppingLastWord(_ text: String) -> String {
        var t = Substring(text)
        while let last = t.last, last.isWhitespace { t.removeLast() }
        while let last = t.last, !last.isWhitespace { t.removeLast() }
        return String(t)
    }
}
