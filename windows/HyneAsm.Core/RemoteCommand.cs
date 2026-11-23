using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

public enum RemoteCommandKind { Insert, Action, QuickSearch, Panel, Profile, NextProfile, ClosePluginWindows }

/// <summary>A command from outside the app: a Stream Deck button, a shortcut tool, a script.
/// Arrives as <c>hyneasm://&lt;command&gt;?…</c> or, with the Stream Deck connection on, <c>http://127.0.0.1:47821/&lt;command&gt;?…</c>.
/// Swift's enum with associated values: <see cref="Name"/> is set for Insert and Profile, <see cref="Action"/> for Action.</summary>
public sealed record RemoteCommand
{
    public const string Scheme = "hyneasm";
    public const ushort HttpPort = 47821;

    public RemoteCommandKind Kind { get; }
    public string? Name { get; }
    public LiveAction? Action { get; }

    RemoteCommand(RemoteCommandKind kind, string? name = null, LiveAction? action = null) { Kind = kind; Name = name; Action = action; }

    public static RemoteCommand Insert(string name) => new(RemoteCommandKind.Insert, name);
    public static RemoteCommand OfAction(LiveAction action) => new(RemoteCommandKind.Action, action: action);
    public static RemoteCommand Profile(string name) => new(RemoteCommandKind.Profile, name);
    public static RemoteCommand QuickSearch { get; } = new(RemoteCommandKind.QuickSearch);
    public static RemoteCommand Panel { get; } = new(RemoteCommandKind.Panel);
    public static RemoteCommand NextProfile { get; } = new(RemoteCommandKind.NextProfile);
    public static RemoteCommand ClosePluginWindows { get; } = new(RemoteCommandKind.ClosePluginWindows);

    /// <summary>Swift <c>init?(url:)</c>. Reads the URL as written (<see cref="Uri.OriginalString"/>), the way
    /// <c>URLComponents</c> does: no host lowercasing, percent-escapes decoded, "+" kept.</summary>
    public static RemoteCommand? TryParse(Uri url) => url.IsAbsoluteUri ? TryParse(url.OriginalString) : null;

    /// <summary>Same, from the URL text (null when it is not an absolute URL).</summary>
    public static RemoteCommand? TryParse(string url)
    {
        if (UrlParts.Parse(url) is not { } parts) return null;
        List<string> path;
        switch (parts.Scheme)
        {
            case Scheme:
                path = new List<string> { parts.Host ?? "" }.Concat(SplitPath(parts.Path)).Where(s => s.Length > 0).ToList();
                break;
            case "http":
                if (parts.Host is not ("127.0.0.1" or "localhost")) return null;
                path = SplitPath(parts.Path);
                break;
            default:
                return null;
        }
        var query = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (name, value) in parts.QueryItems) query[name] = value ?? "";
        var trimmedName = query.TryGetValue("name", out var n) ? Text.TrimWhitespaces(n) : null;

