using System.Globalization;
using System.Text;

namespace HyneAsm.Core;

/// <summary>Forgiving name search: case, spaces and punctuation don't matter, words may be abbreviated and every
/// typed word must appear. "pro q 4", "proq4", "pro 4" all find "Pro-Q 4"; "pro 4" does not find "Pro-L 2".
/// Higher score = better match (name starts with it &gt; words in order &gt; words anywhere &gt; letters inside).
/// (<c>UsageStore</c> and <c>UsageExport</c>, also in SearchMatcher.swift, are ported in UsageStore.cs.)</summary>
public static class SearchMatcher
{
    public sealed class Prepared
    {
        /// <summary>Lowercased, NFC (Swift compares canonically; NFC makes ordinal checks give the same answers).</summary>
        internal readonly string Lower;
        /// <summary><see cref="Lower"/> without surrounding spaces (Swift trims the query on every call).</summary>
        internal readonly string TrimmedLower;
        internal readonly string Compact;
        /// <summary>Lowercased words, NFC.</summary>
        internal readonly string[] Words;
        /// <summary>The words as UTF-8 in the form they were typed or listed (Swift's typo check compares bytes,
        /// so a decomposed name only matches a decomposed query there).</summary>
        internal readonly byte[][] WordBytes;

        public Prepared(string text)
        {
            Lower = Text.Normalize(text);
            TrimmedLower = Text.TrimWhitespaces(Lower);
            Compact = SearchMatcher.Compact(Lower);
            var raw = RawWords(text);
            Words = raw.Select(Text.Nfc).ToArray();
            WordBytes = raw.Select(w => Encoding.UTF8.GetBytes(w)).ToArray();
        }
    }

    public static int? Score(string name, string query) => Score(new Prepared(name), new Prepared(query));

    public static int? Score(Prepared name, Prepared query)
    {
        var q = query.TrimmedLower;
        if (q.Length == 0 || query.Compact.Length == 0) return 0;
        if (HasPrefix(name.Lower, q)) return 100;
        if (HasPrefix(name.Compact, query.Compact)) return 90;
        if (PrefixesInOrder(query.Words, name.Words))
            return query.Words.Length > 0 && name.Words.Length > 0 && HasPrefix(name.Words[0], query.Words[0]) ? 85 : 80;
        if (query.Words.All(w => name.Words.Any(n => HasPrefix(n, w)))) return 70;
        if (Contains(name.Compact, query.Compact)) return 60;
        if (query.Words.All(w => Contains(name.Compact, w))) return 50;
        if (TypoMatch(query.WordBytes, name.WordBytes)) return TypoScore;
        return null;
    }

    /// <summary>Score of a match with a typo — below every exact match, above a tag match.</summary>
    public const int TypoScore = 40;
    /// <summary>Score of an item found only through its kind ("comp" → every compressor).</summary>
    public const int TagScore = 30;

    /// <summary>Name score, else a tag hit when the item's icon kind is one the query stands for.</summary>
    public static int? Score(Prepared name, Prepared query, string iconID, IReadOnlySet<string> tagIcons) =>
        Score(name, query) ?? (tagIcons.Contains(iconID) ? TagScore : null);

