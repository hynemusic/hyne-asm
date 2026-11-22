import XCTest
@testable import HMLauncherCore

/// Shared-fixture handlers for the LES import, menu files and versions, usage, new & rarely used items and presets
/// (spec/fixtures/README.md). The C# side (windows/HyneAsm.Core.Tests/Fixtures.Files.cs) reads the same inputs the same way.
/// File handlers go through the real files (temporary folder) and return the written text, so the comparison is byte-level.
extension SharedFixtureTests {
    static func utf8(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    static func list(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let a)? = v { return a }
        return []
    }

    static func counts(_ v: JSONValue?) throws -> [String: Int] {
        guard case .object(let o)? = v else { return [:] }
        return try o.mapValues { try int($0) }
    }

    static func countsJSON(_ c: [String: Int]) -> JSONValue { .object(c.mapValues { .number(Double($0)) }) }

    /// Seconds since 1970.
    static func date(_ v: JSONValue?) throws -> Date {
        guard case .number(let n)? = v else { throw FixtureError(description: "expected a date (seconds since 1970)") }
        return Date(timeIntervalSince1970: n)
    }

    /// A written file as `{json, text?}` (null when there is none). The exact text only for files with at most one key:
    /// the plain `JSONEncoder` (usage.json, seen.json) writes dictionaries in hash order, so larger ones have no single form.
    static func fileJSON(_ url: URL) throws -> JSONValue {
        guard let data = try? Data(contentsOf: url) else { return .null }
        let tree = try JSONDecoder().decode(JSONValue.self, from: data)
        var o: [String: JSONValue] = ["json": tree]
        if case .object(let d) = tree, d.count > 1 {} else { o["text"] = .string(utf8(data)) }
        return .object(o)
    }

    // MARK: LES import

    static func lesParse(_ input: JSONValue) throws -> JSONValue {
        let text = try string(input)
        return withGerman {
            JSONValue.array(LESMenuParser.parse(text).map { c -> JSONValue in
                .object(["name": .string(c.name), "parent": c.parent.map { .number(Double($0)) } ?? .null,
                         "items": .array(c.items.map { .object(["display": .string($0.display), "query": .string($0.query)]) })])
            })
        }
    }

    static func lesQuery(_ input: JSONValue) throws -> JSONValue {
        let q = LESQuery(try string(input))
        return .object(["text": .string(q.text), "format": q.format.map { .string("\($0)") } ?? .null, "isPreset": .bool(q.isPreset)])
    }

    static func matchJSON(_ m: LESMatch) -> JSONValue {
        .object(["status": .string("\(m.status)"), "item": optional(m.item?.uri),
                 "alternatives": .array(m.alternatives.map { .string($0.uri) }), "isPreset": .bool(m.isPreset)])
    }

    static func menuEntryJSON(_ e: Entry) -> JSONValue {
        var o: [String: JSONValue] = ["name": .string(e.name), "title": .string(e.title), "uri": .string(e.uri), "iconID": .string(e.iconID)]
        if let d = e.displayName { o["displayName"] = .string(d) }
        if let children = e.children { o["children"] = .array(children.map(menuEntryJSON)) }
        return .object(o)
    }

    static func menuJSON(_ categories: [HMLauncherCore.Category]) -> JSONValue {
        .array(categories.map { c in
            .object(["name": .string(c.name), "isFavorites": .bool(c.isFavorites), "entries": .array(c.entries.map(menuEntryJSON))])
        })
    }

    /// Categories with their parent as an index (null: none, "missing": not in the draft), rows and counts.
    static func draftJSON(_ d: ImportDraft) -> JSONValue {
        let ids = d.categories.map(\.id)
        let categories = d.categories.map { c -> JSONValue in
            var parent = JSONValue.null
            if let p = c.parentID { parent = ids.firstIndex(of: p).map { .number(Double($0)) } ?? .string("missing") }
            return .object(["name": .string(c.name), "parent": parent, "rows": .array(c.rows.map { r in
                .object(["display": .string(r.display), "query": .string(r.query), "match": matchJSON(r.match)])
            })])
        }
        let n = d.counts
        return .object(["categories": .array(categories), "counts": .object([
            "found": .number(Double(n.found)), "uncertain": .number(Double(n.uncertain)), "notFound": .number(Double(n.notFound)),
        ])])
    }

