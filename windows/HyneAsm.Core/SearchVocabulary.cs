namespace HyneAsm.Core;

/// <summary>Words people type for a kind of plugin ("comp", "verb") → the icon kinds that stand for it.
/// A query that is one of these words also finds every item of that kind, ranked below name matches.</summary>
public static class SearchVocabulary
{
    static readonly (string[] Words, string[] Icons)[] Table =
    {
        (new[] { "comp", "compressor", "kompressor", "dynamics", "dynamik", "bus comp", "glue" }, new[] { "compressor", "glue" }),
        (new[] { "limit", "limiter", "maximizer", "clipper" }, new[] { "limiter" }),
        (new[] { "eq", "equalizer", "equaliser", "entzerrer" }, new[] { "eq", "eq-curve" }),
        (new[] { "filter", "lowpass", "highpass" }, new[] { "filter" }),
        (new[] { "verb", "reverb", "hall", "hall", "raum", "room", "space" }, new[] { "reverb", "space" }),
        (new[] { "delay", "echo" }, new[] { "delay", "echo" }),
        (new[] { "dist", "distortion", "saturation", "sat", "saturator", "drive", "verzerrer", "tape" }, new[] { "distortion", "saturation", "tape" }),
        (new[] { "bitcrush", "crusher", "lofi", "lo-fi" }, new[] { "bitcrush", "tape" }),
        (new[] { "chorus", "flanger", "phaser", "mod", "modulation", "tremolo" }, new[] { "chorus", "phaser", "modulation" }),
        (new[] { "stereo", "width", "imager", "widener" }, new[] { "stereo" }),
        (new[] { "gate", "expander" }, new[] { "gate" }),
        (new[] { "deesser", "de-esser", "sibilance" }, new[] { "deesser" }),
        (new[] { "transient", "shaper" }, new[] { "transient" }),
        (new[] { "pitch", "tune", "tuning", "autotune" }, new[] { "pitch", "tuner" }),
        (new[] { "vocal", "vocals", "voice", "stimme" }, new[] { "vocal" }),
        (new[] { "synth", "synthesizer", "synthesiser", "instrument" }, new[] { "synth", "sine", "pad", "keys", "bass" }),
        (new[] { "bass", "sub" }, new[] { "bass" }),
        (new[] { "pad", "ambient", "texture" }, new[] { "pad", "texture" }),
        (new[] { "keys", "piano", "rhodes", "organ" }, new[] { "keys" }),
        (new[] { "drum", "drums", "kick", "snare", "beat", "percussion" }, new[] { "drums" }),
        (new[] { "sampler", "sample", "simpler" }, new[] { "sampler" }),
        (new[] { "strings", "orchestra", "orchestral" }, new[] { "strings" }),
        (new[] { "meter", "analyzer", "analyser", "scope", "spectrum" }, new[] { "meter", "analyzer" }),
        (new[] { "utility", "gain", "tool" }, new[] { "utility" }),
        (new[] { "midi", "arp", "arpeggiator", "chord", "chords" }, new[] { "midi", "arp", "chord" }),
        (new[] { "rack", "chain" }, new[] { "rack" }),
    };

    static readonly IReadOnlySet<string> None = new HashSet<string>();

    /// <summary>Icon kinds for a one-word query (or a known two-word phrase); empty when it isn't a tag word.</summary>
    public static IReadOnlySet<string> Icons(string query)
    {
        var q = Text.TrimWhitespaces(Text.Normalize(query));
        var count = Text.Count(q);
        if (count < 2) return None;
        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var (words, icons) in Table)
        {
            if (words.Any(w => w == q || (w.Length >= 4 && count >= 4 && Text.HasPrefix(w, q)))) result.UnionWith(icons);
        }
        return result;
    }
}

/// <summary>How well known a plugin or device is among producers, 0 (unknown) … 100. Breaks ties after the user's own
/// insert counts, so the plugin most people would mean comes first.</summary>
public static class Popularity
{
    /// <summary>Compact lowercase name prefixes ("proq" matches "Pro-Q 3", "Pro-Q 4").</summary>
    static readonly (string Prefix, int Score)[] Table =
    {
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
    };

    /// <summary>The table's prefixes lowercased once (Swift lowercases them on every call).</summary>
    static readonly (string Prefix, int Score)[] Lowered = Table.Select(e => (e.Prefix.ToLowerInvariant(), e.Score)).ToArray();

    public static int Score(string name)
    {
        var compact = SearchMatcher.Compact(Text.Normalize(name));
        foreach (var (prefix, score) in Lowered)
            if (Text.HasPrefixNfc(compact, prefix)) return score;   // compact is NFC, prefixes are ASCII
        return 0;
    }
}
