namespace HyneAsm.Core;

/// <summary>Finds Live's items for the entries of an LES menu. Only the name normalization is here so far
/// (plugin variant keys use it); the matcher itself is ported with the LES import.</summary>
public sealed partial class LESMatcher
{
    /// <summary>Lowercase, single spaces (keeps the normalization form, as Swift does).</summary>
    internal static string Normalize(string s) => Text.CollapseWhitespace(Text.Lower(s));
}