    /// Draft edits; categories and rows are indices into the draft as it is at that op.
    static func draftOp(_ d: inout ImportDraft, _ op: JSONValue) throws {
        let ids = d.categories.map(\.id)
        func category(_ key: String) throws -> UUID { ids[try int(op[key])] }
        func row(_ c: Int) throws -> UUID { d.categories[c].rows[try int(op["row"])].id }
        switch try string(op["op"]) {
        case "removeRow":
            let c = try int(op["category"])
            d.removeRow(try row(c), from: ids[c])
        case "moveRow": d.moveRow(in: try category("category"), from: try int(op["from"]), to: try int(op["to"]))
        case "rename": d.renameCategory(try category("category"), to: try string(op["name"]))
        case "removeCategory": d.removeCategory(try category("category"))
        case "setParent":
            if isNull(op["parent"]) { d.setParent(try category("category"), to: nil) }
            else { d.setParent(try category("category"), to: try category("parent")) }
        case "moveCategory": d.moveCategory(from: try int(op["from"]), to: try int(op["to"]))
        case "merge": d.mergeCategory(try category("source"), into: try category("target"))
        case "setMatch":
            let c = try int(op["category"])
            d.setMatch(try fixtureItem(op["item"]), for: try row(c), in: ids[c])
        default: throw FixtureError(description: "les.match: unknown op")
        }
    }

    /// `{items, display, query}` → match; `{items, text, ops?, setup?, apply?}` → draft (+ menu after applying);
    /// `{restore: [HMLauncherCore.Category]}` → menu after `restoreMenu`. German UI strings.
    static func lesMatch(_ input: JSONValue) throws -> JSONValue {
        try withGerman {
            if case .array? = input["restore"] {
                var c = LauncherConfig.makeDefault()
                c.restoreMenu(try decode([HMLauncherCore.Category].self, input["restore"]))
                return menuJSON(c.categories)
            }
            let items = try list(input["items"]).map(fixtureItem)
            guard case .string(let text)? = input["text"] else {
                return matchJSON(LESMatcher(items: items).match(display: try string(input["display"]), query: try string(input["query"])))
            }
            var draft = ImportDraft.make(text: text, items: items)
            for op in list(input["ops"]) { try draftOp(&draft, op) }
            var out: [String: JSONValue] = ["draft": draftJSON(draft)]
            if case .array(let applies)? = input["apply"] {
                var c = LauncherConfig.makeDefault()
                for s in list(input["setup"]) {
                    if case .string(let name)? = s["category"] { _ = c.addCategory(named: name); continue }
                    let target = s["to"] == .string("favorites") ? c.favoritesID : c.categories[try int(s["to"])].id
                    c.addEntry(try fixtureItem(s["add"]), to: target)
                }
                for a in applies { c.apply(draft, mode: try string(a["mode"]) == "add" ? .add : .replace) }
                out["menu"] = menuJSON(c.categories)
            }
            return .object(out)
        }
    }

    // MARK: Menu files and versions

    /// The id with its random part (8 uppercase hex characters) shown as "HEX8".
    static func versionJSON(_ v: MenuVersion, randomID: Bool = false) -> JSONValue {
        var id = v.id
        if randomID, let dash = id.firstIndex(of: "-") {
            let suffix = id[id.index(after: dash)...]
            if suffix.count == 8, suffix.allSatisfy({ $0.isHexDigit && !$0.isLowercase }) { id = id[...dash] + "HEX8" }
        }
        return .object(["id": .string(id), "name": .string(v.name), "date": .number(v.date.timeIntervalSince1970),
                        "isAutomatic": .bool(v.isAutomatic), "categoryCount": .number(Double(v.categoryCount)),
                        "entryCount": .number(Double(v.entryCount))])
    }