        switch (path.Count > 0 ? Text.Lower(path[0]) : null)
        {
            case "insert":
                return string.IsNullOrEmpty(trimmedName) ? null : Insert(trimmedName);
            case "action":
                if (trimmedName == null || !LiveActionKinds.TryGetValue(trimmedName, out var kind)) return null;
                return OfAction(new LiveAction(kind,
                    query.TryGetValue("value", out var v) ? SwiftNumbers.ParseDouble(v) : null,
                    query.TryGetValue("value2", out var v2) ? SwiftNumbers.ParseInt(v2) : null));
            case "quicksearch" or "quick-search":
                return QuickSearch;
            case "panel":
                return Panel;
            case "profile":
                if (path.Count > 1 && Text.Lower(path[1]) == "next") return NextProfile;
                return string.IsNullOrEmpty(trimmedName) ? null : Profile(trimmedName);
            case "close-plugin-windows":
                return ClosePluginWindows;
            default:
                return null;
        }
    }

    /// <summary>The link that triggers this command (for "Copy Stream Deck Link"). HTTP links carry the install's token.
    /// The exact link text is <see cref="Uri.OriginalString"/> (<see cref="Uri.ToString"/> unescapes some characters).</summary>
    public Uri Link(bool http, string? token = null) => new(LinkText(http, token));

    string LinkText(bool http, string? token)
    {
        string path;
        var query = new List<(string Name, string Value)>();
        switch (Kind)
        {
            case RemoteCommandKind.Insert: path = "insert"; query.Add(("name", Name!)); break;
            case RemoteCommandKind.Action:
                path = "action";
                query.Add(("name", SwiftJson.RawValue(Action!.Kind)));
                if (Action.Value is { } value) query.Add(("value", SwiftNumbers.LinkValue(value)));
                if (Action.Value2 is { } value2) query.Add(("value2", value2.ToString(CultureInfo.InvariantCulture)));
                break;
            case RemoteCommandKind.QuickSearch: path = "quicksearch"; break;
            case RemoteCommandKind.Panel: path = "panel"; break;
            case RemoteCommandKind.Profile: path = "profile"; query.Add(("name", Name!)); break;
            case RemoteCommandKind.NextProfile: path = "profile/next"; break;
            case RemoteCommandKind.ClosePluginWindows: path = "close-plugin-windows"; break;
            default: throw new ArgumentOutOfRangeException(nameof(Kind));
        }
        var sb = new StringBuilder();
        if (http) sb.Append("http://127.0.0.1:").Append(HttpPort).Append('/').Append(path);
        else sb.Append(Scheme).Append("://").Append(path);   // "profile/next" → host "profile", path "/next"
        if (http && token != null) query.Add(("token", token));
        for (var i = 0; i < query.Count; i++)
            sb.Append(i == 0 ? '?' : '&').Append(EncodeQuery(query[i].Name)).Append('=').Append(EncodeQuery(query[i].Value));
        return sb.ToString();
    }

    /// <summary><c>URLComponents.queryItems</c> encoding: RFC 3986 query characters stay, except "&amp;" and "=";
    /// everything else as UTF-8 %XX (uppercase hex).</summary>
    static string EncodeQuery(string s)
    {
        var sb = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(s))
        {
            var c = (char)b;
            if (b < 0x80 && (char.IsAsciiLetterOrDigit(c) || "-._~!$'()*+,;:@/?".Contains(c))) sb.Append(c);
            else sb.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }

    /// <summary><c>path.split(separator: "/")</c> on the decoded path (empty pieces dropped).</summary>
    static List<string> SplitPath(string path) => path.Split('/', StringSplitOptions.RemoveEmptyEntries).ToList();

    static readonly Dictionary<string, LiveActionKind> LiveActionKinds =
        Enum.GetValues<LiveActionKind>().ToDictionary(k => SwiftJson.RawValue(k), k => k, StringComparer.Ordinal);

    public bool Equals(RemoteCommand? o) => o is not null && Kind == o.Kind && Text.Equal(Name, o.Name) && Equals(Action, o.Action);

    public override int GetHashCode() => HashCode.Combine(Kind, Action);
}

/// <summary>A URL split the way Foundation's <c>URLComponents</c> splits it (RFC 3986): scheme as written, host and path
/// percent-decoded, query items with "+" kept.</summary>
internal sealed record UrlParts(string Scheme, string? Host, string Path, List<(string Name, string? Value)> QueryItems)
{
    static readonly Regex SchemePattern = new("^[A-Za-z][A-Za-z0-9+.-]*:", RegexOptions.CultureInvariant);

