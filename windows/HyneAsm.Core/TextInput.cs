namespace HyneAsm.Core;

/// <summary>The typed text of the panel filter and the quick search, edited the way a text field is:
/// Ctrl/Cmd+A selects everything (the next character replaces it, Backspace clears it), a word delete drops the last
/// word, a line delete everything. Edits work on Characters (text elements), never on UTF-16 units.</summary>
public sealed class TextInput
{
    public string Text { get; private set; } = "";
    /// <summary>Select-all was pressed: the whole text is selected.</summary>
    public bool IsAllSelected { get; private set; }

    public TextInput(string text = "") { Text = text; }

    public bool IsEmpty => Text.Length == 0;

    /// <summary>Applies an editing key. Returns false for keys that don't edit text (navigation, insert, close).</summary>
    public bool Apply(PanelKey key)
    {
        switch (key.Kind)
        {
            case PanelKeyKind.Character: Type(key.Character); break;
            case PanelKeyKind.Digit: Type(key.Digit.ToString(System.Globalization.CultureInfo.InvariantCulture)); break;
            case PanelKeyKind.Backspace:
                if (IsAllSelected) Text = "";
                else if (Text.Length > 0) Text = DropLastCharacter(Text);
                break;
            case PanelKeyKind.DeleteWord:
                Text = IsAllSelected ? "" : DroppingLastWord(Text);
                break;
            case PanelKeyKind.DeleteToStart:
                Text = "";
                break;
            case PanelKeyKind.SelectAll:
                IsAllSelected = Text.Length > 0;
                return true;
            default:
                return false;
        }
        IsAllSelected = false;
        return true;
    }

    /// <summary>Any other key (arrows, tabs) ends the selection, like clicking into a text field.</summary>
    public void Deselect() => IsAllSelected = false;

    void Type(string s) => Text = IsAllSelected ? s : Text + s;

    static string DropLastCharacter(string s) => s[..LastCharacterStart(s)];

    static int LastCharacterStart(string s)
    {
        var start = 0;
        foreach (var ch in Core.Text.Characters(s)) { if (start + ch.Length >= s.Length) break; start += ch.Length; }
        return start;
    }

    /// <summary>"pro q 4" → "pro q ", "pro q " → "pro ": trailing spaces, then the word before them.</summary>
    internal static string DroppingLastWord(string text)
    {
        var chars = Core.Text.Characters(text).ToList();
        var n = chars.Count;
        while (n > 0 && Core.Text.IsWhitespace(chars[n - 1])) n--;
        while (n > 0 && !Core.Text.IsWhitespace(chars[n - 1])) n--;
        return string.Concat(chars.Take(n));
    }
}