    /// `{text}` → read as .hmlmenu and written again (`{text}` or `{error}`); `{save}` → the version file;
    /// `{files, load?}` → the store's list (and a loaded version written as .hmlmenu).
    static func filesMenu(_ input: JSONValue) throws -> JSONValue {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        if case .string(let text)? = input["text"] {
            let source = dir.appendingPathComponent("in.hmlmenu"), target = dir.appendingPathComponent("out.hmlmenu")
            try Data(text.utf8).write(to: source)
            let doc: MenuDocument
            do { doc = try MenuDocument.read(from: source) }
            catch is MenuDocument.NotAMenuFile { return .object(["error": .string("notAMenuFile")]) }
            catch { return .object(["error": .string("unreadable")]) }
            try doc.write(to: target)
            return .object(["text": .string(utf8(try Data(contentsOf: target)))])
        }
        let store = MenuVersionStore(directory: dir.appendingPathComponent("Versions"))
        if case .object? = input["save"] {
            let s = input["save"]
            let v = try store.save(name: try string(s?["name"]), categories: try decode([HMLauncherCore.Category].self, s?["categories"]),
                                   isAutomatic: s?["isAutomatic"] == .bool(true), date: try date(s?["date"]))
            let text = utf8(try Data(contentsOf: store.directory.appendingPathComponent(v.id + ".json")))
            return .object(["version": versionJSON(v, randomID: true), "text": .string(text),
                            "listed": .array(try store.list().map { versionJSON($0, randomID: true) })])
        }
        guard case .object(let files)? = input["files"] else { throw FixtureError(description: "files.hmlmenu: unknown input") }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        for (name, content) in files { try Data(try string(content).utf8).write(to: store.directory.appendingPathComponent(name)) }
        var out: [String: JSONValue] = ["list": .array(try store.list().map { versionJSON($0) })]
        if case .string(let id)? = input["load"] {
            let target = dir.appendingPathComponent("loaded.hmlmenu")
            try store.load(id).write(to: target)
            out["loaded"] = .string(utf8(try Data(contentsOf: target)))
        }
        return .object(out)
    }

    // MARK: Usage

    /// `{read}` → counts or error; `{write: {counts, exported}}` → the export's text; `{store: {initial?, ops}}` → usage.json.
    static func filesUsage(_ input: JSONValue) throws -> JSONValue {
        if case .string(let text)? = input["read"] {
            do { return .object(["counts": countsJSON(try UsageExport.read(Data(text.utf8)))]) }
            catch { return .object(["error": .bool(true)]) }
        }
        if case .object? = input["write"] {
            let w = input["write"]
            let data = try UsageExport(counts: try counts(w?["counts"]), exported: try date(w?["exported"])).data()
            return .object(["text": .string(utf8(data))])
        }
        guard case .object? = input["store"] else { throw FixtureError(description: "files.hmlusage: unknown input") }
        let s = input["store"]
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("usage.json")
        if case .string(let initial)? = s?["initial"] { try Data(initial.utf8).write(to: url) }
        let store = UsageStore(url: url)
        for op in list(s?["ops"]) {
            switch try string(op["op"]) {
            case "record": store.record(try string(op["key"]))
            case "merge": store.merge(try counts(op["counts"]))
            case "replaceAll": store.replaceAll(try counts(op["counts"]))
            case "reset": store.reset()
            case "remove": store.remove(try string(op["key"]))
            default: throw FixtureError(description: "files.hmlusage: unknown op")
            }
        }
        return .object(["counts": countsJSON(store.counts), "reloaded": countsJSON(UsageStore(url: url).counts),
                        "file": try fileJSON(url)])
    }

    /// `{initial?, updates: [{items, now}], probe: {items, now, file?, usage?}}` → seen.json and the new uris
    /// (from the store and from a fresh store reading the file).
    static func filesSeen(_ input: JSONValue) throws -> JSONValue {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("seen.json")
        if case .string(let initial)? = input["initial"] { try Data(initial.utf8).write(to: url) }
        let store = SeenStore(url: url)
        for u in list(input["updates"]) { store.update(with: try list(u["items"]).map(fixtureItem), now: try date(u["now"])) }
        let probe = input["probe"]
        var config = LauncherConfig.makeDefault()
        for f in list(probe?["file"]) { config.addEntry(try fixtureItem(f), to: config.favoritesID) }
        let items = try list(probe?["items"]).map(fixtureItem)
        let usage = try counts(probe?["usage"]), now = try date(probe?["now"])
        func newURIs(_ s: SeenStore) -> JSONValue {
            .array(NewItems.uris(items: items, seen: s, config: config, usage: usage, now: now).sorted().map(JSONValue.string))
        }
        return .object(["file": try fileJSON(url), "new": newURIs(store), "newAfterReload": newURIs(SeenStore(url: url))])
    }

