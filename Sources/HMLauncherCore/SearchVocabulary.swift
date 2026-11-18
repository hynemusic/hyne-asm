import Foundation

/// Words people type for a kind of plugin ("comp", "verb") → the icon kinds that stand for it.
/// A query that is one of these words also finds every item of that kind, ranked below name matches.
public enum SearchVocabulary {
    private static let table: [(words: [String], icons: [String])] = [
        (["comp", "compressor", "kompressor", "dynamics", "dynamik", "bus comp", "glue"], ["compressor", "glue"]),
        (["limit", "limiter", "maximizer", "clipper"], ["limiter"]),
        (["eq", "equalizer", "equaliser", "entzerrer"], ["eq", "eq-curve"]),
        (["filter", "lowpass", "highpass"], ["filter"]),
        (["verb", "reverb", "hall", "hall", "raum", "room", "space"], ["reverb", "space"]),
        (["delay", "echo"], ["delay", "echo"]),
        (["dist", "distortion", "saturation", "sat", "saturator", "drive", "verzerrer", "tape"], ["distortion", "saturation", "tape"]),
        (["bitcrush", "crusher", "lofi", "lo-fi"], ["bitcrush", "tape"]),
        (["chorus", "flanger", "phaser", "mod", "modulation", "tremolo"], ["chorus", "phaser", "modulation"]),
        (["stereo", "width", "imager", "widener"], ["stereo"]),
        (["gate", "expander"], ["gate"]),
        (["deesser", "de-esser", "sibilance"], ["deesser"]),
        (["transient", "shaper"], ["transient"]),
        (["pitch", "tune", "tuning", "autotune"], ["pitch", "tuner"]),
        (["vocal", "vocals", "voice", "stimme"], ["vocal"]),
        (["synth", "synthesizer", "synthesiser", "instrument"], ["synth", "sine", "pad", "keys", "bass"]),
        (["bass", "sub"], ["bass"]),
        (["pad", "ambient", "texture"], ["pad", "texture"]),
        (["keys", "piano", "rhodes", "organ"], ["keys"]),
        (["drum", "drums", "kick", "snare", "beat", "percussion"], ["drums"]),
        (["sampler", "sample", "simpler"], ["sampler"]),
        (["strings", "orchestra", "orchestral"], ["strings"]),
        (["meter", "analyzer", "analyser", "scope", "spectrum"], ["meter", "analyzer"]),
        (["utility", "gain", "tool"], ["utility"]),
        (["midi", "arp", "arpeggiator", "chord", "chords"], ["midi", "arp", "chord"]),
        (["rack", "chain"], ["rack"]),
    ]

    /// Icon kinds for a one-word query (or a known two-word phrase); empty when it isn't a tag word.
    public static func icons(for query: String) -> Set<String> {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var result = Set<String>()
        for entry in table where entry.words.contains(where: { $0 == q || ($0.count >= 4 && q.count >= 4 && $0.hasPrefix(q)) }) {
            result.formUnion(entry.icons)
        }
        return result
    }
}

/// How well known a plugin or device is among producers, 0 (unknown) … 100. Breaks ties after the user's own
/// insert counts, so the plugin most people would mean comes first.
public enum Popularity {
    /// Compact lowercase name prefixes ("proq" matches "Pro-Q 3", "Pro-Q 4").
    private static let table: [(String, Int)] = [
        ("proq", 100), ("serum", 98), ("proc", 96), ("prol", 95), ("soothe", 93), ("valhallavintageverb", 92),
        ("valhalla", 90), ("ozone", 90), ("eqeight", 92), ("utility", 91), ("gluecompressor", 90), ("compressor", 88),
        ("saturator", 87), ("decapitator", 86), ("echoboy", 86), ("vital", 86), ("omnisphere", 85), ("kontakt", 85),
        ("massive", 84), ("diva", 82), ("pigments", 82), ("phaseplant", 80), ("shaperbox", 80), ("rc20", 80),
        ("ott", 80), ("limiter", 80), ("reverb", 80), ("delay", 79), ("autofilter", 79), ("drumrack", 85),
        ("simpler", 84), ("sampler", 80), ("operator", 80), ("wavetable", 82), ("drift", 76), ("neutron", 78),
        ("proR", 78), ("promb", 78), ("prods", 77), ("prog", 74), ("trashk", 70), ("cla", 76), ("ssl", 76),
        ("1176", 76), ("la2a", 76), ("pultec", 75), ("kickstart", 74), ("smartcomp", 72), ("smarteq", 72),
        ("bigsky", 70), ("crystallizer", 72), ("littlealterboy", 72), ("melodyne", 82), ("autotune", 80),
        ("spire", 74), ("sylenth", 76), ("nexus", 74), ("keyscape", 74), ("addictivedrums", 72),
    ]

    public static func score(_ name: String) -> Int {
        let compact = SearchMatcher.compact(name.lowercased())
        return table.first { compact.hasPrefix($0.0.lowercased()) }?.1 ?? 0
    }
}
