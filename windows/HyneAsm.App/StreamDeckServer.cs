using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using HyneAsm.Core;

namespace HyneAsm.App;

/// <summary>Local HTTP endpoint for Stream Deck's "Website" action (with "Access in background").
/// Listens on 127.0.0.1 only — nothing outside this PC can reach it — and only while switched on.</summary>
sealed class StreamDeckServer
{
    TcpListener? listener;
    CancellationTokenSource? stop;

    public string Token { get; set; } = "";
    public string? Error { get; private set; }
    public bool IsListening => listener != null;
    /// <summary>Called on a thread-pool thread; the app marshals to the UI.</summary>
    public Action<RemoteCommand>? OnCommand;

    public void SetEnabled(bool enabled)
    {
        if (enabled) Start(); else Stop();
    }

    void Start()
    {
        if (listener != null) return;
        try
        {
            listener = new TcpListener(IPAddress.Loopback, RemoteCommand.HttpPort);
            listener.Start();
            Error = null;
            stop = new CancellationTokenSource();
            _ = Accept(listener, stop.Token);
        }
        catch (Exception e) { Error = e.Message; listener = null; }
    }

    void Stop()
    {
        stop?.Cancel();
        listener?.Stop();
        listener = null;
    }

    async Task Accept(TcpListener l, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await l.AcceptTcpClientAsync(token); }
            catch (Exception) { return; }
            _ = Serve(client);
        }
    }

    /// <summary>Reads the request (line + headers, max 8 KB, 2 s), checks it, runs it, answers and closes.</summary>
    async Task Serve(TcpClient client)
    {
        using (client)
        {
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                var stream = client.GetStream();
                var buffer = new byte[8192];
                var length = 0;
                while (length < buffer.Length)
                {
                    var n = await stream.ReadAsync(buffer.AsMemory(length), timeout.Token);
                    if (n == 0) break;
                    length += n;
                    if (RemoteRequest.IsComplete(Encoding.UTF8.GetString(buffer, 0, length))) break;
                }
                var outcome = RemoteRequest.Handle(Encoding.UTF8.GetString(buffer, 0, length), Token);
                var (status, body) = outcome.Kind switch
                {
                    RemoteOutcomeKind.Run => ("200 OK", "ok"),
                    RemoteOutcomeKind.Refused => ("403 Forbidden", "forbidden"),
                    RemoteOutcomeKind.Unknown => ("404 Not Found", "unknown command"),
                    _ => ("400 Bad Request", "bad request"),
                };
                if (outcome.Kind == RemoteOutcomeKind.Run && outcome.Command != null) OnCommand?.Invoke(outcome.Command);
                var bytes = Encoding.UTF8.GetBytes(
                    $"HTTP/1.1 {status}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {Encoding.UTF8.GetByteCount(body)}\r\nConnection: close\r\n\r\n{body}");
                await stream.WriteAsync(bytes, timeout.Token);
            }
            catch (Exception) { /* client gone or too slow */ }
        }
    }
}
