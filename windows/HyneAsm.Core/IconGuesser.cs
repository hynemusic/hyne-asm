using System.Collections.Concurrent;

namespace HyneAsm.Core;

/// <summary>Picks an icon from a plugin's name. First matching rule wins, so specific rules come first
/// (limiter before compressor, de-esser before compressor …). Not perfect — it only saves clicks.</summary>
public static class IconGuesser
{
    /// <summary>Keywords are matched case-insensitively. Keywords of ≤ 3 characters must be a whole word
    /// ("eq" matches "EQ Eight", not "Sequencer"); longer ones may appear anywhere ("verb" in "VintageVerb").</summary>
    static readonly (string Icon, string[] Keywords)[] Rules =
    {
        // Researched kinds first: they name what a plugin does more precisely than the generic words below.
        ("repair", new[] { "rx", "de-click", "de-hum", "de-noise", "denoise", "de-crackle", "de-clip",
            "de-plosive", "declick", "dehum", "breath control", "isolation", "dialogue isolate",
            "noise reduction" }),
        ("headphones", new[] { "headphone", "abbey road studio", "realphones", "room sim" }),
        ("sparkles", new[] { "exciter", "enhancer", "fresh air", "aphex" }),
        ("resonance", new[] { "soothe", "gullfoss", "clarity", "spectral shaper", "smooth operator",
            "resonance", "refinement" }),
        ("stereo", new[] { "imager" }),   // before "ozone": Ozone Imager is a stereo tool, not the mastering suite
        ("mastering", new[] { "ozone", "masterdesk", "god particle", "alpha master", "mastering",
            "master rebalance" }),
        ("sidechain", new[] { "sidechain", "side chain", "ducker", "duck", "kickstart", "volume shaper",
            "lfotool", "pump" }),
        ("granular", new[] { "granul", "granello", "grain", "dark sky", "quanta" }),
        ("mic", new[] { "mic", "mic collection", "mic mod", "preamp", "610", "v76", "townsend" }),
        ("tape", new[] { "studer", "ampex", "atr-102", "cassette" }),
        ("amp", new[] { "amp", "ampeg", "fender", "friedman", "engl", "diezel", "marshall", "suhr", "mesa",
            "gallien", "eden wt", "fuchs", "svt", "b15n", "tweed", "rockrack", "gtr", "megadual", "megasingle",
            "amplitube", "archetype", "guitar rig", "bias fx", "gav19" }),
        ("utility", new[] { "metronome", "recorder", "notepad", "channel mixer", "channelmatrix",
            "splice bridge", "netsend", "rogerbeep", "roundtrip", "magc" }),
        ("rack", new[] { "reason rack", "effectrack", "effect rack" }),
        ("console", new[] { "fx strip", "cs-1" }),
        ("drums", new[] { "kick", "snare", "808", "909", "drum", "hat", "clap", "percussion", "battery",
            "addictive drums", "superior drummer", "impact" }),
        ("deesser", new[] { "de-ess", "deess", "esser", "pro-ds", "sibilan" }),
        ("limiter", new[] { "limit", "pro-l", "l1", "l2", "l3", "maximizer", "maxim", "clipper", "kclip",
            "standard clip", "clip", "elevate" }),
        ("gate", new[] { "gate", "pro-g", "expander" }),
        ("transient", new[] { "transient", "smack", "punch", "trans-x", "punctuate", "envolution" }),
        ("compressor", new[] { "compress", "comp", "glue", "pro-c", "pro-mb", "1176", "76", "la-2a", "la2a",
            "ott", "dynamics", "multiband", "vca", "opto", "fet", "cl 1b", "distressor", "squash", "rvox",
            "fairchild", "teletronix", "la-2", "la-3a", "dbx", "variable mu", "vari-mu", "mpressor", "175-b",
            "176", "tla-100", "dyna-mite", "vsc-2", "magnum", "c-max", "mratio", "axx" }),
        ("eq", new[] { "eq", "req", "pro-q", "bx_digital", "bx_hybrid", "cambridge", "equivocate", "equaliz",
            "pultec", "eqp", "channel eq", "api 5", "neve 1073", "tilt", "maag", "nseq", "mdweq", "sieq",
            "sie-q", "graphiceq", "parametriceq" }),
        ("filter", new[] { "filter", "resonator", "volcano", "lowpass", "highpass", "autofilter", "wah", "comb",
            "cleansweep", "bandpass", "hipass" }),
        ("reverb", new[] { "verb", "reverb", "room", "plate", "hall", "valhalla", "pro-r", "space", "chamber",
            "spring", "supermassive", "shimmer", "convolution", "emt", "lexicon", "bx 20", "rmx16", "ir-l",
            "reflection engine", "480l", "ocean way studios" }),
        ("delay", new[] { "delay", "echoboy", "timeless", "primaltap", "h-delay", "tape echo", "repeat",
            "re-201", "space echo", "time cube", "sdd-3000", "supertap", "dmx 15" }),
        ("echo", new[] { "echo" }),
        ("chorus", new[] { "chorus", "ensemble", "dimension", "juno", "ce-1" }),
        ("phaser", new[] { "phaser", "flanger", "phase" }),
        ("modulation", new[] { "tremol", "vibrato", "lfo", "shaperbox", "rotary", "modulat", "auto pan",
            "autopan", "ring mod", "mondomod", "enigma" }),
        ("stereo", new[] { "imager", "stereo", "width", "wider", "haas", "spread", "mono", "doubler", "adt",
            "microshift", "widener", "panman", "panner", "split", "doppler", "spectralpan" }),
        ("tape", new[] { "tape", "vinyl", "lo-fi", "lofi", "rc-20", "wow", "flutter" }),
        ("bitcrush", new[] { "crush", "redux", "decimat", "bit", "erosion", "bitfun" }),
        ("distortion", new[] { "distort", "fuzz", "overdrive", "pedal", "roar", "trash", "devil-loc",
            "waveshaper", "wavefolder", "screamer", "distorange", "bx_metal", "blackdist", "bermuda", "uad raw",
            "rift feedback" }),
        ("saturation", new[] { "satur", "decapitator", "saturn", "tube", "warmth", "drive", "heat", "drum buss",
            "radiator", "kramer", "inflator", "vulture", "vsm-3" }),
        ("console", new[] { "redd", "ssl", "neve", "console", "channel strip", "bus", "neutron", "api",
            "harrison", "trident", "wunderlich", "avalon", "helios", "a-range", "voxbox" }),
        ("pitch", new[] { "tune", "pitch", "melodyne", "shifter", "harmoniz", "little alterboy", "crystallizer",
            "octave", "halftime", "half time" }),
        ("vocal", new[] { "vocal", "vox", "voice", "vocoder", "nectar", "choir", "morphoder", "throat",
            "articulator", "avox", "formant" }),
        ("analyzer", new[] { "spectrum", "analy", "span", "insight", "scope", "mixed in key", "metric" }),
        ("meter", new[] { "meter", "loudness", "lufs", "vu" }),
        ("tuner", new[] { "tuner", "auto-key" }),
        ("utility", new[] { "utility", "gain", "trim", "phase invert", "tool" }),
        ("arp", new[] { "arp", "arpeggiat" }),
        ("chord", new[] { "chord", "scaler", "harmony" }),
        ("keys", new[] { "roli", "dlsmusicdevice", "piano", "keys", "keyscape", "rhodes", "wurli", "electric",
            "grand", "organ", "b3", "noire", "una corda" }),
        ("strings", new[] { "wood works", "string", "violin", "cello", "orchestra", "tension", "collision",
            "harp", "guitar", "bass guitar" }),
        ("bass", new[] { "bass", "sub", "trilian", "monobass", "bx_boom" }),
        ("pad", new[] { "pad", "atmos", "ambient", "texture", "granul", "portal", "grain" }),
        ("sampler", new[] { "sampler", "simpler", "kontakt", "sample", "battery", "decent", "spitfire", "labs",
            "phrase" }),
        ("synth", new[] { "synth", "serum", "vital", "massive", "diva", "omnisphere", "sylenth", "spire",
            "pigments", "phase plant", "hive", "repro", "zebra", "analog", "wavetable", "operator", "drift",
            "meld", "nexus", "avenger", "minimoog", "prophet", "jup", "obx", "dx7", "osc", "polysynth", "ana",
            "sylenth1", "dune", "icarus", "thorn" }),
    };

