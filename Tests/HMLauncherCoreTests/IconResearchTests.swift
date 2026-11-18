import XCTest
@testable import HMLauncherCore

/// Real plugin names from a user's library that used to get the generic icon, with what they actually are.
final class IconResearchTests: XCTestCase {
    private func icon(_ name: String, vendor: String = "X") -> String {
        IconGuesser.guess(PluginItem(uri: name, name: name, source: .plugins, path: ["VST3", vendor]))
    }

    func testNewKindsExistInTheCatalog() {
        for id in ["amp", "mic", "repair", "headphones", "mastering", "resonance", "sidechain", "granular"] {
            XCTAssertNotNil(IconCatalog.all.first { $0.id == id }, id)
        }
    }

    func testResearchedNames() {
        let expected: [(String, String)] = [
            ("UAD Ampeg SVTVR", "amp"), ("UAD Friedman BE100", "amp"), ("GTR Stomp 4 (m->s)", "amp"), ("UAD Chandler GAV19T", "amp"),
            ("UAD Ocean Way Mic Collection", "mic"), ("Mic Mod", "mic"), ("UAD UA 610-B", "mic"), ("UAD Manley Reference Mic Preamp", "mic"),
            ("RX 10 De-click", "repair"), ("RX 10 Spectral De-noise", "repair"), ("AUSoundIsolation", "repair"), ("Goyo", "repair"), ("Clear", "repair"),
            ("Abbey Road Studio 3 (6->2)", "headphones"), ("HEADPHONE LAB", "headphones"),
            ("Ozone 12", "mastering"), ("bx_masterdesk", "mastering"), ("The God Particle", "mastering"), ("UAD elysia alpha master", "mastering"),
            ("Ozone 12 Clarity", "resonance"), ("soothe3", "resonance"), ("Gullfoss", "resonance"), ("Ozone 12 Spectral Shaper", "resonance"),
            ("MULTISTAGE SIDECHAIN", "sidechain"), ("PML Volume Ducker", "sidechain"),
            ("Il Granello", "granular"), ("Quanta 2", "granular"), ("Cymatics Dark Sky", "granular"),
            ("UAD EMT 140", "reverb"), ("UAD Lexicon 480L", "reverb"), ("UAD AKG BX 20", "reverb"), ("IR-L (m->s)", "reverb"),
            ("UAD Fairchild 670", "compressor"), ("UAD Teletronix LA-2", "compressor"), ("UAD dbx 160", "compressor"),
            ("UAD Manley Variable Mu", "compressor"), ("UAD elysia mpressor", "compressor"),
            ("UAD Roland RE-201", "delay"), ("UAD Cooper Time Cube", "delay"), ("SuperTap 2-Taps (m->s)", "delay"), ("UAD Korg SDD-3000", "delay"),
            ("UAD Studer A800", "tape"), ("UAD Ampex ATR-102", "tape"), ("Cassette", "tape"),
            ("AUGraphicEQ", "eq"), ("AUParametricEQ", "eq"), ("Maag EQ4", "eq"), ("UAD Tonelux Tilt", "eq"), ("SieQ", "eq"),
            ("Doubler2 (m->s)", "stereo"), ("Reel ADT (m->s)", "stereo"), ("MicroShift", "stereo"), ("Sidewidener II", "stereo"), ("PanMan", "stereo"),
            ("StandardCLIP", "limiter"), ("FreeClip", "limiter"), ("Gold Clip", "limiter"), ("Newfangled Elevate", "limiter"),
            ("Tremolator", "modulation"), ("MondoMod (m->s)", "modulation"),
            ("Morphoder (m->s)", "vocal"), ("AVOX THROAT", "vocal"), ("Evoke", "vocal"),
            ("Fresh Air", "sparkles"), ("Ozone 12 Exciter", "sparkles"), ("UAD Precision Enhancer kHz", "sparkles"),
            ("UAD Harrison 32C", "console"), ("UAD Trident A-Range", "console"), ("NEOLD WUNDERLICH", "console"), ("UAD Avalon VT-737sp", "console"),
            ("M1", "synth"), ("BA-1", "synth"), ("AX73", "synth"), ("Twin 3", "synth"), ("RAV3", "synth"), ("Current", "synth"),
            ("Micro", "filter"), ("MComb", "filter"),
            ("KNOCK", "drums"), ("DELTA", "saturation"), ("Rift", "distortion"), ("Thermal", "distortion"), ("Corrosion", "distortion"),
            ("Newfangled Punctuate", "transient"), ("UAD Oxford Envolution", "transient"),
            ("Mixed In Key SE", "analyzer"), ("Auto-Key 2", "tuner"), ("HalfTime", "pitch"),
            ("AVOX DUO", "vocal"), ("Formant", "vocal"), ("bx_digital V3", "eq"), ("bx_hybrid V2", "eq"), ("UAD Cambridge", "eq"),
            ("Newfangled EQuivocate", "eq"), ("bx_greenscreamer", "distortion"), ("bx_distorange", "distortion"), ("bx_metal2", "distortion"),
            ("bx_blackdist2", "distortion"), ("UAD Bermuda Triangle", "distortion"), ("UAD Raw", "distortion"), ("Rift Feedback Lite", "distortion"),
            ("bx_oberhausen", "synth"), ("RaveGenerator3", "synth"), ("UAD Roland CE-1", "chorus"), ("UAD Vertigo VSM-3", "saturation"),
            ("UAD CS-1", "console"), ("BA-1 FX Strip", "console"), ("UAD C-Suite C-Max", "compressor"), ("MRatio", "compressor"),
            ("UAD Ocean Way Studios", "reverb"), ("MSpectralPan", "stereo"), ("MBitFun", "bitcrush"),
            ("MOscillator", "sine"), ("MNoiseGenerator", "sine"), ("MMetronome", "utility"), ("MRecorder", "utility"),
            ("kHs Channel Mixer", "utility"), ("Splice Bridge", "utility"), ("AURogerBeep", "utility"),
            ("ROLI Studio Player", "keys"), ("DLSMusicDevice", "keys"), ("Reason Rack Plugin", "rack"), ("EffectRack", "rack"),
            ("REQ 2 Stereo", "eq"), ("REQ 6 Mono", "eq"), ("REDD17 Stereo", "console"), ("Renaissance Axx Stereo", "compressor"),
            ("CLA-76 Mono", "compressor"),
                        ("kHs Resonator", "filter"), ("UAD Sound Machine Wood Works", "strings"), ("bx_boom", "bass"),
        ]
        var wrong: [String] = []
        for (name, want) in expected where icon(name) != want { wrong.append("\(name): \(icon(name)) ≠ \(want)") }
        XCTAssertTrue(wrong.isEmpty, wrong.joined(separator: "\n"))
    }

    func testEarlierGuessesStay() {
        XCTAssertEqual(icon("Pro-Q 4"), "eq")
        XCTAssertEqual(icon("Pro-L 2"), "limiter")
        XCTAssertEqual(icon("ValhallaRoom"), "reverb")
        XCTAssertEqual(icon("Serum 2"), "synth")
        XCTAssertEqual(icon("Omnisphere"), "synth")
    }
}
