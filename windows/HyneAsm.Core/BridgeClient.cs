using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Nodes;
using HyneAsm.Core.Json;

namespace HyneAsm.Core;

/// <summary>The bridge's answer to "hello".</summary>
public sealed record HelloResult(string ScriptVersion, string LiveVersion, BridgeCapabilities Capabilities)
{
    /// <summary>Swift's <c>init(from:)</c>: both versions required; capabilities missing (scripts before version 4) or null
    /// → nothing beyond the basics.</summary>
    internal static HelloResult Decode(JsonElement e)
    {
        if (e.ValueKind != JsonValueKind.Object) throw new JsonException("hello: result is not an object");
        var caps = e.TryGetProperty("capabilities", out var c) && c.ValueKind != JsonValueKind.Null
            ? SwiftJson.Deserialize<BridgeCapabilities>(c.GetRawText())
            : new BridgeCapabilities(moveDevice: false, multiSelect: false);
        return new HelloResult(BridgeProtocol.RequiredString(e, "scriptVersion"), BridgeProtocol.RequiredString(e, "liveVersion"), caps);
    }
}

public enum BridgeErrorKind { NotConnected, Timeout, Remote }

/// <summary>Swift's <c>BridgeError</c>. A reply the client cannot read throws <see cref="JsonException"/> instead
/// (Swift: <c>DecodingError</c>).</summary>
public sealed class BridgeError : Exception
{
    public BridgeErrorKind Kind { get; }
    /// <summary>The bridge's error text, for <see cref="BridgeErrorKind.Remote"/>.</summary>
    public string? Remote { get; }

    BridgeError(BridgeErrorKind kind, string? remote) : base(kind == BridgeErrorKind.Remote ? "bridge: " + remote : "bridge: " + kind)
    {
        Kind = kind;
        Remote = remote;
    }

    public static BridgeError NotConnected() => new(BridgeErrorKind.NotConnected, null);
    public static BridgeError Timeout() => new(BridgeErrorKind.Timeout, null);
    public static BridgeError FromRemote(string message) => new(BridgeErrorKind.Remote, message);
}

/// <summary>TCP client for the ASMbridge remote script (newline-delimited JSON on 127.0.0.1:47820).
/// Reconnects automatically while started. Replies are matched to requests by id.
/// <para>Threading: every member may be called from any thread. The connection handler and the continuations of the
/// returned tasks run on thread-pool threads, never on a UI thread; the UI (Plan 2) marshals to its dispatcher.</para></summary>
public sealed class BridgeClient : IDisposable
{
    public static readonly TimeSpan DefaultRequestTimeout = TimeSpan.FromSeconds(3);
    /// <summary>load replies only after Live finished loading (heavy M4L/instruments take seconds).</summary>
    public static readonly TimeSpan DefaultLoadTimeout = TimeSpan.FromSeconds(30);
    /// <summary>The plugin list: Live walks its whole browser first, which takes many seconds with big libraries.</summary>
    public static readonly TimeSpan DefaultListTimeout = TimeSpan.FromSeconds(90);
    public static readonly TimeSpan DefaultReconnectInterval = TimeSpan.FromSeconds(2);

    public string Host { get; }
    public ushort Port { get; }
    public TimeSpan RequestTimeout { get; }
    public TimeSpan LoadTimeout { get; }
    public TimeSpan ListTimeout { get; }
    public TimeSpan ReconnectInterval { get; }

    readonly object gate = new();
    readonly object notifyGate = new();
    Connection? connection;
    bool started;
    bool isConnected;
    int nextID = 1;
    readonly Dictionary<long, TaskCompletionSource<byte[]>> pending = new();
    Action<bool>? handler;

    public BridgeClient(string host = "127.0.0.1", ushort port = 47820, TimeSpan? requestTimeout = null, TimeSpan? loadTimeout = null,
                        TimeSpan? reconnectInterval = null, TimeSpan? listTimeout = null)
    {
        Host = host;
        Port = port;
        RequestTimeout = requestTimeout ?? DefaultRequestTimeout;
        LoadTimeout = loadTimeout ?? DefaultLoadTimeout;
        ListTimeout = listTimeout ?? DefaultListTimeout;
        ReconnectInterval = reconnectInterval ?? DefaultReconnectInterval;
    }

    public bool IsConnected { get { lock (gate) return isConnected; } }

