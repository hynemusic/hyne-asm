import Foundation

/// Picks an icon from a plugin's name. First matching rule wins, so specific rules come first
/// (limiter before compressor, de-esser before compressor …). Not perfect — it only saves clicks.
public enum IconGuesser {
    /// Keywords are matched case-insensitively. Keywords of ≤ 3 characters must be a whole word
    /// ("eq" matches "EQ Eight", not "Sequencer"); longer ones may appear anywhere ("verb" in "VintageVerb").
    private static let rules: [(icon: String, keywords: [String])] = [
        // Researched kinds first: they name what a plugin does more precisely than the generic words below.
        ("repair", ["rx", "de-click", "de-hum", "de-noise", "denoise", "de-crackle", "de-clip", "de-plosive", "declick", "dehum",
                    "breath control", "isolation", "dialogue isolate", "noise reduction"]),
        ("headphones", ["headphone", "abbey road studio", "realphones", "room sim"]),
        ("sparkles", ["exciter", "enhancer", "fresh air", "aphex"]),
        ("resonance", ["soothe", "gullfoss", "clarity", "spectral shaper", "smooth operator", "resonance", "refinement"]),
        ("stereo", ["imager"]),  // before "ozone": Ozone Imager is a stereo tool, not the mastering suite
        ("mastering", ["ozone", "masterdesk", "god particle", "alpha master", "mastering", "master rebalance"]),
        ("sidechain", ["sidechain", "side chain", "ducker", "duck", "kickstart", "volume shaper", "lfotool", "pump"]),
        ("granular", ["granul", "granello", "grain", "dark sky", "quanta"]),
        ("mic", ["mic", "mic collection", "mic mod", "preamp", "610", "v76", "townsend"]),
        ("tape", ["studer", "ampex", "atr-102", "cassette"]),
        ("amp", ["amp", "ampeg", "fender", "friedman", "engl", "diezel", "marshall", "suhr", "mesa", "gallien", "eden wt",
                 "fuchs", "svt", "b15n", "tweed", "rockrack", "gtr", "megadual", "megasingle", "amplitube", "archetype",
                 "guitar rig", "bias fx", "gav19"]),
        ("utility", ["metronome", "recorder", "notepad", "channel mixer", "channelmatrix", "splice bridge", "netsend",
                     "rogerbeep", "roundtrip", "magc"]),
        ("rack", ["reason rack", "effectrack", "effect rack"]),
        ("console", ["fx strip", "cs-1"]),
        ("drums", ["kick", "snare", "808", "909", "drum", "hat", "clap", "percussion", "battery", "addictive drums", "superior drummer", "impact"]),
        ("deesser", ["de-ess", "deess", "esser", "pro-ds", "sibilan"]),
        ("limiter", ["limit", "pro-l", "l1", "l2", "l3", "maximizer", "maxim", "clipper", "kclip", "standard clip", "clip", "elevate"]),
        ("gate", ["gate", "pro-g", "expander"]),
        ("transient", ["transient", "smack", "punch", "trans-x", "punctuate", "envolution"]),
        ("compressor", ["compress", "comp", "glue", "pro-c", "pro-mb", "1176", "76", "la-2a", "la2a", "ott", "dynamics",
                        "multiband", "vca", "opto", "fet", "cl 1b", "distressor", "squash", "rvox", "fairchild", "teletronix",
                        "la-2", "la-3a", "dbx", "variable mu", "vari-mu", "mpressor", "175-b", "176", "tla-100", "dyna-mite",
                        "vsc-2", "magnum", "c-max", "mratio", "axx"]),
        ("eq", ["eq", "req", "pro-q", "bx_digital", "bx_hybrid", "cambridge", "equivocate", "equaliz", "pultec", "eqp", "channel eq", "api 5", "neve 1073", "tilt", "maag", "nseq", "mdweq",
                "sieq", "sie-q", "graphiceq", "parametriceq"]),
        ("filter", ["filter", "resonator", "volcano", "lowpass", "highpass", "autofilter", "wah", "comb", "cleansweep", "bandpass", "hipass"]),
        ("reverb", ["verb", "reverb", "room", "plate", "hall", "valhalla", "pro-r", "space", "chamber", "spring", "supermassive", "shimmer", "convolution",
                    "emt", "lexicon", "bx 20", "rmx16", "ir-l", "reflection engine", "480l", "ocean way studios"]),
        ("delay", ["delay", "echoboy", "timeless", "primaltap", "h-delay", "tape echo", "repeat", "re-201", "space echo",
                   "time cube", "sdd-3000", "supertap", "dmx 15"]),
        ("echo", ["echo"]),
        ("chorus", ["chorus", "ensemble", "dimension", "juno", "ce-1"]),
        ("phaser", ["phaser", "flanger", "phase"]),
        ("modulation", ["tremol", "vibrato", "lfo", "shaperbox", "rotary", "modulat", "auto pan", "autopan", "ring mod", "mondomod", "enigma"]),
        ("stereo", ["imager", "stereo", "width", "wider", "haas", "spread", "mono", "doubler", "adt", "microshift", "widener",
                    "panman", "panner", "split", "doppler", "spectralpan"]),
        ("tape", ["tape", "vinyl", "lo-fi", "lofi", "rc-20", "wow", "flutter"]),
        ("bitcrush", ["crush", "redux", "decimat", "bit", "erosion", "bitfun"]),
        ("distortion", ["distort", "fuzz", "overdrive", "pedal", "roar", "trash", "devil-loc", "waveshaper", "wavefolder",
                        "screamer", "distorange", "bx_metal", "blackdist", "bermuda", "uad raw", "rift feedback"]),
        ("saturation", ["satur", "decapitator", "saturn", "tube", "warmth", "drive", "heat", "drum buss", "radiator", "kramer",
                        "inflator", "vulture", "vsm-3"]),
        ("console", ["redd", "ssl", "neve", "console", "channel strip", "bus", "neutron", "api", "harrison", "trident", "wunderlich",
                     "avalon", "helios", "a-range", "voxbox"]),
        ("pitch", ["tune", "pitch", "melodyne", "shifter", "harmoniz", "little alterboy", "crystallizer", "octave", "halftime", "half time"]),
        ("vocal", ["vocal", "vox", "voice", "vocoder", "nectar", "choir", "morphoder", "throat", "articulator", "avox", "formant"]),
        ("analyzer", ["spectrum", "analy", "span", "insight", "scope", "mixed in key", "metric"]),
        ("meter", ["meter", "loudness", "lufs", "vu"]),
        ("tuner", ["tuner", "auto-key"]),
        ("utility", ["utility", "gain", "trim", "phase invert", "tool"]),
        ("arp", ["arp", "arpeggiat"]),
        ("chord", ["chord", "scaler", "harmony"]),
        ("keys", ["roli", "dlsmusicdevice", "piano", "keys", "keyscape", "rhodes", "wurli", "electric", "grand", "organ", "b3", "noire", "una corda"]),
        ("strings", ["wood works", "string", "violin", "cello", "orchestra", "tension", "collision", "harp", "guitar", "bass guitar"]),
        ("bass", ["bass", "sub", "trilian", "monobass", "bx_boom"]),
        ("pad", ["pad", "atmos", "ambient", "texture", "granul", "portal", "grain"]),
        ("sampler", ["sampler", "simpler", "kontakt", "sample", "battery", "decent", "spitfire", "labs", "phrase"]),
        ("synth", ["synth", "serum", "vital", "massive", "diva", "omnisphere", "sylenth", "spire", "pigments", "phase plant",
                   "hive", "repro", "zebra", "analog", "wavetable", "operator", "drift", "meld", "nexus", "avenger",
                   "minimoog", "prophet", "jup", "obx", "dx7", "osc", "polysynth", "ana", "sylenth1", "dune", "icarus", "thorn"]),
    ]

