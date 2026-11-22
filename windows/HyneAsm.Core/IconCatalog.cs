namespace HyneAsm.Core;

/// <summary>Icon ids, in the Mac catalog's order. Ids are stored in the config — never rename an existing id.
/// (The Mac draws SF Symbols; the Windows look for each id comes with the settings UI.)</summary>
public static class IconCatalog
{
    public const string DefaultID = "generic";
    public const string FolderID = "folder";

    public static readonly IReadOnlyList<string> AllIDs = new[]
    {
        "generic", "folder", "eq", "eq-curve", "filter", "compressor", "glue", "limiter", "gate", "deesser",
        "transient", "reverb", "delay", "echo", "stereo", "space", "saturation", "distortion", "bitcrush",
        "tape", "console", "texture", "modulation", "chorus", "phaser", "pitch", "vocal", "synth", "sine",
        "keys", "sampler", "drums", "bass", "strings", "pad", "utility", "meter", "analyzer", "tuner", "midi",
        "arp", "chord", "rack", "amp", "mic", "repair", "headphones", "mastering", "resonance", "sidechain",
        "granular", "star", "heart", "sparkles",
    };
}