    /// <summary>Called with true/false whenever the connection comes up or goes down (on a thread-pool thread).</summary>
    public void SetConnectionHandler(Action<bool> h) { lock (gate) handler = h; }

    public void Start()
    {
        lock (gate)
        {
            if (started) return;
            started = true;
        }
        Connect();
    }

    public void Stop()
    {
        lock (gate) started = false;
        Teardown(null);
    }

    public void Dispose() => Stop();

    public async Task<HelloResult> Hello() =>
        BridgeProtocol.Decode(await Request(w => w.WriteString("cmd", "hello")).ConfigureAwait(false), HelloResult.Decode);

    /// <summary><paramref name="refresh"/>: make Live walk its browser again (blocks Live ~1 s, longer with big libraries).
    /// Otherwise the bridge answers from its last walk; the first list after Live starts always walks.
    /// Items this app can't read (e.g. a source a newer bridge adds) are skipped.</summary>
    public async Task<List<PluginItem>> ListItems(bool refresh = false)
    {
        var line = await Request(w => { w.WriteString("cmd", "list"); w.WriteBoolean("refresh", refresh); }, ListTimeout).ConfigureAwait(false);
        return BridgeProtocol.Decode(line, BridgeProtocol.Items);
    }

    /// <summary>One item or a chain, loaded in order where the options say.</summary>
    public async Task Load(IReadOnlyList<string> uris, InsertOptions options)
    {
        var line = await Request(w =>
        {
            w.WriteString("cmd", "load");
            w.WriteStartArray("uris");
            foreach (var u in uris) w.WriteStringValue(u);
            w.WriteEndArray();
            w.WriteString("position", SwiftJson.RawValue(options.Position));
            w.WriteBoolean("all_selected", options.AllSelectedTracks);
            // Scripts before version 4 only read "uri": they still load the (first) item.
            if (uris.Count > 0) w.WriteString("uri", uris[0]);
        }, LoadTimeout * Math.Max(uris.Count, 1)).ConfigureAwait(false);
        BridgeProtocol.DecodeEmpty(line);
    }

    public async Task Run(LiveAction action)
    {
        var line = await Request(w =>
        {
            w.WriteString("cmd", "action");
            w.WriteString("name", SwiftJson.RawValue(action.Kind));
            if (action.Value is { } v) { w.WritePropertyName("value"); w.WriteRawValue(SwiftJson.FormatDouble(v)); }
            if (action.Value2 is { } v2) w.WriteNumber("value2", v2);
        }).ConfigureAwait(false);
        BridgeProtocol.DecodeEmpty(line);
    }

    public async Task Load(string uri)
    {
        var line = await Request(w => { w.WriteString("cmd", "load"); w.WriteString("uri", uri); }, LoadTimeout).ConfigureAwait(false);
        BridgeProtocol.DecodeEmpty(line);
    }

    // MARK: Requests