    /// `{items, counts, config?}` → summary; `{readableName: [key]}` → names; `{rare: {config, items, usage, threshold?, keep?}}`.
    static func usageSummary(_ input: JSONValue) throws -> JSONValue {
        try withGerman {
            if case .array(let keys)? = input["readableName"] {
                return .array(try keys.map { .string(UsageStats.readableName(try string($0))) })
            }
            if case .object? = input["rare"] {
                let r = input["rare"]
                var config = try decode(LauncherConfig.self, r?["config"])
                for k in try strings(r?["keep"]) {
                    guard let id = UUID(uuidString: k) else { throw FixtureError(description: "bad uuid \(k)") }
                    config.keepEntry(id)
                }
                let index = SearchIndex(items: try decode([PluginItem].self, r?["items"]), config: config)
                var threshold = 1
                if !isNull(r?["threshold"]) { threshold = try int(r?["threshold"]) }
                let rare = RarelyUsed.entries(config: config, index: index, usage: try counts(r?["usage"]), threshold: threshold)
                return .object([
                    "rare": .array(rare.map { e in .object([
                        "title": .string(e.entry.title), "place": .string(e.place), "count": .number(Double(e.count)),
                        "category": .number(Double(config.categories.firstIndex { $0.id == e.categoryID } ?? -1)),
                    ]) }),
                    "kept": .array(config.keptEntries.map { .string($0.uuidString) }),
                ])
            }
            let items = try decode([PluginItem].self, input["items"])
            var config = LauncherConfig.makeDefault()
            if let c = input["config"], c != .null { config = try decode(LauncherConfig.self, c) }
            let s = UsageStats.summarize(try counts(input["counts"]), items: items, config: config)
            let stats = s.stats.map { st -> JSONValue in .object([
                "key": .string(st.key), "name": .string(st.name), "kind": .string(st.kind.rawValue), "count": .number(Double(st.count)),
                "share": .number(st.share), "iconID": .string(st.iconID), "colorID": optional(st.colorID), "isAvailable": .bool(st.isAvailable),
            ]) }
            return .object([
                "stats": .array(stats), "total": .number(Double(s.total)),
                "byKind": .array(s.byKind.map { .object(["kind": .string($0.kind.rawValue), "count": .number(Double($0.count)),
                                                         "title": .string($0.kind.title)]) }),
                "topShare": .array([1, 2, 3].map { .number(s.topShare($0)) }),
            ])
        }
    }

    // MARK: Presets

    /// `{op: match | isInside | isPresetFile | describe | copyDestination, …}` (paths as POSIX paths).
    static func presetsMatch(_ input: JSONValue) throws -> JSONValue {
        let path = { (key: String) throws -> URL in URL(fileURLWithPath: try string(input[key])) }
        switch try string(input["op"]) {
        case "match":
            let items = try decode([PluginItem].self, input["items"])
            return optional(PresetImport.match(try path("file"), in: items, library: try path("library"))?.uri)
        case "isInside":
            let folder = try path("folder")
            return .array(try strings(input["files"]).map { .bool(PresetImport.isInside(URL(fileURLWithPath: $0), folder)) })
        case "isPresetFile":
            return .array(try strings(input["files"]).map { .bool(PresetFormat.isPresetFile(URL(fileURLWithPath: $0))) })
        case "describe":
            return .array(try decode([PluginItem].self, input["items"]).map { item in .object([
                "label": .string(PresetFormat.label(item)), "group": .string(PresetFormat.groupTitle(item)),
                "fallbackIcon": .string(PresetFormat.fallbackIcon(item)),
            ]) })
        case "copyDestination":
            let library = tempDir()
            defer { try? FileManager.default.removeItem(at: library) }
            let folder = library.appendingPathComponent("Presets/HYNE ASM")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in try strings(input["existing"]) { try Data().write(to: folder.appendingPathComponent(name)) }
            let target = PresetImport.copyDestination(for: try path("file"), library: library)
            return .object(["name": .string(target.lastPathComponent),
                            "folder": .array(target.deletingLastPathComponent().pathComponents.suffix(2).map(JSONValue.string))])
        default:
            throw FixtureError(description: "presets.match: unknown op")
        }
    }
}