    /// <summary>Every typed word appears in the name, words of ≥ 4 letters with one typo (≥ 7 letters: two).
    /// Shorter words and numbers must match exactly — too many names are one edit away from "eq" or "pro".
    /// Typos in the first letter are not forgiven: that keeps the check cheap for 20,000 names.</summary>
    internal static bool TypoMatch(byte[][] query, byte[][] name)
    {
        if (query.Length == 0 || !query.Any(w => w.Length >= 4)) return false;
        foreach (var w in query)
        {
            if (name.Any(n => n.AsSpan().StartsWith(w))) continue;   // exact: no distance needed
            // Short words and numbers must match exactly ("Pro-Q 4" is not "Pro-Q 3").
            if (w.Length < 4 || !w.Any(b => b is >= 97 and <= 122)) return false;
            var allowed = w.Length >= 7 ? 2 : 1;
            var found = false;
            foreach (var n in name)
            {
                if (n.Length == 0 || n[0] != w[0]) continue;
                var prefix = n.AsSpan(0, Math.Min(n.Length, w.Length));
                if (EditDistance(w, prefix, allowed) <= allowed
                    || (Math.Abs(n.Length - w.Length) <= allowed && EditDistance(w, n, allowed) <= allowed))
                {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }

    /// <summary>Edit distance with swapped neighbours counting as one edit ("sreum" → "serum"). Stops early once every
    /// path exceeds <paramref name="limit"/> (returns limit + 1 then).</summary>
    internal static int EditDistance(ReadOnlySpan<byte> a, ReadOnlySpan<byte> b, int limit = int.MaxValue)
    {
        if (a.IsEmpty) return b.Length;
        if (b.IsEmpty) return a.Length;
        if (Math.Abs(a.Length - b.Length) > limit) return limit + 1;
        var width = b.Length + 1;
        Span<int> buf = width * 3 <= 768 ? stackalloc int[width * 3] : new int[width * 3];
        int prev2 = 0, prev = width, cur = 2 * width;   // row offsets
        for (var j = 0; j <= b.Length; j++) { buf[prev + j] = j; buf[prev2 + j] = 0; }
        for (var i = 1; i <= a.Length; i++)
        {
            buf[cur] = i;
            var rowMin = i;
            for (var j = 1; j <= b.Length; j++)
            {
                var cost = a[i - 1] == b[j - 1] ? 0 : 1;
                var v = Math.Min(Math.Min(buf[prev + j] + 1, buf[cur + j - 1] + 1), buf[prev + j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) v = Math.Min(v, buf[prev2 + j - 2] + 1);
                buf[cur + j] = v;
                rowMin = Math.Min(rowMin, v);
            }
            if (rowMin > limit) return limit + 1;
            (prev2, prev, cur) = (prev, cur, prev2);
        }
        return buf[prev + b.Length];
    }

    internal static int EditDistance(string a, string b) => EditDistance(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));

    static bool PrefixesInOrder(string[] query, string[] name)
    {
        var i = 0;
        foreach (var w in query)
        {
            var hit = -1;
            for (var k = i; k < name.Length; k++) if (HasPrefix(name[k], w)) { hit = k; break; }
            if (hit < 0) return false;
            i = hit + 1;
        }
        return true;
    }

    /// <summary>Letters, marks and numbers only (Swift <c>CharacterSet.alphanumerics</c>, scalar by scalar).</summary>
    internal static string Compact(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var r in s.EnumerateRunes())
        {
            if (r.IsAscii ? char.IsAsciiLetterOrDigit((char)r.Value) : IsAlphanumeric(r)) sb.Append(r.ToString());
        }
        return Text.Nfc(sb.ToString());
    }

    static bool IsAlphanumeric(Rune r) => Rune.GetUnicodeCategory(r) switch
    {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter => true,
        UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark => true,
        UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber => true,
        _ => false,
    };

    /// <summary>Words split at spaces/punctuation and at camelCase ("ValhallaVintageVerb" → valhalla, vintage, verb), NFC.</summary>
    internal static string[] Words(string s) => RawWords(s).Select(Text.Nfc).ToArray();

    /// <summary><see cref="Words"/> in the normalization form of <paramref name="s"/>.</summary>
    static List<string> RawWords(string s)
    {
        var result = new List<string>();
        var current = new StringBuilder();
        string? previous = null;
        foreach (var ch in Text.Characters(s))
        {
            if (!Text.IsLetterOrNumber(ch))
            {
                if (current.Length > 0) { result.Add(current.ToString()); current.Clear(); }
            }
            else
            {
                if (previous != null && Text.IsLowercase(previous) && Text.IsUppercase(ch) && current.Length > 0)
                {
                    result.Add(current.ToString());
                    current.Clear();
                }
                current.Append(ch);
            }
            previous = ch;
        }
        if (current.Length > 0) result.Add(current.ToString());
        return result.Select(Text.Lower).ToList();
    }

    // Both sides are NFC already (Prepared), so only the Character boundary needs checking.
    static bool HasPrefix(string s, string p) => Text.HasPrefixNfc(s, p);

    static bool Contains(string s, string p) => Text.ContainsNfc(s, p);
}
