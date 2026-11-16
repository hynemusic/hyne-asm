public struct IconDef: Hashable, Sendable {
    public let id: String
    public let label: String
    public let symbolName: String
}

/// SF Symbols available on macOS 13. Ids are stored in the config — never rename an existing id.
public enum IconCatalog {
    public static let defaultID = "generic"

    public static let all: [IconDef] = [
        IconDef(id: "generic", label: "Plugin", symbolName: "puzzlepiece.extension"),
        // Dynamics & EQ
        IconDef(id: "eq", label: "EQ", symbolName: "slider.vertical.3"),
        IconDef(id: "eq-curve", label: "EQ-Kurve", symbolName: "point.topleft.down.curvedto.point.bottomright.up"),
        IconDef(id: "filter", label: "Filter", symbolName: "line.diagonal"),
        IconDef(id: "compressor", label: "Kompressor", symbolName: "arrow.down.right.and.arrow.up.left"),
        IconDef(id: "glue", label: "Bus-Comp", symbolName: "rectangle.compress.vertical"),
        IconDef(id: "limiter", label: "Limiter", symbolName: "arrow.down.to.line"),
        IconDef(id: "gate", label: "Gate", symbolName: "door.left.hand.closed"),
        IconDef(id: "deesser", label: "De-Esser", symbolName: "mouth"),
        IconDef(id: "transient", label: "Transient", symbolName: "bolt"),
        // Space & time
        IconDef(id: "reverb", label: "Reverb", symbolName: "dot.radiowaves.left.and.right"),
        IconDef(id: "delay", label: "Delay", symbolName: "repeat"),
        IconDef(id: "echo", label: "Echo", symbolName: "wave.3.right"),
        IconDef(id: "stereo", label: "Stereo", symbolName: "arrow.left.and.right"),
        IconDef(id: "space", label: "Raum", symbolName: "cube.transparent"),
        // Color
        IconDef(id: "saturation", label: "Sättigung", symbolName: "flame"),
        IconDef(id: "distortion", label: "Distortion", symbolName: "waveform.badge.exclamationmark"),
        IconDef(id: "bitcrush", label: "Bitcrush", symbolName: "square.grid.3x3"),
        IconDef(id: "tape", label: "Tape", symbolName: "recordingtape"),
        IconDef(id: "console", label: "Konsole", symbolName: "dial.high"),
        IconDef(id: "texture", label: "Textur", symbolName: "circle.hexagongrid"),
        // Modulation & pitch
        IconDef(id: "modulation", label: "Modulation", symbolName: "waveform.path.ecg"),
        IconDef(id: "chorus", label: "Chorus", symbolName: "water.waves"),
        IconDef(id: "phaser", label: "Phaser", symbolName: "circle.lefthalf.filled"),
        IconDef(id: "pitch", label: "Pitch", symbolName: "tuningfork"),
        IconDef(id: "vocal", label: "Vocal", symbolName: "music.mic"),
        // Instruments
        IconDef(id: "synth", label: "Synth", symbolName: "waveform"),
        IconDef(id: "sine", label: "Sinus", symbolName: "alternatingcurrent"),
        IconDef(id: "keys", label: "Keys", symbolName: "pianokeys"),
        IconDef(id: "sampler", label: "Sampler", symbolName: "waveform.path"),
        IconDef(id: "drums", label: "Drums", symbolName: "circle.grid.3x3"),
        IconDef(id: "bass", label: "Bass", symbolName: "speaker.wave.3"),
        IconDef(id: "strings", label: "Strings", symbolName: "music.quarternote.3"),
        IconDef(id: "pad", label: "Pad", symbolName: "cloud"),
        // Tools
        IconDef(id: "utility", label: "Utility", symbolName: "dial.medium"),
        IconDef(id: "meter", label: "Meter", symbolName: "chart.bar"),
        IconDef(id: "analyzer", label: "Analyzer", symbolName: "waveform.badge.magnifyingglass"),
        IconDef(id: "tuner", label: "Tuner", symbolName: "gauge.medium"),
        IconDef(id: "midi", label: "MIDI", symbolName: "pianokeys.inverse"),
        IconDef(id: "arp", label: "Arp", symbolName: "arrow.up.right"),
        IconDef(id: "chord", label: "Chord", symbolName: "music.note.list"),
        IconDef(id: "rack", label: "Rack", symbolName: "square.stack.3d.up"),
        IconDef(id: "star", label: "Favorit", symbolName: "star"),
        IconDef(id: "heart", label: "Herz", symbolName: "heart"),
        IconDef(id: "sparkles", label: "Magic", symbolName: "sparkles"),
    ]

    public static func symbolName(for id: String) -> String {
        all.first { $0.id == id }?.symbolName ?? all[0].symbolName
    }
}
