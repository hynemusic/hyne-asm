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
