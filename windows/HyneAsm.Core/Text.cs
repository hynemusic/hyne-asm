using System.Globalization;
using System.Text;

namespace HyneAsm.Core;

/// <summary>
/// Swift <c>String</c> semantics that C# strings lack. Swift compares, hashes and searches strings by
/// <em>Character</em> (grapheme cluster) under canonical equivalence: "Ü" as U+00DC equals "U" + U+0308, and
/// "q" is no prefix of "q" + U+0301. Plugin names from Mac file systems arrive decomposed (NFD), so every place where
/// Swift compares or hashes names goes through these helpers. Nothing here depends on the current culture.
/// </summary>
public static class Text
{
    /// <summary>NFC + Swift's <c>lowercased()</c>: the form to compare lowercased names in.</summary>
    public static string Normalize(string s) => Nfc(Lower(s));

    /// <summary>Canonical composition; ASCII (nearly every plugin name) is returned as is.</summary>
    public static string Nfc(string s) => IsAscii(s) || s.IsNormalized(NormalizationForm.FormC) ? s : s.Normalize(NormalizationForm.FormC);

    /// <summary>Swift's <c>lowercased()</c>: culture-independent, keeps the normalization form, full mapping of "İ".</summary>
    public static string Lower(string s)
    {
        var lower = s.ToLowerInvariant();
        return lower.Contains('İ') ? lower.Replace("İ", "i̇", StringComparison.Ordinal) : lower;
    }

    /// <summary>Swift <c>==</c> on strings.</summary>
    public static bool Equal(string? a, string? b) =>
        a is null || b is null ? a == b : string.Equals(a, b, StringComparison.Ordinal) || string.Equals(Nfc(a), Nfc(b), StringComparison.Ordinal);

    /// <summary>Swift <c>==</c> on string arrays.</summary>
    public static bool Equal(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (a.Count != b.Count) return false;
        for (var i = 0; i < a.Count; i++) if (!Equal(a[i], b[i])) return false;
        return true;
    }

    /// <summary>Keys of Swift <c>[String: …]</c> and <c>Set&lt;String&gt;</c>: canonically equal strings are one key.</summary>
    public static readonly IEqualityComparer<string> Canonical = new CanonicalComparer();

    sealed class CanonicalComparer : IEqualityComparer<string>
    {
        public bool Equals(string? x, string? y) => Equal(x, y);
        public int GetHashCode(string s) => StringComparer.Ordinal.GetHashCode(Nfc(s));
    }

    /// <summary>Swift <c>&lt;</c> on strings: Unicode scalar order of the NFC forms.</summary>
    public static int CompareScalars(string a, string b)
    {
        var (x, y) = (Nfc(a), Nfc(b));
        int i = 0, j = 0;
        while (i < x.Length && j < y.Length)
        {
            var rx = Rune.GetRuneAt(x, i);
            var ry = Rune.GetRuneAt(y, j);
            if (rx != ry) return rx.Value.CompareTo(ry.Value);
            i += rx.Utf16SequenceLength;
            j += ry.Utf16SequenceLength;
        }
        return (x.Length - i).CompareTo(y.Length - j);
    }

    static readonly CompareInfo Invariant = CultureInfo.InvariantCulture.CompareInfo;

    /// <summary>Swift's <c>localizedCaseInsensitiveCompare</c>, with the root collation instead of the Mac's locale
    /// (the same for the names this app sorts; Swift's recordings ran with en_DE).</summary>
    public static int LocalizedCaseInsensitiveCompare(string a, string b) => Invariant.Compare(a, b, CompareOptions.IgnoreCase);

    /// <summary>Swift's <c>hasPrefix</c>: whole Characters, canonical equivalence.</summary>
    public static bool HasPrefix(string s, string prefix)
    {
        if (prefix.Length == 0) return true;
        var (a, p) = (Nfc(s), Nfc(prefix));
        return a.StartsWith(p, StringComparison.Ordinal) && IsBoundary(a, p.Length);
    }

    /// <summary>Swift's <c>hasSuffix</c>: whole Characters, canonical equivalence.</summary>
    public static bool HasSuffix(string s, string suffix)
    {
        if (suffix.Length == 0) return true;
        var (a, p) = (Nfc(s), Nfc(suffix));
        return a.EndsWith(p, StringComparison.Ordinal) && IsBoundary(a, a.Length - p.Length);
    }

    /// <summary>Swift's <c>contains</c> for a substring: a run of whole Characters, canonical equivalence.</summary>
    public static bool Contains(string s, string part)
    {
        if (part.Length == 0) return true;
        var (a, p) = (Nfc(s), Nfc(part));
        for (var i = a.IndexOf(p, StringComparison.Ordinal); i >= 0; i = a.IndexOf(p, i + 1, StringComparison.Ordinal))
            if (IsBoundary(a, i) && IsBoundary(a, i + p.Length)) return true;
        return false;
    }

    /// <summary><see cref="HasPrefix"/> for strings already in NFC.</summary>
    internal static bool HasPrefixNfc(string s, string prefix) =>
        s.StartsWith(prefix, StringComparison.Ordinal) && IsBoundary(s, prefix.Length);

    /// <summary><see cref="Contains"/> for strings already in NFC.</summary>
    internal static bool ContainsNfc(string s, string part)
    {
        if (part.Length == 0) return true;
        for (var i = s.IndexOf(part, StringComparison.Ordinal); i >= 0; i = s.IndexOf(part, i + 1, StringComparison.Ordinal))
            if (IsBoundary(s, i) && IsBoundary(s, i + part.Length)) return true;
        return false;
    }

