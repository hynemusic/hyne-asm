import Foundation

/// Where inserted items land, and on which tracks (Behavior settings).
public enum InsertPosition: String, Codable, CaseIterable, Sendable {
    case end
    case afterSelected = "after_selected"
}

public struct InsertOptions: Codable, Equatable, Sendable {
    public var position: InsertPosition
    /// With several tracks selected in Live, each of them gets the item.
    public var allSelectedTracks: Bool

    public init(position: InsertPosition = .end, allSelectedTracks: Bool = true) {
        self.position = position
        self.allSelectedTracks = allSelectedTracks
    }

    public static let `default` = InsertOptions()
}

/// What the Live script in use can do (older scripts or Live versions lack some calls).
/// Sent as `move_device` / `multi_select`; the client converts snake_case keys.
public struct BridgeCapabilities: Codable, Equatable, Sendable {
    public var moveDevice: Bool
    public var multiSelect: Bool

    public init(moveDevice: Bool, multiSelect: Bool) { self.moveDevice = moveDevice; self.multiSelect = multiSelect }
}

/// A Live command offered alongside plugins ("New MIDI Track", "Tempo 128" …).
public enum LiveActionKind: String, Codable, CaseIterable, Sendable {
    case newMidiTrack = "new_midi_track"
    case newAudioTrack = "new_audio_track"
    case newReturnTrack = "new_return_track"
    case newScene = "new_scene"
    case duplicateTrack = "duplicate_track"
    case setTempo = "set_tempo"
    case tapTempo = "tap_tempo"
    case setTimeSignature = "set_time_signature"
    case toggleMetronome = "toggle_metronome"
    case toggleLoop = "toggle_loop"
    case toggleArrangementRecord = "toggle_arrangement_record"
    case toggleSessionRecord = "toggle_session_record"
    case captureMidi = "capture_midi"
    case stopAllClips = "stop_all_clips"
    case undo, redo

    /// Actions that need a value before they become an entry (several entries with different values can exist).
    public var takesValue: Bool { self == .setTempo || self == .setTimeSignature }

    public var defaultValue: Double? {
        switch self {
        case .setTempo: return 120
        case .setTimeSignature: return 4
        default: return nil
        }
    }

    public var defaultValue2: Int? { self == .setTimeSignature ? 4 : nil }

    public var title: String {
        switch self {
        case .newMidiTrack: return Loc.t("Neue MIDI-Spur", "New MIDI Track")
        case .newAudioTrack: return Loc.t("Neue Audiospur", "New Audio Track")
        case .newReturnTrack: return Loc.t("Neue Return-Spur", "New Return Track")
        case .newScene: return Loc.t("Neue Szene", "New Scene")
        case .duplicateTrack: return Loc.t("Spur duplizieren", "Duplicate Track")
        case .setTempo: return Loc.t("Tempo", "Tempo")
        case .tapTempo: return Loc.t("Tap Tempo", "Tap Tempo")
        case .setTimeSignature: return Loc.t("Taktart", "Time Signature")
        case .toggleMetronome: return Loc.t("Metronom an/aus", "Metronome On/Off")
        case .toggleLoop: return Loc.t("Loop an/aus", "Loop On/Off")
        case .toggleArrangementRecord: return Loc.t("Arrangement-Aufnahme", "Arrangement Record")
        case .toggleSessionRecord: return Loc.t("Session-Aufnahme", "Session Record")
        case .captureMidi: return Loc.t("MIDI einfangen", "Capture MIDI")
        case .stopAllClips: return Loc.t("Alle Clips stoppen", "Stop All Clips")
        case .undo: return Loc.t("Widerrufen", "Undo")
        case .redo: return Loc.t("Wiederholen", "Redo")
        }
    }

    public var iconID: String {
        switch self {
        case .newMidiTrack: return "midi"
        case .newAudioTrack: return "sampler"
        case .newReturnTrack: return "space"
        case .newScene, .duplicateTrack: return "rack"
        case .setTempo, .tapTempo: return "meter"
        case .setTimeSignature: return "chord"
        case .toggleMetronome: return "tuner"
        case .toggleLoop: return "delay"
        case .toggleArrangementRecord, .toggleSessionRecord, .captureMidi: return "sparkles"
        case .stopAllClips: return "gate"
        case .undo, .redo: return "utility"
        }
    }
}

public struct LiveAction: Codable, Hashable, Sendable {
    public var kind: LiveActionKind
    public var value: Double?
    public var value2: Int?

    public init(kind: LiveActionKind, value: Double? = nil, value2: Int? = nil) {
        self.kind = kind
        self.value = value ?? kind.defaultValue
        self.value2 = value2 ?? kind.defaultValue2
    }

    /// "Tempo 128", "Time Signature 7/8", "New MIDI Track".
    public var title: String {
        switch kind {
        case .setTempo: return "\(kind.title) \(Self.format(value ?? 120))"
        case .setTimeSignature: return "\(kind.title) \(Int(value ?? 4))/\(value2 ?? 4)"
        default: return kind.title
        }
    }

    private static func format(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}