    /// <summary>Null when the text is not an absolute URL (no scheme, or a port that is not a number).</summary>
    public static UrlParts? Parse(string url)
    {
        var m = SchemePattern.Match(url);
        if (!m.Success) return null;
        var scheme = url[..(m.Length - 1)];
        var rest = url[m.Length..];
        var hash = rest.IndexOf('#');
        if (hash >= 0) rest = rest[..hash];
        string? query = null;
        var q = rest.IndexOf('?');
        if (q >= 0) { query = rest[(q + 1)..]; rest = rest[..q]; }
        string? host = null;
        if (rest.StartsWith("//", StringComparison.Ordinal))
        {
            var slash = rest.IndexOf('/', 2);
            var authority = slash < 0 ? rest[2..] : rest[2..slash];
            rest = slash < 0 ? "" : rest[slash..];
            var at = authority.LastIndexOf('@');
            if (at >= 0) authority = authority[(at + 1)..];
            string port;
            if (authority.StartsWith('['))
            {
                var close = authority.IndexOf(']');
                if (close < 0) return null;
                host = authority[1..close];
                port = authority[(close + 1)..];
                if (port.Length > 0 && port[0] != ':') return null;
                port = port.Length > 0 ? port[1..] : "";
            }
            else
            {
                var colon = authority.LastIndexOf(':');
                host = colon < 0 ? authority : authority[..colon];
                port = colon < 0 ? "" : authority[(colon + 1)..];
            }
            if (!port.All(char.IsAsciiDigit)) return null;
            host = Uri.UnescapeDataString(host);
        }
        var items = new List<(string, string?)>();
        if (query != null)
            foreach (var item in query.Split('&'))
            {
                var eq = item.IndexOf('=');
                items.Add(eq < 0
                    ? (Uri.UnescapeDataString(item), null)
                    : (Uri.UnescapeDataString(item[..eq]), Uri.UnescapeDataString(item[(eq + 1)..])));
            }
        return new UrlParts(scheme, host, Uri.UnescapeDataString(rest), items);
    }
}

/// <summary>Swift's number ↔ text conversions as the URL commands use them.</summary>
internal static class SwiftNumbers
{
    static readonly Regex Decimal = new(@"^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$", RegexOptions.CultureInvariant);
    static readonly Regex Hex = new(@"^([+-]?)0[xX]([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?(?:[pP]([+-]?[0-9]+))?$", RegexOptions.CultureInvariant);
    static readonly Regex Special = new(@"^([+-]?)(inf|infinity|nan)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary><c>Double(String)</c> (strtod, whole text): decimal, hexadecimal ("0x10", "0x1p3"), "inf"/"nan";
    /// no surrounding whitespace.</summary>
    public static double? ParseDouble(string s)
    {
        if (Decimal.IsMatch(s)) return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
        if (Special.Match(s) is { Success: true } sp)
        {
            var negative = sp.Groups[1].Value == "-";
            if (sp.Groups[2].Value.Equals("nan", StringComparison.OrdinalIgnoreCase)) return double.NaN;
            return negative ? double.NegativeInfinity : double.PositiveInfinity;
        }
        if (Hex.Match(s) is { Success: true } h && h.Groups[2].Length + h.Groups[3].Length > 0)
        {
            double mantissa = 0;
            foreach (var c in h.Groups[2].Value + h.Groups[3].Value) mantissa = mantissa * 16 + Convert.ToInt32(c.ToString(), 16);
            var exponent = (h.Groups[4].Success ? int.Parse(h.Groups[4].Value, CultureInfo.InvariantCulture) : 0) - 4 * h.Groups[3].Length;
            var value = mantissa * Math.Pow(2, exponent);
            return h.Groups[1].Value == "-" ? -value : value;
        }
        return null;
    }

    /// <summary><c>Int(String)</c>: optional sign and decimal digits only. Values outside Int32 (C# <c>LiveAction.Value2</c>)
    /// are treated as unreadable.</summary>
    public static int? ParseInt(string s) =>
        s.Length > 0 && s.Skip(s[0] is '+' or '-' ? 1 : 0).All(char.IsAsciiDigit) && s.Any(char.IsAsciiDigit) &&
        int.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var n) ? n : null;

