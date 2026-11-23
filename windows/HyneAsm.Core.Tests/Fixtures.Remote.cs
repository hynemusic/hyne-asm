using System.Text.Json;
using System.Text.Json.Nodes;
using HyneAsm.Core.Json;

namespace HyneAsm.Core.Tests;

/// <summary>Fixture handlers for remote commands, the bridge protocol, the window guards and onboarding — the same input
/// shapes as Tests/HMLauncherCoreTests/SharedFixtureRemote.swift. Numbers that may be fractional go out in Swift's form.</summary>
public static partial class Fixtures
{
    static JsonNode? SwiftNode(object value) => JsonNode.Parse(SwiftJson.Serialize(value));

    // MARK: Remote commands

    static JsonNode? CommandJSON(RemoteCommand? c) => c?.Kind switch
    {
        null => null,
        RemoteCommandKind.Insert => new JsonObject { ["insert"] = c.Name },
        RemoteCommandKind.Action => new JsonObject { ["action"] = SwiftNode(c.Action!) },
        RemoteCommandKind.QuickSearch => "quickSearch",
        RemoteCommandKind.Panel => "panel",
        RemoteCommandKind.Profile => new JsonObject { ["profile"] = c.Name },
        RemoteCommandKind.NextProfile => "nextProfile",
        RemoteCommandKind.ClosePluginWindows => "closePluginWindows",
        _ => throw new InvalidOperationException(),
    };

    static RemoteCommand Command(JsonNode? n)
    {
        if (n is JsonValue v)
            return Str(v) switch
            {
                "quickSearch" => RemoteCommand.QuickSearch,
                "panel" => RemoteCommand.Panel,
                "nextProfile" => RemoteCommand.NextProfile,
                "closePluginWindows" => RemoteCommand.ClosePluginWindows,
                var s => throw new InvalidOperationException("unknown command " + s),
            };
        if (n?["insert"] is { } i) return RemoteCommand.Insert(Str(i));
        if (n?["profile"] is { } p) return RemoteCommand.Profile(Str(p));
        if (n?["action"] is { } a) return RemoteCommand.OfAction(Decode<LiveAction>(a));
        throw new InvalidOperationException("unknown command " + n?.ToJsonString());
    }

    static JsonNode? RemoteParse(JsonNode? input) =>
        Uri.TryCreate(Str(input), UriKind.Absolute, out var url) ? CommandJSON(RemoteCommand.TryParse(url)) : "invalid url";

    static JsonNode? RemoteLink(JsonNode? input)
    {
        var token = IsNull(input!["token"]) ? null : Str(input["token"]);
        var link = Command(input["command"]).Link(input["http"]!.GetValue<bool>(), token);
        return new JsonObject { ["link"] = link.OriginalString, ["parsed"] = CommandJSON(RemoteCommand.TryParse(link)) };
    }

    static JsonNode? RemoteRequestOp(JsonNode? input)
    {
        var raw = Str(input!["raw"]);
        var outcome = RemoteRequest.Handle(raw, Str(input["token"]));
        JsonNode? o = outcome.Kind switch
        {
            RemoteOutcomeKind.Run => new JsonObject { ["run"] = CommandJSON(outcome.Command) },
            RemoteOutcomeKind.Refused => "refused",
            RemoteOutcomeKind.BadRequest => "badRequest",
            _ => "unknown",
        };
        return new JsonObject { ["complete"] = RemoteRequest.IsComplete(raw), ["outcome"] = o };
    }

    // MARK: Bridge protocol

    /// <summary><c>{call, args, reply}</c> → <c>{request, result}</c> or <c>{request, error}</c> against a local fake bridge
    /// (timeouts 0.5 s; the defaults are asserted in BridgeClientTests).</summary>
    static JsonNode? BridgeProtocolOp(JsonNode? input) => BridgeProtocolAsync(input!).GetAwaiter().GetResult();

