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
            let handler = Self.handlers[area]
            if handler == nil {
                if isHand { continue }   // validated later, once a handler exists
                XCTFail("\(name): no Swift handler for area \(area)"); continue
            }
            var seen = Set<String>()
            for i in cases.indices {
                guard case .string(let caseName)? = cases[i]["name"] else { XCTFail("\(name): case \(i) has no name"); continue }
                XCTAssertTrue(seen.insert(caseName).inserted, "\(name): duplicate case name \(caseName)")
                let input = cases[i]["input"] ?? .null
                let actual = try handler!(input)
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
