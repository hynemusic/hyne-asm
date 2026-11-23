using System.Globalization;
using System.Reflection;
using System.Runtime.Serialization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HyneAsm.Core.Json;

/// <summary>
/// JSON exactly as Swift's <c>JSONEncoder</c>/<c>JSONDecoder</c> write and read it: camelCase keys (the Swift
/// property names), nil optionals omitted, UUIDs as uppercase strings, enums as their Swift raw values, numbers as
/// Swift prints them, "/" escaped as "\/". Pretty output matches <c>[.prettyPrinted, .sortedKeys]</c> byte for byte.
/// </summary>
public static class SwiftJson
{
    /// <summary>Options for everything written to or read from Mac files.</summary>
    public static readonly JsonSerializerOptions Options = Create(withConfigConverter: true);

    /// <summary>Same as <see cref="Options"/> without the <see cref="LauncherConfig"/> reader (used to write it).</summary>
    internal static readonly JsonSerializerOptions PlainOptions = Create(withConfigConverter: false);

    static JsonSerializerOptions Create(bool withConfigConverter)
    {
        var o = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };
        o.Converters.Add(new UuidConverter());
        o.Converters.Add(new DoubleConverter());
        o.Converters.Add(new SwiftEnumConverterFactory());
        if (withConfigConverter) o.Converters.Add(new LauncherConfig.Reader());
        return o;
    }

    /// <summary>Swift <c>JSONEncoder</c> output; <paramref name="pretty"/> = <c>[.prettyPrinted, .sortedKeys]</c>.</summary>
    public static string Serialize(object? value, bool pretty = false)
    {
        var compact = JsonSerializer.Serialize(value, value?.GetType() ?? typeof(object), Options);
        using var doc = JsonDocument.Parse(compact);
        var sb = new StringBuilder(compact.Length * 2);
        Write(sb, doc.RootElement, pretty, 0);
        return sb.ToString();
    }

    /// <summary>Swift <c>JSONDecoder</c> reading: a leading UTF-8 BOM is skipped, as Swift does.</summary>
    public static T Deserialize<T>(string json) =>
        JsonSerializer.Deserialize<T>(json.StartsWith('﻿') ? json[1..] : json, Options)
        ?? throw new JsonException("JSON is null");

    /// <summary>A deep copy through the file format — what assigning a Swift value type gives. The one copy helper for
    /// configs, categories and entries, so no nested list or record (actions, chain items) stays shared.</summary>
    public static T Clone<T>(T value) => Deserialize<T>(Serialize(value));

    /// <summary>The Swift raw value of an enum case (<c>ItemSource.AudioEffects</c> → "audio_effects").</summary>
    public static string RawValue<T>(T value) where T : struct, Enum => SwiftEnumConverter<T>.ToRaw[value];

    // MARK: Writing

    static void Write(StringBuilder sb, JsonElement e, bool pretty, int indent)
    {
        switch (e.ValueKind)
        {
            case JsonValueKind.Object:
                var props = e.EnumerateObject().Select(p => (p.Name, p.Value)).ToList();
                if (pretty) props.Sort((a, b) => Utf8Compare(a.Name, b.Name));
                WriteContainer(sb, '{', '}', props.Count, pretty, indent, i =>
                {
                    Quote(sb, props[i].Name);
                    sb.Append(pretty ? " : " : ":");
                    Write(sb, props[i].Value, pretty, indent + 2);
                });
                break;
            case JsonValueKind.Array:
                var items = e.EnumerateArray().ToList();
                WriteContainer(sb, '[', ']', items.Count, pretty, indent, i => Write(sb, items[i], pretty, indent + 2));
                break;
            case JsonValueKind.String: Quote(sb, e.GetString()!); break;
            default: sb.Append(e.GetRawText()); break;   // numbers (already in Swift form), true, false, null
        }
    }

    /// <summary>Swift pretty form: one element per line, 2-space indent; an empty container is "[\n\n&lt;indent&gt;]".</summary>
    static void WriteContainer(StringBuilder sb, char open, char close, int count, bool pretty, int indent, Action<int> element)
    {
        sb.Append(open);
        if (!pretty)
        {
            for (var i = 0; i < count; i++) { if (i > 0) sb.Append(','); element(i); }
        }
        else
        {
            sb.Append('\n');
            for (var i = 0; i < count; i++)
            {
                if (i > 0) sb.Append(",\n");
                sb.Append(' ', indent + 2);
                element(i);
            }
            sb.Append('\n').Append(' ', indent);
        }
        sb.Append(close);
    }

    /// <summary>Swift's escaping: quote, backslash, slash, \b \f \n \r \t, other controls as \u00xx; the rest raw.</summary>
    static void Quote(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (var c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '/': sb.Append("\\/"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }

    /// <summary>Order of <c>.sortedKeys</c>: by the UTF-8 bytes of the key (= code point order), no normalization.</summary>
    internal static int Utf8Compare(string a, string b)
    {
        var ea = a.EnumerateRunes();
        var eb = b.EnumerateRunes();
        while (true)
        {
            var hasA = ea.MoveNext();
            var hasB = eb.MoveNext();
            if (!hasA || !hasB) return hasA.CompareTo(hasB);
            var d = ea.Current.Value.CompareTo(eb.Current.Value);
            if (d != 0) return d;
        }
    }

    /// <summary>Swift's Double text: integral values below 2^53 without a fraction (120, -0), else the shortest
    /// round-trip form with a lowercase exponent (0.5, 1e-05, 1e+16).</summary>
    internal static string FormatDouble(double d)
    {
        if (double.IsNaN(d) || double.IsInfinity(d)) throw new JsonException("Swift cannot encode " + d);
        if (d == Math.Floor(d) && Math.Abs(d) < 9007199254740992.0)
            return d == 0 && double.IsNegative(d) ? "-0" : ((long)d).ToString(CultureInfo.InvariantCulture);
        return d.ToString("R", CultureInfo.InvariantCulture).Replace('E', 'e');
    }

    // MARK: Decoding helpers with Swift's semantics (used by hand-written readers such as LauncherConfig's)

    /// <summary><c>decode(_:forKey:)</c>: missing key or null → error.</summary>
    internal static T Required<T>(JsonElement obj, string key, JsonSerializerOptions o)
    {
        if (!obj.TryGetProperty(key, out var v)) throw new JsonException($"missing key \"{key}\"");
        if (v.ValueKind == JsonValueKind.Null) throw new JsonException($"null for key \"{key}\"");
        return v.Deserialize<T>(o) is { } r ? r : throw new JsonException($"null for key \"{key}\"");
    }

    /// <summary><c>decodeIfPresent(_:forKey:) ?? fallback</c>: missing or null → fallback, a wrong value → error.</summary>
    internal static T IfPresent<T>(JsonElement obj, string key, JsonSerializerOptions o, Func<T> fallback)
    {
        if (!obj.TryGetProperty(key, out var v) || v.ValueKind == JsonValueKind.Null) return fallback();
        return v.Deserialize<T>(o) is { } r ? r : fallback();
    }

    /// <summary><c>(try? decodeIfPresent(_:forKey:)) ?? fallback</c>: anything unreadable → fallback.</summary>
    internal static T Lenient<T>(JsonElement obj, string key, JsonSerializerOptions o, Func<T> fallback)
    {
        try { return IfPresent(obj, key, o, fallback); }
        catch (JsonException) { return fallback(); }
    }

    /// <summary>Swift rejects null for a non-optional value; .NET 8 does not (it ignores nullable annotations).
    /// Called after decoding (<c>IJsonOnDeserialized</c>) so damaged files fail like they do in Swift.</summary>
    internal static void RejectNull(string type, params object?[] values)
    {
        if (values.Any(v => v is null)) throw new JsonException($"{type}: null for a non-optional value");
    }

    /// <summary>Same for the elements of non-optional lists (<c>[Category]</c> cannot hold null in Swift).</summary>
    internal static void RejectNullElements(string type, params IEnumerable<object?>?[] lists)
    {
        if (lists.Any(l => l != null && l.Any(x => x is null))) throw new JsonException($"{type}: null element in a list");
    }

    // MARK: Dates (.iso8601) and Mac text files

    /// <summary>Swift <c>.iso8601</c> encoding: whole seconds (the fraction is dropped), UTC, "Z".</summary>
    internal static string FormatIso8601(DateTime date) =>
        AsUtc(date).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", CultureInfo.InvariantCulture);

    /// <summary>The one rule for a <see cref="DateTime"/> of unknown kind: Local is converted, Unspecified counts as UTC
    /// (Swift's <c>Date</c> has no kind, and every date the core makes or reads is UTC).</summary>
    internal static DateTime AsUtc(DateTime date) => date.Kind switch
    {
        DateTimeKind.Local => date.ToUniversalTime(),
        DateTimeKind.Unspecified => DateTime.SpecifyKind(date, DateTimeKind.Utc),
        _ => date,
    };

    static readonly System.Text.RegularExpressions.Regex IsoPattern = new(
        @"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(Z|[+-][0-9]{2}:?[0-9]{2})$",
        System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    /// <summary>Swift <c>.iso8601</c> decoding: "T" and a zone ("Z", "+01:00", "+0100") required, a fraction accepted.
    /// ASCII digits only ("٢٠٢٦" is no year). Any malformed date gives false, never an exception.</summary>
    internal static bool TryParseIso8601(string s, out DateTime utc)
    {
        utc = default;
        var m = IsoPattern.Match(s);
        if (!m.Success) return false;
        int G(int i) => int.Parse(m.Groups[i].Value, CultureInfo.InvariantCulture);
        try
        {
            var local = new DateTime(G(1), G(2), G(3), G(4), G(5), G(6), DateTimeKind.Utc);
            if (m.Groups[7].Success)
            {
                var digits = (m.Groups[7].Value + "0000000")[..7];
                local = local.AddTicks(long.Parse(digits, CultureInfo.InvariantCulture));
            }
            var zone = m.Groups[8].Value;
            if (zone != "Z")
            {
                var z = zone.Replace(":", "");
                var minutes = int.Parse(z[1..3], CultureInfo.InvariantCulture) * 60 + int.Parse(z[3..5], CultureInfo.InvariantCulture);
                local = local.AddMinutes(z[0] == '+' ? -minutes : minutes);
            }
            utc = local;
            return true;
        }
        catch (Exception e) when (e is ArgumentOutOfRangeException or FormatException or OverflowException) { return false; }
    }

    /// <summary>A <c>Date</c> property written with Swift's <c>.iso8601</c> strategy.</summary>
    internal sealed class Iso8601Converter : JsonConverter<DateTime>
    {
        public override DateTime Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
        {
            if (reader.TokenType != JsonTokenType.String || !TryParseIso8601(reader.GetString()!, out var d))
                throw new JsonException("not an ISO-8601 date");
            return d;
        }

        public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions o) =>
            writer.WriteStringValue(FormatIso8601(value));
    }

    static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>UTF-8 file bytes as text; invalid UTF-8 throws (as <c>JSONDecoder</c> rejects it). A BOM is kept.</summary>
    internal static string DecodeUtf8(byte[] data) => StrictUtf8.GetString(data);

    /// <summary>Text as file bytes: UTF-8 without a BOM.</summary>
    internal static byte[] EncodeUtf8(string text) => StrictUtf8.GetBytes(text);

    /// <summary>Swift <c>[String: Int]</c> decoding: an object of integral numbers (1.0 counts, 1.5 does not).
    /// Keys are compared canonically; a repeated key keeps the last value. A leading BOM is skipped.</summary>
    internal static Dictionary<string, int> ReadCounts(string json)
    {
        using var doc = JsonDocument.Parse(json.StartsWith('﻿') ? json[1..] : json);
        return ReadCounts(doc.RootElement);
    }

    internal static Dictionary<string, int> ReadCounts(JsonElement e)
    {
        if (e.ValueKind != JsonValueKind.Object) throw new JsonException("counts must be an object");
        var result = new Dictionary<string, int>(Text.Canonical);
        foreach (var p in e.EnumerateObject()) result[p.Name] = ReadInt(p.Value);
        return result;
    }

    /// <summary>Swift <c>Int</c> decoding of a JSON number: integral values only (also written as 9.0).</summary>
    internal static int ReadInt(JsonElement v)
    {
        if (v.ValueKind != JsonValueKind.Number) throw new JsonException("not a number");
        if (v.TryGetInt32(out var i)) return i;
        if (v.TryGetDouble(out var d) && d == Math.Floor(d) && d >= int.MinValue && d <= int.MaxValue) return (int)d;
        throw new JsonException("not an Int");
    }

    // MARK: Converters

    sealed class UuidConverter : JsonConverter<Guid>
    {
        public override Guid Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
        {
            if (reader.TokenType != JsonTokenType.String) throw new JsonException("UUID must be a string");
            return Guid.TryParseExact(reader.GetString(), "D", out var g) ? g : throw new JsonException("invalid UUID");
        }

        public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions o) =>
            writer.WriteStringValue(value.ToString("D").ToUpperInvariant());
    }

    sealed class DoubleConverter : JsonConverter<double>
    {
        public override double Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
        {
            if (reader.TokenType != JsonTokenType.Number || !reader.TryGetDouble(out var d) || double.IsInfinity(d))
                throw new JsonException("not a Double");
            return d;
        }

        public override void Write(Utf8JsonWriter writer, double value, JsonSerializerOptions o) =>
            writer.WriteRawValue(FormatDouble(value), skipInputValidation: true);
    }

    /// <summary>String enums by Swift raw value: <c>[EnumMember(Value = ...)]</c>, else the camelCase case name.
    /// <c>[Flags]</c> enums (option sets such as <see cref="ModifierSet"/>) stay numbers.</summary>
    sealed class SwiftEnumConverterFactory : JsonConverterFactory
    {
        public override bool CanConvert(Type t) => t.IsEnum && !t.IsDefined(typeof(FlagsAttribute), false);

        public override JsonConverter CreateConverter(Type t, JsonSerializerOptions o) =>
            (JsonConverter)Activator.CreateInstance(typeof(SwiftEnumConverter<>).MakeGenericType(t))!;
    }

    sealed class SwiftEnumConverter<T> : JsonConverter<T> where T : struct, Enum
    {
        internal static readonly Dictionary<T, string> ToRaw = typeof(T).GetFields(BindingFlags.Public | BindingFlags.Static)
            .ToDictionary(f => (T)f.GetValue(null)!,
                f => f.GetCustomAttribute<EnumMemberAttribute>()?.Value ?? char.ToLowerInvariant(f.Name[0]) + f.Name[1..]);

        static readonly Dictionary<string, T> FromRaw = ToRaw.ToDictionary(p => p.Value, p => p.Key, StringComparer.Ordinal);

        public override T Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
        {
            if (reader.TokenType != JsonTokenType.String) throw new JsonException($"{typeof(T).Name} must be a string");
            var raw = reader.GetString()!;
            return FromRaw.TryGetValue(raw, out var v) ? v : throw new JsonException($"unknown {typeof(T).Name} \"{raw}\"");
        }

        public override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions o) => writer.WriteStringValue(ToRaw[value]);
    }
}
