using System.Globalization;
using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace HyneAsm.Core;

/// <summary>Where inserted items land, and on which tracks (Behavior settings).</summary>
public enum InsertPosition
{
    End,
    [EnumMember(Value = "after_selected")] AfterSelected,
}

public sealed record InsertOptions
{
    [JsonRequired] public InsertPosition Position { get; set; } = InsertPosition.End;
    /// <summary>With several tracks selected in Live, each of them gets the item.</summary>
    [JsonRequired] public bool AllSelectedTracks { get; set; } = true;

    public InsertOptions() { }

    public InsertOptions(InsertPosition position = InsertPosition.End, bool allSelectedTracks = true)
    {
        Position = position;
        AllSelectedTracks = allSelectedTracks;
    }

    /// <summary>A fresh copy of the defaults on every call.</summary>
    public static InsertOptions Default => new();
}

/// <summary>What the Live script in use can do (older scripts or Live versions lack some calls).
/// Sent as <c>move_device</c> / <c>multi_select</c>; the client converts snake_case keys.</summary>
public sealed record BridgeCapabilities
{
    [JsonRequired] public bool MoveDevice { get; set; }
    [JsonRequired] public bool MultiSelect { get; set; }

    public BridgeCapabilities() { }

    public BridgeCapabilities(bool moveDevice, bool multiSelect) { MoveDevice = moveDevice; MultiSelect = multiSelect; }
}

/// <summary>A Live command offered alongside plugins ("New MIDI Track", "Tempo 128" …).</summary>
public enum LiveActionKind
{
    [EnumMember(Value = "new_midi_track")] NewMidiTrack,
    [EnumMember(Value = "new_audio_track")] NewAudioTrack,
    [EnumMember(Value = "new_return_track")] NewReturnTrack,
    [EnumMember(Value = "new_scene")] NewScene,
    [EnumMember(Value = "duplicate_track")] DuplicateTrack,
    [EnumMember(Value = "set_tempo")] SetTempo,
    [EnumMember(Value = "tap_tempo")] TapTempo,
    [EnumMember(Value = "set_time_signature")] SetTimeSignature,
    [EnumMember(Value = "toggle_metronome")] ToggleMetronome,
    [EnumMember(Value = "toggle_loop")] ToggleLoop,
    [EnumMember(Value = "toggle_arrangement_record")] ToggleArrangementRecord,
    [EnumMember(Value = "toggle_session_record")] ToggleSessionRecord,
    [EnumMember(Value = "capture_midi")] CaptureMidi,
    [EnumMember(Value = "stop_all_clips")] StopAllClips,
    Undo,
    Redo,
}

public static class LiveActionKindExtensions
{
    /// <summary>Actions that need a value before they become an entry (several entries with different values can exist).</summary>
    public static bool TakesValue(this LiveActionKind kind) => kind is LiveActionKind.SetTempo or LiveActionKind.SetTimeSignature;

    public static double? DefaultValue(this LiveActionKind kind) => kind switch
    {
        LiveActionKind.SetTempo => 120,
        LiveActionKind.SetTimeSignature => 4,
        _ => null,
    };

    public static int? DefaultValue2(this LiveActionKind kind) => kind == LiveActionKind.SetTimeSignature ? 4 : null;

    public static string Title(this LiveActionKind kind) => kind switch
    {
        LiveActionKind.NewMidiTrack => Loc.T("Neue MIDI-Spur", "New MIDI Track"),
        LiveActionKind.NewAudioTrack => Loc.T("Neue Audiospur", "New Audio Track"),
        LiveActionKind.NewReturnTrack => Loc.T("Neue Return-Spur", "New Return Track"),
        LiveActionKind.NewScene => Loc.T("Neue Szene", "New Scene"),
        LiveActionKind.DuplicateTrack => Loc.T("Spur duplizieren", "Duplicate Track"),
        LiveActionKind.SetTempo => Loc.T("Tempo", "Tempo"),
        LiveActionKind.TapTempo => Loc.T("Tap Tempo", "Tap Tempo"),
        LiveActionKind.SetTimeSignature => Loc.T("Taktart", "Time Signature"),
        LiveActionKind.ToggleMetronome => Loc.T("Metronom an/aus", "Metronome On/Off"),
        LiveActionKind.ToggleLoop => Loc.T("Loop an/aus", "Loop On/Off"),
        LiveActionKind.ToggleArrangementRecord => Loc.T("Arrangement-Aufnahme", "Arrangement Record"),
        LiveActionKind.ToggleSessionRecord => Loc.T("Session-Aufnahme", "Session Record"),
        LiveActionKind.CaptureMidi => Loc.T("MIDI einfangen", "Capture MIDI"),
        LiveActionKind.StopAllClips => Loc.T("Alle Clips stoppen", "Stop All Clips"),
        LiveActionKind.Undo => Loc.T("Widerrufen", "Undo"),
        LiveActionKind.Redo => Loc.T("Wiederholen", "Redo"),
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    public static string IconID(this LiveActionKind kind) => kind switch
    {
        LiveActionKind.NewMidiTrack => "midi",
        LiveActionKind.NewAudioTrack => "sampler",
        LiveActionKind.NewReturnTrack => "space",
        LiveActionKind.NewScene or LiveActionKind.DuplicateTrack => "rack",
        LiveActionKind.SetTempo or LiveActionKind.TapTempo => "meter",
        LiveActionKind.SetTimeSignature => "chord",
        LiveActionKind.ToggleMetronome => "tuner",
        LiveActionKind.ToggleLoop => "delay",
        LiveActionKind.ToggleArrangementRecord or LiveActionKind.ToggleSessionRecord or LiveActionKind.CaptureMidi => "sparkles",
        LiveActionKind.StopAllClips => "gate",
        LiveActionKind.Undo or LiveActionKind.Redo => "utility",
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };
}

public sealed record LiveAction
{
    [JsonRequired] public LiveActionKind Kind { get; set; }
    public double? Value { get; set; }
    public int? Value2 { get; set; }

    /// <summary>For the JSON reader: missing values stay null (Swift's synthesized decoding adds no defaults).</summary>
    public LiveAction() { }

    public LiveAction(LiveActionKind kind, double? value = null, int? value2 = null)
    {
        Kind = kind;
        Value = value ?? kind.DefaultValue();
        Value2 = value2 ?? kind.DefaultValue2();
    }

    /// <summary>"Tempo 128", "Time Signature 7/8", "New MIDI Track".</summary>
    [JsonIgnore]
    public string Title => Kind switch
    {
        LiveActionKind.SetTempo => $"{Kind.Title()} {Format(Value ?? 120)}",
        LiveActionKind.SetTimeSignature => $"{Kind.Title()} {(long)(Value ?? 4)}/{Value2 ?? 4}",
        _ => Kind.Title(),
    };

    static string Format(double v) =>
        Math.Round(v, MidpointRounding.AwayFromZero) == v
            ? ((long)v).ToString(CultureInfo.InvariantCulture)
            : v.ToString("F1", CultureInfo.InvariantCulture);
}