    internal static IEnumerable<string> RuleIconIDs => Rules.Select(r => r.Icon);

    /// <summary>The rules with each keyword's kind worked out once: short single words are looked up among the words.</summary>
    static readonly (string Icon, (string Keyword, bool WholeWord)[] Keywords)[] Prepared = Rules
        .Select(r => (r.Icon, r.Keywords.Select(k => (k, k.Length <= 3 && !k.Contains(' ') && !k.Contains('-'))).ToArray()))
        .ToArray();

    /// <summary>Guesses are remembered per name/source/path: the plugin list is searched often and rarely changes.</summary>
    static readonly ConcurrentDictionary<string, string> Cache = new(Text.Canonical);

    public static string Guess(PluginItem item)
    {
        var cacheKey = Json.SwiftJson.RawValue(item.Source) + "|" + item.Name + "|" + string.Join("/", item.Path) + "|" + (item.Format ?? "");
        return Cache.GetOrAdd(cacheKey, _ => ComputeGuess(item));
    }

    /// <summary>One-word product names that say nothing on their own (looked up: FabFilter One/Twin/Simplon/Micro, Supertone
    /// Clear/Goyo, Minimal Current/Rift/Evoke, NEST DELTA, Output Thermal …). Compact lowercase name → icon.</summary>
    static readonly Dictionary<string, string> ExactNames = new(Text.Canonical)
    {
        ["clear"] = "repair", ["goyo"] = "repair", ["one"] = "synth", ["twin3"] = "synth",
        ["simplon"] = "synth", ["micro"] = "filter", ["m1"] = "synth", ["ba1"] = "synth", ["ax73"] = "synth",
        ["rav3"] = "synth", ["current"] = "synth", ["hype"] = "synth", ["evoke"] = "vocal",
        ["bxoberhausen"] = "synth", ["ravegenerator3"] = "synth", ["moscillator"] = "sine",
        ["mnoisegenerator"] = "sine", ["mccgenerator"] = "sine", ["knock"] = "drums", ["delta"] = "saturation",
        ["rift"] = "distortion", ["thermal"] = "distortion", ["corrosion"] = "distortion", ["cassette"] = "tape",
    };