    async Task<byte[]> Request(Action<Utf8JsonWriter> body, TimeSpan? timeout = null)
    {
        Connection conn;
        int id;
        lock (gate)
        {
            if (!isConnected || connection?.Stream == null) throw BridgeError.NotConnected();
            conn = connection;
            id = nextID++;
        }
        var data = BridgeProtocol.Message(body, id);
        var reply = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate)
        {
            if (connection != conn) throw BridgeError.NotConnected();
            pending[id] = reply;
        }
        using var timer = new CancellationTokenSource(timeout ?? RequestTimeout);
        using var registration = timer.Token.Register(() => Fail(id, BridgeError.Timeout()));
        _ = conn.Send(data);
        return await reply.Task.ConfigureAwait(false);
    }

    void Fail(long id, BridgeError error)
    {
        TaskCompletionSource<byte[]>? waiting;
        lock (gate)
        {
            if (!pending.Remove(id, out waiting)) return;
        }
        waiting.TrySetException(error);
    }

    // MARK: Connection

    sealed class Connection : IDisposable
    {
        public readonly TcpClient Client = new();
        public readonly CancellationTokenSource Cancel = new();
        readonly SemaphoreSlim writing = new(1, 1);
        public NetworkStream? Stream;

        public async Task Send(byte[] data)
        {
            try
            {
                await writing.WaitAsync(Cancel.Token).ConfigureAwait(false);
                try { await Stream!.WriteAsync(data, Cancel.Token).ConfigureAwait(false); }
                finally { writing.Release(); }
            }
            catch (Exception e) when (e is IOException or SocketException or OperationCanceledException or ObjectDisposedException) { }
        }

        public void Dispose()
        {
            try { Cancel.Cancel(); } catch (ObjectDisposedException) { }
            Client.Dispose();
        }
    }

    void Connect()
    {
        Connection conn;
        lock (gate)
        {
            if (!started || connection != null) return;
            conn = new Connection();
            connection = conn;
        }
        _ = RunConnection(conn);
    }

    async Task RunConnection(Connection conn)
    {
        try
        {
            await conn.Client.ConnectAsync(Host, Port, conn.Cancel.Token).ConfigureAwait(false);
            lock (gate)
            {
                if (connection != conn) return;
                conn.Stream = conn.Client.GetStream();
            }
            SetConnected(true, conn);
            var buffer = new List<byte>();
            var chunk = new byte[65536];
            while (true)
            {
                var n = await conn.Stream.ReadAsync(chunk, conn.Cancel.Token).ConfigureAwait(false);
                if (n == 0) break;
                buffer.AddRange(chunk.AsSpan(0, n).ToArray());
                int nl;
                while ((nl = buffer.IndexOf(0x0A)) >= 0)
                {
                    var line = buffer.GetRange(0, nl).ToArray();
                    buffer.RemoveRange(0, nl + 1);
                    if (BridgeProtocol.ReplyID(line) is not { } id) continue;
                    TaskCompletionSource<byte[]>? waiting;
                    lock (gate)
                    {
                        if (connection != conn || !pending.Remove(id, out waiting)) continue;
                    }
                    waiting.TrySetResult(line);
                }
            }
        }
        catch (Exception e) when (e is IOException or SocketException or OperationCanceledException or ObjectDisposedException) { }
        finally { conn.Dispose(); }
        if (Teardown(conn)) ScheduleReconnect();
    }

    /// <summary>Drops <paramref name="only"/> (or whatever connection there is, for null) and fails the waiting requests.
    /// False when that connection was already gone.</summary>
    bool Teardown(Connection? only)
    {
        Connection? conn;
        List<TaskCompletionSource<byte[]>> waiting;
        lock (gate)
        {
            if (only != null && connection != only) return false;
            conn = connection;
            connection = null;
            waiting = pending.Values.ToList();
            pending.Clear();
        }
        conn?.Dispose();
        foreach (var w in waiting) w.TrySetException(BridgeError.NotConnected());
        SetConnected(false, null);
        return true;
    }

    void ScheduleReconnect()
    {
        lock (gate) if (!started) return;
        _ = Task.Delay(ReconnectInterval).ContinueWith(_ => Connect(), TaskScheduler.Default);
    }

    /// <summary>Handler calls happen one at a time and in order. <paramref name="conn"/>: only while it is still current.</summary>
    void SetConnected(bool value, Connection? conn)
    {
        lock (notifyGate)
        {
            Action<bool>? h;
            lock (gate)
            {
                if (conn != null && connection != conn) return;
                if (value == isConnected) return;
                isConnected = value;
                h = handler;
            }
            h?.Invoke(value);
        }
    }
}

