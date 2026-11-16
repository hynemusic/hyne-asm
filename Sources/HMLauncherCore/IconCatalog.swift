public struct IconDef: Hashable, Sendable {
    public let id: String
    public let label: String
    public let symbolName: String
}

/// v1 uses SF Symbols; custom line icons can later reuse the same ids.
public enum IconCatalog {
    public static let defaultID = "generic"

    public static let all: [IconDef] = [
        IconDef(id: "generic", label: "Plugin", symbolName: "puzzlepiece.extension"),
        IconDef(id: "eq", label: "EQ", symbolName: "slider.vertical.3"),
        IconDef(id: "compressor", label: "Compressor", symbolName: "arrow.down.right.and.arrow.up.left"),
        IconDef(id: "limiter", label: "Limiter", symbolName: "arrow.down.to.line"),
        IconDef(id: "reverb", label: "Reverb", symbolName: "dot.radiowaves.left.and.right"),
        IconDef(id: "delay", label: "Delay", symbolName: "repeat"),
        IconDef(id: "synth", label: "Synth", symbolName: "waveform"),
        IconDef(id: "sampler", label: "Sampler", symbolName: "waveform.path"),
        IconDef(id: "drums", label: "Drums", symbolName: "circle.grid.3x3"),
        IconDef(id: "utility", label: "Utility", symbolName: "dial.medium"),
        IconDef(id: "saturation", label: "Saturation", symbolName: "flame"),
        IconDef(id: "filter", label: "Filter", symbolName: "line.diagonal"),
        IconDef(id: "modulation", label: "Modulation", symbolName: "waveform.path.ecg"),
        IconDef(id: "meter", label: "Meter", symbolName: "chart.bar"),
        IconDef(id: "pitch", label: "Pitch", symbolName: "tuningfork"),
        IconDef(id: "vocal", label: "Vocal", symbolName: "music.mic"),
    ]

    public static func symbolName(for id: String) -> String {
        all.first { $0.id == id }?.symbolName ?? all[0].symbolName
    }
}
