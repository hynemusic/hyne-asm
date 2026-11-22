import XCTest
@testable import HMLauncherCore

/// Small JSON tree used by the shared fixtures (spec/fixtures/*.json).
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Canonical text: 2-space indent, sorted keys, `"key": value`, no trailing newline.
    func pretty(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent + 2)
        let end = String(repeating: " ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let d):
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        case .string(let s): return JSONValue.quote(s)
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { pad + $0.pretty(indent: indent + 2) }.joined(separator: ",\n") + "\n" + end + "]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.keys.sorted().map { pad + JSONValue.quote($0) + ": " + o[$0]!.pretty(indent: indent + 2) }
                .joined(separator: ",\n") + "\n" + end + "}"
        }
    }

    private static func quote(_ s: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? enc.encode([s])) ?? Data("[\"\"]".utf8)
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

final class SharedFixtureTests: XCTestCase {
    /// One handler per fixture area. Later tasks add entries here (and one on the C# side).
    static let handlers: [String: (JSONValue) throws -> JSONValue] = [
        "smoke.echo": { $0 },
        "config.roundtrip": configRoundtrip,
        "config.migrate": configMigrate,
        "search.score": searchScore,
        "search.vocabulary": { .array(SearchVocabulary.icons(for: try string($0)).sorted().map(JSONValue.string)) },
        "search.popularity": { .number(Double(Popularity.score(try string($0)))) },
        "search.tuning": searchTuning,
        "variants.collapse": variantsCollapse,
        "variants.channel": variantsChannel,
        "plugins.groups": pluginsGroups,
        "icons.guess": { .array(try decode([PluginItem].self, $0).map { .string(IconGuesser.guess($0)) }) },
        "icons.catalog": { _ in
            .object(["all": .array(IconCatalog.all.map { .string($0.id) }),
                     "defaultID": .string(IconCatalog.defaultID), "folderID": .string(IconCatalog.folderID)])
        },
        "search.index": searchIndex,
        "search.quick": searchQuick,
        "search.quick_state": searchQuickState,
        "text.input": textInput,
        "keys.double_right_click": doubleRightClick,
        "keys.digit": { .array(try numbers($0).map { n in DigitKeys.digit(forKeyCode: UInt16(n)).map { .number(Double($0)) } ?? .null }) },
        "keys.shortcut_match": shortcutMatch,
        "keys.panel_bindings": panelBindings,
    ]

    /// Areas whose `expected` is hand-written (`"reference": "hand"`): the Swift side only validates, and returns `expected`.
    static let handValidators: [String: (_ input: JSONValue, _ expected: JSONValue) throws -> JSONValue] = [
        "keys.translation": validateKeyTranslation,
    ]

    struct FixtureError: Error, CustomStringConvertible { let description: String }

