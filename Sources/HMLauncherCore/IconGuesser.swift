import Foundation

/// Picks an icon from a plugin's name. First matching rule wins, so specific rules come first
/// (limiter before compressor, de-esser before compressor …). Not perfect — it only saves clicks.
public enum IconGuesser {
    /// Keywords are matched case-insensitively. Keywords of ≤ 3 characters must be a whole word
    /// ("eq" matches "EQ Eight", not "Sequencer"); longer ones may appear anywhere ("verb" in "VintageVerb").
    private static let rules: [(icon: String, keywords: [String])] = [
        ("drums", ["kick", "snare", "808", "909", "drum", "hat", "clap", "percussion", "battery", "addictive drums", "superior drummer", "impact"]),
        ("deesser", ["de-ess", "deess", "esser", "pro-ds", "sibilan"]),
        ("limiter", ["limit", "pro-l", "l1", "l2", "l3", "maximizer", "maxim", "clipper", "kclip", "standard clip"]),
        ("gate", ["gate", "pro-g", "expander"]),
        ("transient", ["transient", "smack", "punch", "trans-x"]),
        ("compressor", ["compress", "comp", "glue", "pro-c", "pro-mb", "1176", "76", "la-2a", "la2a", "ott", "dynamics",
                        "multiband", "vca", "opto", "fet", "cl 1b", "distressor", "squash", "rvox"]),
        ("eq", ["eq", "pro-q", "equaliz", "pultec", "eqp", "channel eq", "api 5", "neve 1073"]),
        ("filter", ["filter", "volcano", "lowpass", "highpass", "autofilter", "wah"]),
        ("reverb", ["verb", "reverb", "room", "plate", "hall", "valhalla", "pro-r", "space", "chamber", "spring", "supermassive", "shimmer", "convolution"]),
        ("delay", ["delay", "echoboy", "timeless", "primaltap", "h-delay", "tape echo", "repeat"]),
        ("echo", ["echo"]),
        ("chorus", ["chorus", "ensemble", "dimension", "juno"]),
        ("phaser", ["phaser", "flanger", "phase"]),
        ("modulation", ["tremolo", "vibrato", "lfo", "shaperbox", "rotary", "modulat", "auto pan", "autopan", "ring mod"]),
        ("stereo", ["imager", "stereo", "width", "wider", "haas", "spread", "mono"]),
        ("tape", ["tape", "vinyl", "lo-fi", "lofi", "rc-20", "wow", "flutter"]),
        ("bitcrush", ["crush", "redux", "decimat", "bit", "erosion"]),
        ("distortion", ["distort", "fuzz", "overdrive", "pedal", "amp", "roar", "trash", "devil-loc", "guitar rig"]),
        ("saturation", ["satur", "decapitator", "saturn", "tube", "warmth", "drive", "heat", "drum buss", "radiator", "kramer"]),
        ("console", ["ssl", "neve", "console", "channel strip", "bus", "neutron", "api"]),
        ("pitch", ["tune", "pitch", "melodyne", "shifter", "harmoniz", "little alterboy", "crystallizer", "octave"]),
        ("vocal", ["vocal", "vox", "voice", "vocoder", "nectar", "choir"]),
        ("analyzer", ["spectrum", "analy", "span", "insight", "scope"]),
        ("meter", ["meter", "loudness", "lufs", "vu"]),
        ("tuner", ["tuner"]),
        ("utility", ["utility", "gain", "trim", "phase invert", "tool"]),
        ("arp", ["arp", "arpeggiat"]),
        ("chord", ["chord", "scaler", "harmony"]),
        ("keys", ["piano", "keys", "keyscape", "rhodes", "wurli", "electric", "grand", "organ", "b3", "noire", "una corda"]),
        ("strings", ["string", "violin", "cello", "orchestra", "tension", "collision", "harp", "guitar", "bass guitar"]),
        ("bass", ["bass", "sub", "trilian", "monobass"]),
        ("pad", ["pad", "atmos", "ambient", "texture", "granul", "portal", "grain"]),
        ("sampler", ["sampler", "simpler", "kontakt", "sample", "battery", "decent", "spitfire", "labs", "phrase"]),
        ("synth", ["synth", "serum", "vital", "massive", "diva", "omnisphere", "sylenth", "spire", "pigments", "phase plant",
                   "hive", "repro", "zebra", "analog", "wavetable", "operator", "drift", "meld", "nexus", "avenger",
                   "minimoog", "prophet", "jup", "obx", "dx7", "osc", "polysynth", "ana", "sylenth1", "dune", "icarus", "thorn"]),
    ]

    static var ruleIconIDs: [String] { rules.map(\.icon) }

    public static func guess(_ item: PluginItem) -> String {
        let name = item.name.lowercased()
        let words = Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        for rule in rules where rule.keywords.contains(where: { matches($0, name: name, words: words) }) {
            return rule.icon
        }
        switch item.source {
        case .instruments: return "synth"
        case .midiEffects: return "midi"
        default: return IconCatalog.defaultID
        }
    }

    private static func matches(_ keyword: String, name: String, words: Set<String>) -> Bool {
        if keyword.count <= 3, !keyword.contains(" "), !keyword.contains("-") { return words.contains(keyword) }
        return name.contains(keyword)
    }
}