    static async Task<JsonNode?> BridgeProtocolAsync(JsonNode input)
    {
        using var server = new FakeBridgeServer();
        server.Start();
        JsonNode? seen = null;
        var reply = input["reply"];
        server.RespondLine = req =>
        {
            var sent = (JsonObject)req.DeepClone();
            sent.Remove("id");
            seen = sent;
            var id = req["id"]!.ToJsonString();
            switch (reply)
            {
                case null: return null;
                case JsonValue v when v.GetValueKind() == JsonValueKind.String: return Str(v).Replace("{id}", id);
                case JsonObject o:
                    var r = (JsonObject)o.DeepClone();
                    r.Remove("id");
                    var rest = r.ToJsonString()[1..];
                    return "{\"id\":" + id + (r.Count == 0 ? "" : ",") + rest + "\n";
                default: return null;
            }
        };
        var half = TimeSpan.FromSeconds(0.5);
        using var client = new BridgeClient(port: server.Port, requestTimeout: half, loadTimeout: half,
                                            reconnectInterval: TimeSpan.FromSeconds(0.3));
        client.Start();
        if (!await FakeBridgeServer.WaitUntil(() => client.IsConnected)) throw new InvalidOperationException("bridge: no connection");
        var args = input["args"] ?? new JsonObject();
        var output = new JsonObject();
        try
        {
            switch (Str(input["call"]))
            {
                case "hello":
                    var h = await client.Hello();
                    output["result"] = new JsonObject
                    {
                        ["scriptVersion"] = h.ScriptVersion, ["liveVersion"] = h.LiveVersion, ["capabilities"] = SwiftNode(h.Capabilities),
                    };
                    break;
                case "list":
                    output["result"] = SwiftNode(await client.ListItems(args["refresh"]?.GetValue<bool>() ?? false));
                    break;
                case "load":
                    await client.Load(StrList(args["uris"]), Decode<InsertOptions>(args["options"]));
                    output["result"] = "done";
                    break;
                case "load_uri":
                    await client.Load(Str(args["uri"]));
                    output["result"] = "done";
                    break;
                case "run":
                    await client.Run(Decode<LiveAction>(args["action"]));
                    output["result"] = "done";
                    break;
                default: throw new InvalidOperationException("bridge: unknown call");
            }
        }
        catch (BridgeError e)
        {
            output["error"] = e.Kind switch
            {
                BridgeErrorKind.NotConnected => "notConnected",
                BridgeErrorKind.Timeout => "timeout",
                _ => "remote: " + e.Remote,
            };
        }
        catch (JsonException)
        {
            output["error"] = "decoding";
        }
        client.Stop();
        output["request"] = seen?.DeepClone();
        return output;
    }

    // MARK: Guards and onboarding

    static Rect RectOf(JsonNode? n)
    {
        var a = n!.AsArray().Select(x => x!.GetValue<double>()).ToArray();
        if (a.Length != 4) throw new InvalidOperationException("a rect is [x, y, width, height]");
        return new Rect(a[0], a[1], a[2], a[3]);
    }

    static JsonNode? RectJSON(Rect r) =>
        JsonNode.Parse("[" + string.Join(",", new[] { r.X, r.Y, r.Width, r.Height }.Select(SwiftJson.FormatDouble)) + "]");

    static JsonNode? GuardsMainWindow(JsonNode? input)
    {
        var screen = List(input!["screen"]).Select(w =>
            new MainWindowGuard.ScreenWindow(RectOf(w!["frame"]), Int(w["layer"]), Str(w["title"]))).ToList();
        var main = new JsonArray(MainWindowGuard.MainWindows(screen)
            .Select(w => (JsonNode?)new JsonObject { ["title"] = w.Title, ["frame"] = RectJSON(w.Frame) }).ToArray());
        var verdicts = new JsonArray(List(input["probes"]).Select(p => (JsonNode?)JsonValue.Create(MainWindowGuard.IsMain(
            IsNull(p!["frame"]) ? null : RectOf(p["frame"]), IsNull(p["title"]) ? null : Str(p["title"]),
            p["isAXMain"]!.GetValue<bool>(), screen))).ToArray());
        return new JsonObject { ["main"] = main, ["isMain"] = verdicts };
    }

    static JsonNode? GuardsTooltip(JsonNode? input)
    {
        var size = input!["size"]!.AsArray().Select(x => x!.GetValue<double>()).ToArray();
        return RectJSON(TooltipPlacement.Frame(new Size(size[0], size[1]), RectOf(input["below"]), RectOf(input["visible"])));
    }

    static readonly Dictionary<OnboardingStep, string> StepNames = new()
    {
        [OnboardingStep.Welcome] = "welcome", [OnboardingStep.Permission] = "permission", [OnboardingStep.Connect] = "connect",
        [OnboardingStep.Menu] = "menu", [OnboardingStep.TryIt] = "tryIt",
    };

    static JsonNode? OnboardingSteps(JsonNode? input)
    {
        if (input!["starter"] is { } starter)
        {
            var items = Decode<List<PluginItem>>(starter);
            var config = IsNull(input["config"]) ? LauncherConfig.MakeDefault() : Decode<LauncherConfig>(input["config"]);
            var added = config.AddStarterSet(items);
            var again = config.AddStarterSet(items);
            var categories = new JsonArray(config.Categories.Select(c => (JsonNode?)new JsonObject
            {
                ["name"] = c.Name, ["titles"] = Strings(c.Entries.Select(e => e.Title)), ["icons"] = Strings(c.Entries.Select(e => e.IconID)),
            }).ToArray());
            return new JsonObject { ["added"] = added, ["again"] = again, ["categories"] = categories };
        }
        var st = input["status"];
        bool Flag(string key) => st?[key]?.GetValue<bool>() ?? false;
        var s = new OnboardingStatus
        {
            Permission = Flag("permission"), ScriptInstalled = Flag("scriptInstalled"), Connected = Flag("connected"),
            PanelOpened = Flag("panelOpened"), MenuChosen = Flag("menuChosen"),
        };
        var steps = Enum.GetValues<OnboardingStep>();
        return new JsonObject
        {
            ["steps"] = Strings(steps.Select(x => StepNames[x])),
            ["done"] = Strings(steps.Where(s.IsDone).Select(x => StepNames[x])),
            ["showOnLaunch"] = Onboarding.ShowOnLaunch(input["configExisted"]!.GetValue<bool>(), input["done"]!.GetValue<bool>()),
        };
    }
}