    /// Config text → decode → encode exactly as `ConfigStore.save` does. Ids and the Stream Deck token that decoding
    /// generates are random, so they become `NEW-1`, `NEW-2` … and `NEW-TOKEN` (the C# handler does the same).
    static func configRoundtrip(_ input: JSONValue) throws -> JSONValue {
        guard case .string(let text) = input else { throw FixtureError(description: "config.roundtrip: input must be a string") }
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        let config = try JSONDecoder().decode(LauncherConfig.self, from: Data(text.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = String(decoding: try encoder.encode(config), as: UTF8.self)
        return .string(replaceGenerated(in: output, input: text))
    }

    /// Config text → decode → `ConfigStore.migrate` (the v1→v4 steps `load` runs) → encode as `save` does.
    static func configMigrate(_ input: JSONValue) throws -> JSONValue {
        let text = try string(input)
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        var config = try JSONDecoder().decode(LauncherConfig.self, from: Data(text.utf8))
        ConfigStore.migrate(&config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = String(decoding: try encoder.encode(config), as: UTF8.self)
        return .string(replaceGenerated(in: output, input: text))
    }

    // MARK: Search and plugin lists

    static func string(_ v: JSONValue?) throws -> String {
        guard case .string(let s)? = v else { throw FixtureError(description: "expected a string, got \(String(describing: v))") }
        return s
    }

    static func strings(_ v: JSONValue?) throws -> [String] {
        guard case .array(let a)? = v else { return [] }
        return try a.map { try string($0) }
    }

    /// A model type from its JSON form (same Codable as the app's files).
    static func decode<T: Decodable>(_ type: T.Type, _ v: JSONValue?) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(v ?? .null))
    }

    static func optional(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }

    /// `{name, query}` → score or null; with `iconID`, the tag score for the query's vocabulary too.
    static func searchScore(_ input: JSONValue) throws -> JSONValue {
        let name = try string(input["name"]), query = try string(input["query"])
        let score: Int?
        if case .string(let icon)? = input["iconID"] {
            score = SearchMatcher.score(SearchMatcher.Prepared(name), SearchMatcher.Prepared(query), iconID: icon,
                                        tagIcons: SearchVocabulary.icons(for: query))
        } else {
            score = SearchMatcher.score(name, query)
        }
        return score.map { .number(Double($0)) } ?? .null
    }

    static func ruleJSON(_ r: SearchRule) -> JSONValue {
        .object(["query": .string(r.query), "pinned": .array(r.pinned.map(JSONValue.string)), "hidden": .array(r.hidden.map(JSONValue.string))])
    }

    /// One of: `{normalize}`, `{rule, rules}`, `{apply, rule?, inject}`, `{edit: [{op, key, query, by?}]}`.
    static func searchTuning(_ input: JSONValue) throws -> JSONValue {
        if case .string(let q)? = input["normalize"] { return .string(SearchTuning.normalize(q)) }
        if case .string(let q)? = input["rule"] {
            let rules = try strings(input["rules"]).map { SearchRule(query: $0) }
            return optional(SearchTuning.rule(for: q, in: rules)?.query)
        }
        if case .array? = input["apply"] {
            var rule: SearchRule?
            if case .object? = input["rule"] {
                rule = SearchRule(query: try string(input["rule"]?["query"]), pinned: try strings(input["rule"]?["pinned"]),
                                  hidden: try strings(input["rule"]?["hidden"]))
            }
            let inject = Set(try strings(input["inject"]))
            let out = SearchTuning.apply(try strings(input["apply"]), key: { $0 }, rule: rule) { inject.contains($0) ? $0 : nil }
            return .array(out.map(JSONValue.string))
        }
        guard case .array(let ops)? = input["edit"] else { throw FixtureError(description: "search.tuning: unknown input") }
        var c = LauncherConfig.makeDefault()
        for op in ops {
            let key = try string(op["key"]), query = try string(op["query"])
            switch try string(op["op"]) {
            case "pin": c.pinSearchResult(key, for: query)
            case "unpin": c.unpinSearchResult(key, for: query)
            case "hide": c.hideSearchResult(key, for: query)
            case "unhide": c.unhideSearchResult(key, for: query)
            case "move":
                guard case .number(let by)? = op["by"] else { throw FixtureError(description: "move needs by") }
                c.movePinnedSearchResult(key, by: Int(by), for: query)
            default: throw FixtureError(description: "search.tuning: unknown op")
            }
        }
        return .array(c.searchRules.map(ruleJSON))
    }

    /// Items → groups (uris, formats, channels, labels) and the usage key of every item.
    static func variantsCollapse(_ input: JSONValue) throws -> JSONValue {
        let items = try decode([PluginItem].self, input)
        let keys = PluginVariants.Keys(items)
        let groups = PluginVariants.collapse(items).map { g -> JSONValue in
            .object(["variants": .array(g.variants.map { .string($0.uri) }),
                     "formats": .array(g.formats.map(JSONValue.string)),
                     "channels": .array(g.channels.map(JSONValue.string)),
                     "labels": .array(g.variants.map { .string(PluginVariants.label($0)) })])
        }
        return .object(["groups": .array(groups), "keys": .array(items.map { .string(keys.key($0)) })])
    }

    static func variantsChannel(_ input: JSONValue) throws -> JSONValue {
        let c = PluginVariants.channel(try string(input))
        return .object(["base": .string(c.base), "label": optional(c.label)])
    }

    /// `{items, search}` (German UI strings) → groups with their item uris, and every item's format label.
    static func pluginsGroups(_ input: JSONValue) throws -> JSONValue {
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        let items = try decode([PluginItem].self, input["items"])
        let groups = PluginGrouping.groups(items, search: try string(input["search"])).map { g -> JSONValue in
            .object(["title": .string(g.title), "items": .array(g.items.map { .string($0.uri) })])
        }
        return .object(["groups": .array(groups), "formatLabels": .array(items.map { .string(PluginGrouping.formatLabel($0)) })])
    }

    static func rowJSON(_ r: PanelRow) -> JSONValue {
        var o: [String: JSONValue] = [
            "title": .string(r.title), "uri": .string(r.uri), "name": .string(r.name), "iconID": .string(r.iconID),
            "usageKey": .string(r.usageKey), "isGlobal": .bool(r.isGlobal), "isAvailable": .bool(r.isAvailable),
            "isNew": .bool(r.isNew), "path": .array(r.path.map(JSONValue.string)),
        ]
        if let c = r.colorID { o["colorID"] = .string(c) }
        if let chain = r.chain { o["chain"] = .array(chain.map(JSONValue.string)) }
        if let a = r.action { o["action"] = .string(a.title) }
        return .object(o)
    }

    /// `{items, config?, newURIs?}` → global rows with their alternatives, and every item's usage key.
    static func searchIndex(_ input: JSONValue) throws -> JSONValue {
        let items = try decode([PluginItem].self, input["items"])
        var config = LauncherConfig.makeDefault()
        if let c = input["config"], c != .null { config = try decode(LauncherConfig.self, c) }
        let index = SearchIndex(items: items, config: config, newURIs: Set(try strings(input["newURIs"])))
        let rows = index.globalRows.map { r -> JSONValue in
            guard case .object(var o) = rowJSON(r) else { return .null }
            o["alternatives"] = .array(index.alternatives(forKey: r.usageKey).map { .string($0.uri) })
            o["popularity"] = .number(Double(Popularity.score(r.title)))
            return .object(o)
        }
        return .object(["rows": .array(rows), "usageKeys": .array(items.map { optional(index.usageKey[$0.uri]) })])
    }

    /// `{items, config, usage: [[key, count]], queries}` → `[{query, results: [row + place]}]` (German action titles).
    static func searchQuick(_ input: JSONValue) throws -> JSONValue {
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        let items = try decode([PluginItem].self, input["items"])
        let config = try decode(LauncherConfig.self, input["config"])
        var usage: [String: Int] = [:]
        if case .array(let pairs)? = input["usage"] {
            for p in pairs {
                guard case .array(let kv) = p, kv.count == 2, case .number(let n) = kv[1] else { continue }
                usage[try string(kv[0])] = Int(n)
            }
        }
        let search = QuickSearch(config: config, items: items, usage: usage)
        return .array(try strings(input["queries"]).map { q -> JSONValue in
            let results = search.results(q).map { r -> JSONValue in
                guard case .object(var o) = rowJSON(r.row) else { return .null }
                if let place = r.place { o["place"] = .string(place) }
                return .object(o)
            }
            return .object(["query": .string(q), "results": .array(results)])
        })
    }

    // MARK: Keys and text

    static func numbers(_ v: JSONValue?) throws -> [Double] {
        guard case .array(let a)? = v else { return [] }
        return try a.map { guard case .number(let n) = $0 else { throw FixtureError(description: "expected a number") }; return n }
    }

    static func int(_ v: JSONValue?) throws -> Int {
        guard case .number(let n)? = v else { throw FixtureError(description: "expected a number, got \(String(describing: v))") }
        return Int(n)
    }

    static let simpleKeys: [String: PanelKey] = [
        "backspace": .backspace, "left": .left, "right": .right, "tab": .tab, "up": .up, "down": .down,
        "return": .returnKey, "escape": .escape, "selectAll": .selectAll, "deleteWord": .deleteWord, "deleteToStart": .deleteToStart,
    ]

    /// A key as fixture JSON: a name ("backspace", "selectAll" …), `{"digit": 4}` or `{"char": "é"}` (one Character).
    static func panelKey(_ v: JSONValue?) throws -> PanelKey {
        if case .string(let name)? = v, let k = simpleKeys[name] { return k }
        if case .number(let d)? = v?["digit"] { return .digit(Int(d)) }
        if case .string(let c)? = v?["char"] {
            guard c.count == 1, let ch = c.first else { throw FixtureError(description: "char must be one Character: \(c)") }
            return .character(ch)
        }
        throw FixtureError(description: "unknown key \(String(describing: v))")
    }

    static func keyName(_ k: PanelKey) -> String {
        switch k {
        case .digit(let d): return "digit \(d)"
        case .character(let c): return "char \(c)"
        default: return simpleKeys.first { $0.value == k }!.key
        }
    }

    static func combo(_ v: JSONValue?) throws -> KeyCombo {
        KeyCombo(keyCode: UInt16(try int(v?["keyCode"])), modifiers: ModifierSet(rawValue: UInt8(try int(v?["modifiers"]))))
    }

    static func comboJSON(_ c: KeyCombo) -> JSONValue {
        .object(["keyCode": .number(Double(c.keyCode)), "modifiers": .number(Double(c.modifiers.rawValue))])
    }

    /// `{initial?, ops: [key | "deselect"]}` → `{steps: [{handled, text, selected}]}`; "handled" is null for "deselect".
    static func textInput(_ input: JSONValue) throws -> JSONValue {
        var t = TextInput(try { if case .string(let s)? = input["initial"] { return s } else { return "" } }())
        guard case .array(let ops)? = input["ops"] else { throw FixtureError(description: "text.input needs ops") }
        let steps = try ops.map { op -> JSONValue in
            var handled = JSONValue.null
            if case .string("deselect") = op { t.deselect() } else { handled = .bool(t.apply(try panelKey(op))) }
            return .object(["handled": handled, "text": .string(t.text), "selected": .bool(t.isAllSelected)])
        }
        return .object(["steps": .array(steps)])
    }

    /// `{interval, times}` (seconds) → verdict per press.
    static func doubleRightClick(_ input: JSONValue) throws -> JSONValue {
        guard case .number(let interval)? = input["interval"] else { throw FixtureError(description: "needs interval") }
        var d = DoubleRightClickDetector(interval: interval)
        return .array(try numbers(input["times"]).map { .string(d.rightMouseDown(at: $0) == .openPanel ? "openPanel" : "passThrough") })
    }

    /// `{settings?, items: [{uri, keyCode, modifiers}], probes: [{keyCode, modifiers}]}` → `[{action, item}]` (item = uri).
    static func shortcutMatch(_ input: JSONValue) throws -> JSONValue {
        var settings = ShortcutSettings.default
        if let s = input["settings"], s != .null { settings = try decode(ShortcutSettings.self, s) }
        let matcher = ShortcutMatcher(settings: settings)
        var items: [ItemShortcut] = []
        if case .array(let list)? = input["items"] {
            for i in list {
                let item = PluginItem(uri: try string(i["uri"]), name: try string(i["uri"]), source: .plugins, path: [])
                items.append(ItemShortcut(combo: try combo(i), item: item))
            }
        }
        guard case .array(let probes)? = input["probes"] else { throw FixtureError(description: "needs probes") }
        return .array(try probes.map { p in
            let c = try combo(p)
            let action = matcher.match(keyCode: c.keyCode, modifiers: c.modifiers)
            let item = ShortcutMatcher.itemShortcut(keyCode: c.keyCode, modifiers: c.modifiers, in: items)
            return .object(["action": optional(action.map { "\($0)" }), "item": optional(item?.uri)])
        })
    }

    /// `{json, probes}` (json null = defaults) → bindings per action, the panel key per probe, German labels; or `{error}`.
    static func panelBindings(_ input: JSONValue) throws -> JSONValue {
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        var bindings = PanelKeyBindings.default
        if let j = input["json"], j != .null {
            do { bindings = try decode(PanelKeyBindings.self, j) } catch { return .object(["error": .bool(true)]) }
        }
        var perAction: [String: JSONValue] = [:], labels: [String: JSONValue] = [:]
        for a in PanelKeyAction.allCases {
            perAction[a.rawValue] = .array(bindings[a].map(comboJSON))
            labels[a.rawValue] = .string(a.label)
        }
        guard case .array(let probes)? = input["probes"] else { throw FixtureError(description: "needs probes") }
        let keys = try probes.map { optional(bindings.key(for: try combo($0)).map(keyName)) }
        return .object(["bindings": .object(perAction), "keys": .array(keys), "labels": .object(labels)])
    }

    /// `{items, config, usage, keys}` → one state per key: `{action, query, selected, highlighted, titles}`.
    static func searchQuickState(_ input: JSONValue) throws -> JSONValue {
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        let items = try decode([PluginItem].self, input["items"])
        let config = try decode(LauncherConfig.self, input["config"])
        var usage: [String: Int] = [:]
        if case .array(let pairs)? = input["usage"] {
            for p in pairs {
                guard case .array(let kv) = p, kv.count == 2 else { continue }
                usage[try string(kv[0])] = try int(kv[1])
            }
        }
        var state = QuickSearchState(search: QuickSearch(config: config, items: items, usage: usage))
        func snapshot(_ action: String) -> JSONValue {
            .object(["action": .string(action), "query": .string(state.query), "selected": .bool(state.isQuerySelected),
                     "highlighted": .number(Double(state.highlighted)), "titles": .array(state.results.map { .string($0.row.title) })])
        }
        guard case .array(let keys)? = input["keys"] else { throw FixtureError(description: "needs keys") }
        var steps = [snapshot("start")]
        for k in keys {
            let action: String
            switch state.handle(try panelKey(k)) {
            case .none: action = "none"
            case .close: action = "close"
            case .insert(let row): action = "insert \(row.usageKey)"
            }
            steps.append(snapshot(action))
        }
        return .array(steps)
    }

    /// macOS virtual key codes (Carbon `kVK_*`, HIToolbox/Events.h).
    static let macKeyCodes: Set<Int> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 67, 69, 71, 72, 73, 74, 75, 76, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
        96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 109, 111, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
        123, 124, 125, 126,
    ]