    /// <summary><c>v.rounded() == v ? String(Int(v)) : String(v)</c>. Infinity (which traps in Swift) is written "inf".</summary>
    public static string LinkValue(double v)
    {
        if (double.IsNaN(v)) return "nan";
        if (double.IsInfinity(v)) return v > 0 ? "inf" : "-inf";
        if (Math.Round(v, MidpointRounding.AwayFromZero) == v && Math.Abs(v) < 9.2e18) return ((long)v).ToString(CultureInfo.InvariantCulture);
        return SwiftJson.FormatDouble(v);
    }
}

/// <summary>Finds what an "insert by name" means: a menu entry with that title (chains and actions included) first,
/// else the installed plugin, device or preset with that name.</summary>
public static class RemoteTarget
{
    public static PanelRow? Row(string name, LauncherConfig config, SearchIndex index)
    {
        var wanted = Text.Lower(name);
        foreach (var category in config.Categories)
            foreach (var e in category.Entries)
                foreach (var entry in e.IsFolder ? e.Children ?? new List<Entry>() : new List<Entry> { e })
                {
                    if (!Text.Equal(Text.Lower(entry.Title), wanted)) continue;
                    if (PanelRow.Special(entry, index, null) is { } special) return special;
                    if (index.Resolver.Resolve(entry) is { } resolved &&
                        index.GlobalRow(index.UsageKey.TryGetValue(resolved.Uri, out var key) ? key : "") is { } row)
                        return row;
                }
        return index.GlobalRows.FirstOrDefault(r => Text.Equal(Text.Lower(r.Title), wanted));
    }
}

public enum RemoteOutcomeKind { Run, Refused, BadRequest, Unknown }

/// <summary>One request to the local Stream Deck endpoint, checked before anything runs:
/// GET only, the install's token must match, and nothing a browser sends for a web page (Origin, Referer,
/// Sec-Fetch-Site) — so a site open in the user's browser can't fire commands at 127.0.0.1.</summary>
public static class RemoteRequest
{
    public sealed record Outcome(RemoteOutcomeKind Kind, RemoteCommand? Command = null)
    {
        public static Outcome Run(RemoteCommand command) => new(RemoteOutcomeKind.Run, command);
        public static readonly Outcome Refused = new(RemoteOutcomeKind.Refused);
        public static readonly Outcome BadRequest = new(RemoteOutcomeKind.BadRequest);
        public static readonly Outcome Unknown = new(RemoteOutcomeKind.Unknown);
    }

    static readonly string[] BrowserHeaders = { "origin", "referer", "sec-fetch-site", "sec-fetch-mode" };

    /// <summary>The request line and headers have arrived.</summary>
    public static bool IsComplete(string raw) => raw.Contains("\r\n\r\n", StringComparison.Ordinal);

    public static Outcome Handle(string raw, string token)
    {
        var lines = raw.Split("\r\n");
        var parts = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || parts[0] != "GET") return Outcome.BadRequest;
        var url = $"http://127.0.0.1:{RemoteCommand.HttpPort}" + parts[1];
        if (!Uri.TryCreate(url, UriKind.Absolute, out _) || UrlParts.Parse(url) is not { } parsed) return Outcome.BadRequest;
        var headers = lines.Skip(1).Select(line => line.IndexOf(':')).Zip(lines.Skip(1))
            .Where(p => p.First >= 0).Select(p => Text.Lower(p.Second[..p.First]));
        if (headers.Any(h => BrowserHeaders.Contains(h))) return Outcome.Refused;
        var sent = parsed.QueryItems.FirstOrDefault(i => i.Name == "token").Value;
        if (sent == null || token.Length == 0 || !Text.Equal(sent, token)) return Outcome.Refused;
        return RemoteCommand.TryParse(url) is { } command ? Outcome.Run(command) : Outcome.Unknown;
    }
}

public sealed partial record LauncherConfig
{
    /// <summary>Swift's <c>LauncherConfig.newToken()</c>: 20 lowercase hex characters (the Stream Deck link secret).</summary>
    public static string NewToken() => Guid.NewGuid().ToString("N")[..20];
}
