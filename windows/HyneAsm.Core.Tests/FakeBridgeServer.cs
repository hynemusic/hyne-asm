using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace HyneAsm.Core.Tests;

/// <summary>Local TCP server speaking the bridge's line protocol (Tests/HMLauncherCoreTests/FakeBridgeServer.swift).
/// <see cref="Respond"/> gets the parsed request and returns the reply object (or null to stay silent).</summary>
public sealed class FakeBridgeServer : IDisposable
{
    public ushort Port { get; private set; }
    public Func<JsonObject, JsonObject?> Respond { get; set; } = _ => null;
    /// <summary>When set, replaces <see cref="Respond"/>: the exact text to send back (newlines included), or null.</summary>
    public Func<JsonObject, string?>? RespondLine { get; set; }
    public int? ChunkSize { get; set; }
    public bool ReverseOrder { get; set; }
    public TimeSpan ReplyDelay { get; set; } = TimeSpan.Zero;

    readonly object gate = new();
    TcpListener? listener;
    readonly List<TcpClient> connections = new();
    readonly List<(TcpClient, byte[])> held = new();

    public void Start(ushort port = 0)
    {
        var l = new TcpListener(IPAddress.Loopback, port);
        l.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        l.Start();
        Port = (ushort)((IPEndPoint)l.LocalEndpoint).Port;
        listener = l;
        _ = Accept(l);
    }

    public void Stop()
    {
        lock (gate)
        {
            listener?.Stop();
            listener = null;
            foreach (var c in connections) c.Close();
            connections.Clear();
        }
    }

    public void Dispose() => Stop();

    async Task Accept(TcpListener l)
    {
        while (true)
        {
            TcpClient c;
            try { c = await l.AcceptTcpClientAsync(); }
            catch (Exception e) when (e is SocketException or ObjectDisposedException or InvalidOperationException) { return; }
            lock (gate)
            {
                if (listener != l) { c.Close(); return; }
                connections.Add(c);
            }
            _ = Read(c);
        }
    }

    async Task Read(TcpClient c)
    {
        var buffer = new List<byte>();
        var chunk = new byte[65536];
        try
        {
            var stream = c.GetStream();
            while (true)
            {
                var n = await stream.ReadAsync(chunk);
                if (n == 0) return;
                buffer.AddRange(chunk.AsSpan(0, n).ToArray());
                int nl;
                while ((nl = buffer.IndexOf(0x0A)) >= 0)
                {
                    var line = buffer.GetRange(0, nl).ToArray();
                    buffer.RemoveRange(0, nl + 1);
                    JsonObject? req;
                    try { req = JsonNode.Parse(line) as JsonObject; } catch (JsonException) { continue; }
                    if (req == null) continue;
                    if (RespondLine is { } respondLine)
                    {
                        if (respondLine(req) is { } text) Send(c, Encoding.UTF8.GetBytes(text));
                        continue;
                    }
                    if (Respond(req) is not { } reply) continue;
                    var data = Encoding.UTF8.GetBytes(reply.ToJsonString() + "\n");
                    if (ReverseOrder)
                    {
                        lock (gate)
                        {
                            held.Add((c, data));
                            if (held.Count < 2) continue;
                            foreach (var (conn, bytes) in Enumerable.Reverse(held)) Send(conn, bytes);
                            held.Clear();
                        }
                    }
                    else if (ReplyDelay > TimeSpan.Zero)
                    {
                        _ = Task.Delay(ReplyDelay).ContinueWith(_ => Send(c, data), TaskScheduler.Default);
                    }
                    else Send(c, data);
                }
            }
        }
        catch (Exception e) when (e is IOException or SocketException or ObjectDisposedException or InvalidOperationException) { }
    }

    void Send(TcpClient c, byte[] data)
    {
        try
        {
            var stream = c.GetStream();
            lock (c)
            {
                var size = ChunkSize ?? data.Length;
                for (var offset = 0; offset < data.Length; offset += size)
                {
                    stream.Write(data, offset, Math.Min(size, data.Length - offset));
                    stream.Flush();
                }
            }
        }
        catch (Exception e) when (e is IOException or SocketException or ObjectDisposedException or InvalidOperationException) { }
    }

    /// <summary>A success reply to <paramref name="req"/>.</summary>
    public static JsonObject Ok(JsonObject req, JsonNode? result = null) =>
        new() { ["id"] = req["id"]?.DeepClone(), ["ok"] = true, ["result"] = result, ["error"] = null };

    public static async Task<bool> WaitUntil(Func<bool> condition, double timeout = 3)
    {
        var end = DateTime.UtcNow.AddSeconds(timeout);
        while (DateTime.UtcNow < end)
        {
            if (condition()) return true;
            await Task.Delay(20);
        }
        return condition();
    }
}