    /// <summary>Swift's <c>count</c>: the number of Characters.</summary>
    public static int Count(string s) => IsAscii(s) && !s.Contains('\r') ? s.Length : new StringInfo(s).LengthInTextElements;

    /// <summary>The Characters of a string, in order (Swift <c>for ch in s</c>).</summary>
    public static IEnumerable<string> Characters(string s)
    {
        for (var i = 0; i < s.Length;)
        {
            var n = NextCharacterLength(s, i);
            yield return s.Substring(i, n);
            i += n;
        }
    }

    /// <summary>Length in UTF-16 units of the Character at <paramref name="i"/>; ASCII without a combining follower is 1.</summary>
    static int NextCharacterLength(string s, int i)
    {
        var c = s[i];
        if (c < 0x80 && (i + 1 == s.Length || (s[i + 1] < 0x80 && !(c == '\r' && s[i + 1] == '\n')))) return 1;
        return StringInfo.GetNextTextElementLength(s, i);
    }

    /// <summary>Swift's <c>dropFirst(n)</c> / <c>removeFirst(n)</c> on a String: drops <paramref name="n"/> Characters.</summary>
    public static string DropFirst(string s, int n)
    {
        var i = 0;
        for (; n > 0 && i < s.Length; n--) i += NextCharacterLength(s, i);
        return s[i..];
    }

    /// <summary>True when a Character starts at UTF-16 offset <paramref name="index"/> (or it is the end).</summary>
    public static bool IsBoundary(string s, int index)
    {
        if (index <= 0 || index >= s.Length) return true;
        if (s[index] < 0x80 && s[index - 1] < 0x80) return !(s[index - 1] == '\r' && s[index] == '\n');
        for (var i = 0; i < s.Length;)
        {
            if (i == index) return true;
            if (i > index) return false;
            i += NextCharacterLength(s, i);
        }
        return false;
    }

    /// <summary>Swift's <c>trimmingCharacters(in: .whitespaces)</c>: spaces (Zs) and tabs, not line breaks.</summary>
    public static string TrimWhitespaces(string s)
    {
        int start = 0, end = s.Length;
        while (start < end && IsSpaceOrTab(s[start])) start++;
        while (end > start && IsSpaceOrTab(s[end - 1])) end--;
        return start == 0 && end == s.Length ? s : s[start..end];
    }

    static bool IsSpaceOrTab(char c) => c == '\t' || char.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;

    /// <summary>Swift's <c>lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")</c>.</summary>
    public static string CollapseWhitespace(string lowered)
    {
        if (IsAscii(lowered))   // CR LF is one Character in Swift, but both halves are whitespace: same result
            return string.Join(" ", lowered.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        var parts = new List<string>();
        var current = new StringBuilder();
        foreach (var ch in Characters(lowered))
        {
            if (IsWhitespace(ch)) { if (current.Length > 0) { parts.Add(current.ToString()); current.Clear(); } }
            else current.Append(ch);
        }
        if (current.Length > 0) parts.Add(current.ToString());
        return string.Join(" ", parts);
    }

    // MARK: Character properties (Swift: the first scalar's Unicode properties)

    /// <summary>Swift <c>Character.isLetter || isNumber</c>: Alphabetic or numeric first scalar.</summary>
    public static bool IsLetterOrNumber(string ch)
    {
        var c = Rune.GetUnicodeCategory(Rune.GetRuneAt(ch, 0));
        return c is UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter or UnicodeCategory.LetterNumber
            or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.OtherNumber;
    }

    /// <summary>Swift <c>Character.isNumber</c>.</summary>
    public static bool IsNumber(string ch) =>
        Rune.GetUnicodeCategory(Rune.GetRuneAt(ch, 0)) is UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber
            or UnicodeCategory.OtherNumber;

    /// <summary>Swift <c>Character.isWhitespace</c> (Unicode White_Space of the first scalar).</summary>
    public static bool IsWhitespace(string ch) => Rune.IsWhiteSpace(Rune.GetRuneAt(ch, 0));

    /// <summary>Swift <c>Character.isUppercase</c>: an uppercase letter, or a cased Character that uppercasing keeps.</summary>
    public static bool IsUppercase(string ch)
    {
        if (ch.Length == 1 && ch[0] < 0x80) return char.IsAsciiLetterUpper(ch[0]);
        if (ch.Length == 1 && char.IsUpper(ch[0])) return true;
        var (upper, lower) = (Nfc(ch.ToUpperInvariant()), Nfc(Lower(ch)));
        var self = Nfc(ch);
        return upper == self && lower != self;
    }

    /// <summary>Swift <c>Character.isLowercase</c>: a lowercase letter, or a cased Character that lowercasing keeps.</summary>
    public static bool IsLowercase(string ch)
    {
        if (ch.Length == 1 && ch[0] < 0x80) return char.IsAsciiLetterLower(ch[0]);
        if (ch.Length == 1 && char.IsLower(ch[0])) return true;
        var (upper, lower) = (Nfc(ch.ToUpperInvariant()), Nfc(Lower(ch)));
        var self = Nfc(ch);
        return lower == self && upper != self;
    }

    internal static bool IsAscii(string s)
    {
        foreach (var c in s) if (c >= 0x80) return false;
        return true;
    }
}