    static var ruleIconIDs: [String] { rules.map(\.icon) }

    /// Guesses are remembered per name/source/path: the plugin list is searched often and rarely changes.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    public static func guess(_ item: PluginItem) -> String {
        let cacheKey = item.source.rawValue + "|" + item.name + "|" + item.path.joined(separator: "/") + "|" + (item.format ?? "")
        cacheLock.lock()
        if let hit = cache[cacheKey] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        let icon = computeGuess(item)
        cacheLock.lock()
        cache[cacheKey] = icon
        cacheLock.unlock()
        return icon
    }

    /// One-word product names that say nothing on their own (looked up: FabFilter One/Twin/Simplon/Micro, Supertone
    /// Clear/Goyo, Minimal Current/Rift/Evoke, NEST DELTA, Output Thermal …). Compact lowercase name → icon.
    private static let exactNames: [String: String] = [
        "clear": "repair", "goyo": "repair", "one": "synth", "twin3": "synth", "simplon": "synth", "micro": "filter",
        "m1": "synth", "ba1": "synth", "ax73": "synth", "rav3": "synth", "current": "synth", "hype": "synth",
        "evoke": "vocal", "bxoberhausen": "synth", "ravegenerator3": "synth", "moscillator": "sine", "mnoisegenerator": "sine",
        "mccgenerator": "sine", "knock": "drums", "delta": "saturation", "rift": "distortion", "thermal": "distortion",
        "corrosion": "distortion", "cassette": "tape",
    ]

    private static func computeGuess(_ item: PluginItem) -> String {
        // "REQ 2 Stereo" is an EQ, not a stereo tool: guess from the name without its channel suffix.
        let plain = PluginVariants.channel(item.name).base
        let name = plain.lowercased()
        if let exact = exactNames[SearchMatcher.compact(name)] { return exact }
        // Words split at spaces/punctuation and at camelCase ("AUGraphicEQ" → augraphic, eq).
        let words = Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init) + SearchMatcher.words(plain))
        let bytes = Array(name.utf8)
        for rule in compiledRules where rule.matches(name: name, bytes: bytes, words: words) {
            return rule.icon
        }
        if item.source.isPreset { return PresetFormat.fallbackIcon(item) }
        switch item.source {
        case .instruments: return "synth"
        case .midiEffects: return "midi"
        default: return IconCatalog.defaultID
        }
    }

    /// The rules with each keyword sorted once: short single words ("eq", "rx") must match a whole word,
    /// longer ones may sit anywhere in the name. Checked per plugin, so worked out once, not per plugin.
    private struct CompiledRule {
        let icon: String
        let wholeWords: Set<String>
        /// With their UTF-8 bytes: a byte search is many times faster than String.contains (big libraries), and the
        /// keywords are ASCII, so every real match is also a byte match. A byte hit is then confirmed with
        /// String.contains, which also respects combining marks ("Gate" + accent is no gate).
        let substrings: [(text: String, bytes: [UInt8])]

        func matches(name: String, bytes: [UInt8], words: Set<String>) -> Bool {
            !wholeWords.isDisjoint(with: words)
                || substrings.contains { IconGuesser.contains(bytes, $0.bytes) && name.contains($0.text) }
        }
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard let first = needle.first, needle.count <= haystack.count else { return needle.isEmpty }
        var i = 0
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
                if j == needle.count { return true }
            }
            i += 1
        }
        return false
    }

    private static let compiledRules: [CompiledRule] = rules.map { rule in
        assert(rule.keywords.allSatisfy { $0.allSatisfy(\.isASCII) }, "the byte search needs ASCII keywords")
        let isWord: (String) -> Bool = { $0.count <= 3 && !$0.contains(" ") && !$0.contains("-") }
        return CompiledRule(icon: rule.icon, wholeWords: Set(rule.keywords.filter(isWord)),
                            substrings: rule.keywords.filter { !isWord($0) }.map { ($0, Array($0.utf8)) })
    }
}