    /// Every `keyCode` under a "mac" key (input or expected) must be a real macOS key code; `expected` is returned unchanged.
    static func validateKeyTranslation(_ input: JSONValue, _ expected: JSONValue) throws -> JSONValue {
        func check(_ v: JSONValue) throws {
            guard case .object(let o) = v else { return }
            if case .object(let mac)? = o["mac"], case .number(let code)? = mac["keyCode"] {
                guard macKeyCodes.contains(Int(code)) else { throw FixtureError(description: "not a macOS key code: \(Int(code))") }
            }
            for (_, child) in o { try check(child) }
        }
        try check(input)
        try check(expected)
        return expected
    }

    /// UUIDs (and the Stream Deck token) in `output` that are not in `input` → `NEW-n` in order of first appearance.
    static func replaceGenerated(in output: String, input: String) -> String {
        let known = input.uppercased()
        var result = output
        let token = try! NSRegularExpression(pattern: "\"streamDeckToken\" : \"([0-9a-f]{20})\"")
        if let m = token.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let r = Range(m.range(at: 1), in: result), !input.contains(String(result[r])) {
            result.replaceSubrange(r, with: "NEW-TOKEN")
        }
        let uuid = try! NSRegularExpression(pattern: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
        var names: [String: String] = [:]
        for m in uuid.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            let id = String(result[Range(m.range, in: result)!])
            if !known.contains(id), names[id] == nil { names[id] = "NEW-\(names.count + 1)" }
        }
        for (id, name) in names { result = result.replacingOccurrences(of: id, with: name) }
        return result
    }

    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/fixtures")
    }

    func testAllFixtures() throws {
        let recording = ProcessInfo.processInfo.environment["HM_RECORD_FIXTURES"] == "1"
        let files = try FileManager.default.contentsOfDirectory(at: Self.fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no fixtures found in \(Self.fixturesDir.path)")

        for file in files {
            let name = file.lastPathComponent
            var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
            guard case .string(let area)? = root["area"], case .array(var cases)? = root["cases"] else {
                XCTFail("\(name): needs \"area\" and \"cases\""); continue
            }
            let isHand: Bool = { if case .string("hand")? = root["reference"] { return true } else { return false } }()
            let validator = isHand ? Self.handValidators[area] : nil
            let handler = Self.handlers[area]
            if handler == nil && validator == nil {
                if isHand { continue }   // validated later, once a handler exists
                XCTFail("\(name): no Swift handler for area \(area)"); continue
            }
            var seen = Set<String>()
            for i in cases.indices {
                guard case .string(let caseName)? = cases[i]["name"] else { XCTFail("\(name): case \(i) has no name"); continue }
                XCTAssertTrue(seen.insert(caseName).inserted, "\(name): duplicate case name \(caseName)")
                let input = cases[i]["input"] ?? .null
                let actual = try validator?(input, cases[i]["expected"] ?? .null) ?? handler!(input)
                if recording && !isHand {
                    guard case .object(var o) = cases[i] else { continue }
                    o["expected"] = actual
                    cases[i] = .object(o)
                } else {
                    XCTAssertEqual(actual, cases[i]["expected"] ?? .null, "\(name) / \(area) / \(caseName)")
                }
            }
            if recording && !isHand, case .object(var r) = root {
                r["cases"] = .array(cases)
                root = .object(r)
                try (root.pretty() + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