/// <summary>The bridge's line protocol as Swift's <c>BridgeClient</c> reads and writes it (bridge/ASMbridge/protocol.py).</summary>
internal static class BridgeProtocol
{
    /// <summary>One request line: the body's fields plus "id", then "\n".</summary>
    public static byte[] Message(Action<Utf8JsonWriter> body, int id)
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms))
        {
            w.WriteStartObject();
            body(w);
            w.WriteNumber("id", id);
            w.WriteEndObject();
        }
        ms.WriteByte(0x0A);
        return ms.ToArray();
    }

    /// <summary>The "id" of a reply line (Swift <c>IDOnly</c>: a JSON object whose "id" is an integer, or nothing).</summary>
    public static long? ReplyID(byte[] line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            if (doc.RootElement.ValueKind != JsonValueKind.Object || !doc.RootElement.TryGetProperty("id", out var id) ||
                id.ValueKind != JsonValueKind.Number) return null;
            if (id.TryGetInt64(out var n)) return n;
            var d = id.GetDouble();
            return d == Math.Floor(d) && Math.Abs(d) < 9.2e18 ? (long)d : null;
        }
        catch (JsonException) { return null; }
    }

    /// <summary>Swift <c>decode(_:_:resultOptional:)</c> with <c>.convertFromSnakeCase</c>: the whole envelope is read first
    /// (a result that can't be read fails even when ok is false), then ok / error, then a missing result.</summary>
    public static T Decode<T>(byte[] line, Func<JsonElement, T> result) => Decode(line, result, optional: false)!;

    /// <summary>For replies without a result (<c>Empty</c> in Swift, which reads from any JSON value).</summary>
    public static void DecodeEmpty(byte[] line) => Decode(line, _ => true, optional: true);

    static T? Decode<T>(byte[] line, Func<JsonElement, T> result, bool optional)
    {
        T? value = default;
        bool hasValue, ok;
        string? error;
        try
        {
            var node = ConvertKeys(JsonNode.Parse(line));
            using var doc = JsonDocument.Parse(node?.ToJsonString() ?? "null");
            var env = doc.RootElement;
            if (env.ValueKind != JsonValueKind.Object) throw new JsonException("reply is not an object");
            if (!env.TryGetProperty("ok", out var okValue) || okValue.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new JsonException("reply: ok must be a Bool");
            ok = okValue.GetBoolean();
            error = OptionalString(env, "error");
            hasValue = env.TryGetProperty("result", out var r) && r.ValueKind != JsonValueKind.Null;
            if (hasValue) value = result(r);
        }
        catch (Exception e) when (e is not JsonException and not BridgeError)
        {
            throw new JsonException("reply: " + e.Message, e);
        }
        if (!ok) throw BridgeError.FromRemote(error ?? "unknown");
        if (hasValue || optional) return value;
        throw BridgeError.FromRemote("missing_result");
    }

    /// <summary>Lossy: an item the app can't decode (e.g. a source a newer bridge adds) is skipped instead of failing the list.</summary>
    public static List<PluginItem> Items(JsonElement result)
    {
        if (result.ValueKind != JsonValueKind.Object || !result.TryGetProperty("items", out var items) ||
            items.ValueKind != JsonValueKind.Array) throw new JsonException("list: items must be a list");
        var list = new List<PluginItem>();
        foreach (var e in items.EnumerateArray())
        {
            try { list.Add(SwiftJson.Deserialize<PluginItem>(e.GetRawText())); }
            catch (JsonException) { }
        }
        return list;
    }

    public static string RequiredString(JsonElement obj, string key)
    {
        if (!obj.TryGetProperty(key, out var v) || v.ValueKind != JsonValueKind.String) throw new JsonException($"missing string \"{key}\"");
        return v.GetString()!;
    }

    static string? OptionalString(JsonElement obj, string key)
    {
        if (!obj.TryGetProperty(key, out var v) || v.ValueKind == JsonValueKind.Null) return null;
        return v.ValueKind == JsonValueKind.String ? v.GetString() : throw new JsonException($"\"{key}\" must be a string");
    }

    /// <summary>Applies <see cref="FromSnakeCase"/> to every object key (Swift converts the keys of every keyed container).</summary>
    static JsonNode? ConvertKeys(JsonNode? node)
    {
        switch (node)
        {
            case JsonObject o:
                var converted = new JsonObject();
                foreach (var (key, value) in o.ToList())
                {
                    o.Remove(key);
                    converted.Add(FromSnakeCase(key), ConvertKeys(value));
                }
                return converted;
            case JsonArray a:
                var items = a.ToList();
                a.Clear();
                return new JsonArray(items.Select(ConvertKeys).ToArray());
            default:
                return node;
        }
    }

    /// <summary>Swift's <c>JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase</c>: "script_version" → "scriptVersion";
    /// leading/trailing underscores kept; a key without inner underscores unchanged; otherwise the first word lowercased
    /// and each further word capitalized ("multi_SELECT" → "multiSelect").</summary>
    internal static string FromSnakeCase(string key)
    {
        var first = 0;
        while (first < key.Length && key[first] == '_') first++;
        if (first == key.Length) return key;
        var last = key.Length - 1;
        while (last > first && key[last] == '_') last--;
        var core = key[first..(last + 1)];
        var words = core.Split('_', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 1) return key;
        var joined = Text.Lower(words[0]) + string.Concat(words.Skip(1).Select(Capitalized));
        return key[..first] + joined + key[(last + 1)..];
    }

    /// <summary>Foundation's <c>capitalized</c> for one word: first character uppercased, the rest lowercased.</summary>
    static string Capitalized(string word)
    {
        var firstChar = Text.Characters(word).First();
        return Text.UpperCharacter(firstChar) + Text.Lower(word[firstChar.Length..]);
    }
}