    static string ComputeGuess(PluginItem item)
    {
        // "REQ 2 Stereo" is an EQ, not a stereo tool: guess from the name without its channel suffix.
        var plain = PluginVariants.Channel(item.Name).Base;
        var name = Text.Normalize(plain);
        if (ExactNames.TryGetValue(SearchMatcher.Compact(name), out var exact)) return exact;
        // Words split at spaces/punctuation and at camelCase ("AUGraphicEQ" → augraphic, eq).
        // Every word is NFC (from the NFC name, or SearchMatcher.Words), and so are the ASCII keywords: ordinal is canonical here.
        var words = new HashSet<string>(SplitWords(name), StringComparer.Ordinal);
        words.UnionWith(SearchMatcher.Words(plain));
        foreach (var (icon, keywords) in Prepared)
            foreach (var (keyword, wholeWord) in keywords)
                // name is NFC and the keywords are ASCII, so ordinal search is canonical here.
                if (wholeWord ? words.Contains(keyword) : Text.ContainsNfc(name, keyword)) return icon;
        if (item.Source.IsPreset()) return PresetFormat.FallbackIcon(item);
        return item.Source switch
        {
            ItemSource.Instruments => "synth",
            ItemSource.MidiEffects => "midi",
            _ => IconCatalog.DefaultID,
        };
    }

    /// <summary>Swift's <c>name.split { !$0.isLetter && !$0.isNumber }</c>.</summary>
    static IEnumerable<string> SplitWords(string name)
    {
        var current = new System.Text.StringBuilder();
        foreach (var ch in Text.Characters(name))
        {
            if (Text.IsLetterOrNumber(ch)) { current.Append(ch); continue; }
            if (current.Length > 0) { yield return current.ToString(); current.Clear(); }
        }
        if (current.Length > 0) yield return current.ToString();
    }
}
