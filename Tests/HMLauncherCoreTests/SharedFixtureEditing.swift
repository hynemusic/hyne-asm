import XCTest
@testable import HMLauncherCore

/// Shared-fixture handlers for the panel, menu editing, colors and profiles (spec/fixtures/README.md).
/// The C# side (windows/HyneAsm.Core.Tests/Fixtures.Editing.cs) reads the same inputs the same way.
extension SharedFixtureTests {
    // MARK: Items and edit scripts

    /// An item as fixture JSON: `{name, uri?, source?, path?}`; uri defaults to "u:<name>", source to plugins
    /// (like `item()` in TestSupport).
    static func fixtureItem(_ v: JSONValue?) throws -> PluginItem {
        let name = try string(v?["name"])
        var uri = "u:" + name
        if case .string(let u)? = v?["uri"] { uri = u }
        var source = ItemSource.plugins
        if case .string(let s)? = v?["source"] {
            guard let parsed = ItemSource(rawValue: s) else { throw FixtureError(description: "unknown source \(s)") }
            source = parsed
        }
        return PluginItem(uri: uri, name: name, source: source, path: try strings(v?["path"]))
    }

    static func isNull(_ v: JSONValue?) -> Bool { v == nil || v == .null }

    /// Runs `ops` on a config. References: a category is an index, "$var", "favorites", a UUID or a name; an entry is
    /// "$var", a UUID or a title (first in list order of the op's category); a profile is an index, "$var" or a UUID;
    /// an item is an alias from `items` or an inline item. `"as": "x"` binds an op's returned id to "$x".
    struct EditScript {
        var config: LauncherConfig
        let items: [String: JSONValue]
        var vars: [String: UUID] = [:]

        init(_ input: JSONValue) throws {
            if let c = input["config"], c != .null { config = try decode(LauncherConfig.self, c) } else { config = .makeDefault() }
            if case .object(let o)? = input["items"] { items = o } else { items = [:] }
        }

        func item(_ v: JSONValue?) throws -> PluginItem {
            if case .string(let alias)? = v {
                guard let found = items[alias] else { throw FixtureError(description: "unknown item \(alias)") }
                return try fixtureItem(found)
            }
            return try fixtureItem(v)
        }

        func itemList(_ v: JSONValue?) throws -> [PluginItem] {
            guard case .array(let a)? = v else { return [] }
            return try a.map { try item($0) }
        }

        func variable(_ s: String) throws -> UUID? {
            guard s.hasPrefix("$") else { return nil }
            guard let id = vars[String(s.dropFirst())] else { throw FixtureError(description: "unbound \(s)") }
            return id
        }

        func category(_ v: JSONValue?) throws -> UUID {
            if case .number(let n)? = v { return config.categories[Int(n)].id }
            let s = try string(v)
            if let id = try variable(s) { return id }
            if s == "favorites" { return config.favoritesID }
            if let id = UUID(uuidString: s) { return id }
            guard let c = config.categories.first(where: { $0.name == s }) else { throw FixtureError(description: "no category \(s)") }
            return c.id
        }

        func entry(_ v: JSONValue?, in categoryID: UUID) throws -> UUID {
            let s = try string(v)
            if let id = try variable(s) { return id }
            if let id = UUID(uuidString: s) { return id }
            guard let id = config.orderedEntryIDs(in: categoryID).first(where: { config.findEntry($0, in: categoryID)?.title == s })
            else { throw FixtureError(description: "no entry \(s)") }
            return id
        }

        func optionalEntry(_ v: JSONValue?, in categoryID: UUID) throws -> UUID? {
            isNull(v) ? nil : try entry(v, in: categoryID)
        }

        func entries(_ v: JSONValue?, in categoryID: UUID) throws -> [UUID] {
            guard case .array(let a)? = v else { return [] }
            return try a.map { try entry($0, in: categoryID) }
        }

        func profile(_ v: JSONValue?) throws -> UUID {
            if case .number(let n)? = v { return config.profiles[Int(n)].id }
            let s = try string(v)
            if let id = try variable(s) { return id }
            guard let id = UUID(uuidString: s) else { throw FixtureError(description: "bad profile \(s)") }
            return id
        }

        func action(_ v: JSONValue?) throws -> LiveAction { try decode(LiveAction.self, v) }

        static func rule(_ v: JSONValue?) throws -> ColorRule {
            if case .string("live")? = v { return .liveDevices }
            return .vendor(try string(v?["vendor"]))
        }

        static func optionalString(_ v: JSONValue?) throws -> String? { isNull(v) ? nil : try string(v) }

        static func id(_ id: UUID?) -> JSONValue { id.map { .string($0.uuidString) } ?? .null }

        mutating func bind(_ op: JSONValue, _ id: UUID?) -> JSONValue {
            if case .string(let name)? = op["as"], let id { vars[name] = id }
            return Self.id(id)
        }

        /// One op; returns what the Swift method returns (ids as strings), or null.
        mutating func run(_ op: JSONValue) throws -> JSONValue {
            let name = try string(op["op"])
            switch name {
            // ConfigEditing
            case "addEntry":
                let cat = try category(op["cat"])
                config.addEntry(try item(op["item"]), to: cat, folder: try optionalEntry(op["folder"], in: cat))
            case "addChain":
                let cat = try category(op["cat"])
                let id = config.addChain(named: try string(op["name"]), steps: try itemList(op["steps"]), to: cat,
                                         folder: try optionalEntry(op["folder"], in: cat))
                return bind(op, id)
            case "updateChain":
                let cat = try category(op["cat"])
                config.updateChain(try entry(op["entry"], in: cat), in: cat, name: try string(op["name"]), steps: try itemList(op["steps"]))
            case "updateAction":
                let cat = try category(op["cat"])
                config.updateAction(try entry(op["entry"], in: cat), in: cat, to: try action(op["action"]))
            case "addAction":
                let cat = try category(op["cat"])
                config.addAction(try action(op["action"]), to: cat, folder: try optionalEntry(op["folder"], in: cat))
            case "addFolder":
                return bind(op, config.addFolder(named: try string(op["name"]), to: try category(op["cat"])))
            case "removeEntry":
                let cat = try category(op["cat"])
                config.removeEntry(try entry(op["entry"], in: cat), from: cat)
            case "moveEntry":
                let cat = try category(op["cat"])
                config.moveEntry(in: cat, folder: try optionalEntry(op["folder"], in: cat), from: try int(op["from"]), to: try int(op["to"]))
            case "moveToFolder":
                let cat = try category(op["cat"])
                config.moveEntry(try entry(op["entry"], in: cat), toFolder: try optionalEntry(op["folder"], in: cat), in: cat)
            case "renameFolder":
                let cat = try category(op["cat"])
                config.renameFolder(try entry(op["folder"], in: cat), in: cat, to: try string(op["name"]))
            case "dissolveFolder":
                let cat = try category(op["cat"])
                config.dissolveFolder(try entry(op["folder"], in: cat), in: cat)
            case "addCategory":
                return bind(op, config.addCategory(named: try string(op["name"])))
            case "renameCategory":
                config.renameCategory(try category(op["cat"]), to: try string(op["name"]))
            case "deleteCategory":
                config.deleteCategory(try category(op["cat"]))
            case "moveCategory":
                config.moveCategory(from: try int(op["from"]), to: try int(op["to"]))
            case "moveCategoryBefore":
                config.moveCategory(try category(op["cat"]), before: isNull(op["before"]) ? nil : try category(op["before"]))
            case "setIcon":
                let cat = try category(op["cat"])
                config.setIcon(try string(op["icon"]), entry: try entry(op["entry"], in: cat), in: cat)
            case "setDisplayName":
                let cat = try category(op["cat"])
                config.setDisplayName(try Self.optionalString(op["name"]), entry: try entry(op["entry"], in: cat), in: cat)
            case "allPluginEntries":
                return .array(config.allPluginEntries.map { .string($0.title) })
            case "favoritesID":
                return Self.id(config.favoritesID)
            case "favoriteEntry":
                let isFolder: Bool = { if case .bool(true)? = op["folderRow"] { return true } else { return false } }()
                let row = PanelRow(uri: try string(op["uri"]), name: "", source: .plugins, path: [], iconID: "", title: "",
                                   isAvailable: true, folderID: isFolder ? UUID() : nil)
                return Self.id(config.favoriteEntry(for: row, items: try itemList(op["installed"]))?.id)
            // MultiEdit
            case "orderedEntryIDs":
                return .array(config.orderedEntryIDs(in: try category(op["cat"])).map { .string($0.uuidString) })
            case "moveEntries":
                let cat = try category(op["cat"])
                config.moveEntries(try entries(op["entries"], in: cat), toFolder: try optionalEntry(op["folder"], in: cat),
                                   before: try optionalEntry(op["before"], in: cat), in: cat)
            case "moveEntriesToCategory":
                let from = try category(op["from"])
                config.moveEntries(try entries(op["entries"], in: from), toCategory: try category(op["to"]), from: from)
            case "groupEntries":
                let cat = try category(op["cat"])
                return bind(op, config.groupEntries(try entries(op["entries"], in: cat), in: cat, named: try string(op["name"])))
            // BrowserSelection
            case "addSelection":
                let cat = try category(op["cat"])
                var folders: [BrowserSelection.Folder] = []
                if case .array(let list)? = op["folders"] {
                    folders = try list.map { .init(title: try string($0["title"]), items: try itemList($0["items"])) }
                }
                var actions: [LiveAction] = []
                if case .array(let list)? = op["actions"] { actions = try list.map { try action($0) } }
                let selection = BrowserSelection(folders: folders, items: try itemList(op["items"]), actions: actions)
                let asFolders: Bool = { if case .bool(false)? = op["asFolders"] { return false } else { return true } }()
                config.add(selection, to: cat, folder: try optionalEntry(op["folder"], in: cat), asFolders: asFolders)
                return .object(["pluginCount": .number(Double(selection.pluginCount)), "isEmpty": .bool(selection.isEmpty)])
            // ColorLabels
            case "setColor":
                let cat = try category(op["cat"])
                config.setColor(try Self.optionalString(op["color"]), entry: try entry(op["entry"], in: cat), in: cat)
            case "setColorRule":
                config.setColorRule(try Self.optionalString(op["color"]), for: try Self.rule(op["rule"]))
            case "colorOf":
                let cat = try category(op["cat"])
                guard let e = config.findEntry(try entry(op["entry"], in: cat), in: cat) else { return .null }
                return optional(config.colorID(for: e))
            case "colorOfItem":
                return optional(config.colorID(for: try item(op["item"])))
            case "colorRule":
                return optional(config.colorRule(try Self.rule(op["rule"])))
            case "rulesForItem":
                return .array(ColorRule.forItem(try item(op["item"])).map { .string($0.key) })
            case "palette":
                return .array(ColorPalette.all.map { c in
                    .object(["id": .string(c.id), "label": .string(c.label), "red": .number(c.red), "green": .number(c.green),
                             "blue": .number(c.blue)])
                })
            case "color":
                return optional(ColorPalette.color(try Self.optionalString(op["id"]))?.id)
            // Profiles
            case "addProfile":
                let copy: Bool = { if case .bool(true)? = op["copy"] { return true } else { return false } }()
                return bind(op, config.addProfile(named: try string(op["name"]), copyingCurrent: copy))
            case "switchProfile":
                config.switchProfile(to: try profile(op["profile"]))
            case "nextProfile":
                config.switchToNextProfile()
            case "renameProfile":
                config.renameProfile(try profile(op["profile"]), to: try string(op["name"]))
            case "deleteProfile":
                config.deleteProfile(try profile(op["profile"]))
            case "activeProfile":
                return .object(["id": .string(config.activeProfile.id.uuidString), "name": .string(config.activeProfile.name)])
            // Search rules (set up for panel.state)
            case "pin":
                config.pinSearchResult(try string(op["key"]), for: try string(op["query"]))
            case "hide":
                config.hideSearchResult(try string(op["key"]), for: try string(op["query"]))
            default:
                throw FixtureError(description: "unknown op \(name)")
            }
            return .null
        }
    }

    /// A model value as fixture JSON (its Codable form).
    static func json<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Ids the run generated (not in `input`) → `NEW-1`, `NEW-2` … in order of appearance in the canonical text.
    static func normalizeGenerated(_ output: JSONValue, input: JSONValue) throws -> JSONValue {
        let text = replaceGenerated(in: output.pretty(), input: input.pretty())
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    static func withGerman<T>(_ body: () throws -> T) rethrows -> T {
        let saved = Loc.language
        Loc.language = .de
        defer { Loc.language = saved }
        return try body()
    }

    /// `{config?, items?, ops, show?}` → `{results, categories, …show}` (German UI strings). `show` adds
    /// "colorRules", "profiles", "activeProfileID".
    static func editScript(_ input: JSONValue) throws -> JSONValue {
        try withGerman {
            var script = try EditScript(input)
            guard case .array(let ops)? = input["ops"] else { throw FixtureError(description: "edit script needs ops") }
            let results = try ops.map { try script.run($0) }
            var out: [String: JSONValue] = ["results": .array(results), "categories": try json(script.config.categories)]
            for key in try strings(input["show"]) {
                switch key {
                case "colorRules": out[key] = try json(script.config.colorRules)
                case "profiles": out[key] = try json(script.config.profiles)
                case "activeProfileID": out[key] = .string(script.config.activeProfileID.uuidString)
                default: throw FixtureError(description: "unknown show \(key)")
                }
            }
            return try normalizeGenerated(.object(out), input: input)
        }
    }

    // MARK: Panel

    /// A panel row as fixture JSON: `rowJSON` plus `folderID` and `childCount` for folder rows.
    static func panelRowJSON(_ r: PanelRow) -> JSONValue {
        guard case .object(var o) = rowJSON(r) else { return .null }
        if let f = r.folderID {
            o["folderID"] = .string(f.uuidString)
            o["childCount"] = .number(Double(r.childCount))
        }
        return .object(o)
    }

    /// `{config?, items, ops?, installed, usage?, selectedTab?, events}` → one snapshot per event (and one at the start):
    /// `{event, action, tab, filter, filterSelected, highlighted, page, pageSize, openFolder, rows}`, plus `tabs` at the
    /// start and `folderRows` for a "folderRows" event. Events: `{type: "tab", index}`, `{type: "key", key}`,
    /// `{type: "text", chars}` (one key per Character; action of the last), `{type: "page", page}`,
    /// `{type: "pageSize", size}`, `{type: "openFolder", folder}`, `{type: "closeFolder"}`, `{type: "folderRows", folder}`.
    /// Folders are entry references in the selected tab's category.
    static func panelState(_ input: JSONValue) throws -> JSONValue {
        try withGerman {
            var script = try EditScript(input)
            if case .array(let ops)? = input["ops"] { for op in ops { _ = try script.run(op) } }
            var usage: [String: Int] = [:]
            if case .array(let pairs)? = input["usage"] {
                for p in pairs {
                    guard case .array(let kv) = p, kv.count == 2 else { continue }
                    usage[try string(kv[0])] = try int(kv[1])
                }
            }
            let selected: Int = { if case .number(let n)? = input["selectedTab"] { return Int(n) } else { return 0 } }()
            var state = PanelState(config: script.config, items: try script.itemList(input["installed"]), selectedTab: selected, usage: usage)
            func currentCategory() -> UUID {
                guard case .category(let id, _) = state.tabs[state.selectedTab] else { return UUID() }
                return id
            }
            func snapshot(_ event: String, _ action: PanelAction?) -> [String: JSONValue] {
                var actionJSON = JSONValue.null
                switch action {
                case nil: break
                case .some(PanelAction.none): actionJSON = .string("none")
                case .close?: actionJSON = .string("close")
                case .insert(let row)?: actionJSON = .string("insert \(row.usageKey)")
                }
                return ["event": .string(event), "action": actionJSON, "tab": .number(Double(state.selectedTab)),
                        "filter": .string(state.filter), "filterSelected": .bool(state.isFilterSelected),
                        "highlighted": state.highlighted.map { .number(Double($0)) } ?? .null,
                        "page": .number(Double(state.page)), "pageSize": .number(Double(state.pageSize)),
                        "openFolder": optional(state.openFolderName), "rows": .array(state.rows.map(panelRowJSON))]
            }
            var start = snapshot("start", nil)
            start["tabs"] = .array(state.tabs.map { tab -> JSONValue in
                guard case .category(_, let name) = tab else { return .null }
                return .string(name)
            })
            var steps: [JSONValue] = [.object(start)]
            guard case .array(let events)? = input["events"] else { throw FixtureError(description: "panel.state needs events") }
            for event in events {
                let type = try string(event["type"])
                var action: PanelAction?
                var extra: [String: JSONValue] = [:]
                switch type {
                case "tab": state.selectTab(try int(event["index"]))
                case "key": action = state.handle(try panelKey(event["key"]))
                case "text": for ch in try string(event["chars"]) { action = state.handle(.character(ch)) }
                case "page": state.page = try int(event["page"])
                case "pageSize": state.pageSize = try int(event["size"])
                case "openFolder": state.openFolder(try script.entry(event["folder"], in: currentCategory()))
                case "closeFolder": state.closeFolder()
                case "folderRows":
                    extra["folderRows"] = .array(state.folderRows(try script.entry(event["folder"], in: currentCategory())).map(panelRowJSON))
                default: throw FixtureError(description: "unknown panel event \(type)")
                }
                steps.append(.object(snapshot(type, action).merging(extra) { a, _ in a }))
            }
            return try normalizeGenerated(.array(steps), input: input)
        }
    }

    static func pair(_ v: JSONValue?) throws -> (Int, Int) {
        let n = try numbers(v)
        guard n.count == 2 else { throw FixtureError(description: "expected two numbers") }
        return (Int(n[0]), Int(n[1]))
    }

    static func sizeJSON(columns: Int, rows: Int, pageSize: Int) -> JSONValue {
        .object(["columns": .number(Double(columns)), "rows": .number(Double(rows)), "pageSize": .number(Double(pageSize))])
    }

    static func pageJSON(_ p: PanelPage) -> JSONValue {
        .object(["columns": .number(Double(p.columns)), "rows": .number(Double(p.rows)), "columnMajor": .bool(p.columnMajor),
                 "size": .number(Double(p.size))])
    }

    /// One of: `{order: [count, from, to]}`, `{size: [width, height]}`, `{grid: [columns, rows], set?: {columns?, rows?}}`,
    /// `{list: …same}`, `{page: {columns, rows, columnMajor} | {style, grid, list}, slots: [[row, column]], positions: [slot]}`,
    /// `{config}` (decoded) → its panel layout settings.
    static func panelGrid(_ input: JSONValue) throws -> JSONValue {
        if case .array? = input["order"] {
            let n = try numbers(input["order"]).map(Int.init)
            return .array(PanelGrid.order(count: n[0], moving: n[1], to: n[2]).map { .number(Double($0)) })
        }
        if case .array? = input["size"] {
            let n = try numbers(input["size"])
            let s = PanelSize(columnWidth: n[0], itemHeight: n[1])
            return .object(["columnWidth": .number(s.columnWidth), "itemHeight": .number(s.itemHeight)])
        }
        if case .array? = input["grid"] {
            let (c, r) = try pair(input["grid"])
            var g = PanelGridSize(columns: c, rows: r)
            if case .number(let v)? = input["set"]?["columns"] { g.columns = Int(v) }
            if case .number(let v)? = input["set"]?["rows"] { g.rows = Int(v) }
            return sizeJSON(columns: g.columns, rows: g.rows, pageSize: g.pageSize)
        }
        if case .array? = input["list"] {
            let (c, r) = try pair(input["list"])
            var l = PanelListSize(columns: c, rows: r)
            if case .number(let v)? = input["set"]?["columns"] { l.columns = Int(v) }
            if case .number(let v)? = input["set"]?["rows"] { l.rows = Int(v) }
            return sizeJSON(columns: l.columns, rows: l.rows, pageSize: l.pageSize)
        }
        if let p = input["page"] {
            let page: PanelPage
            if case .string(let s)? = p["style"] {
                guard let style = PanelStyle(rawValue: s) else { throw FixtureError(description: "unknown style \(s)") }
                let (gc, gr) = try pair(p["grid"]), (lc, lr) = try pair(p["list"])
                page = PanelPage(style: style, grid: PanelGridSize(columns: gc, rows: gr), list: PanelListSize(columns: lc, rows: lr))
            } else {
                let major: Bool = { if case .bool(true)? = p["columnMajor"] { return true } else { return false } }()
                page = PanelPage(columns: try int(p["columns"]), rows: try int(p["rows"]), columnMajor: major)
            }
            guard case .object(var o) = pageJSON(page) else { return .null }
            var slots: [JSONValue] = []
            if case .array(let list)? = input["slots"] {
                for rc in list {
                    let (r, c) = try pair(rc)
                    slots.append(.number(Double(page.slot(row: r, column: c))))
                }
            }
            o["slots"] = .array(slots)
            o["positions"] = .array(try numbers(input["positions"]).map { s in
                let p = page.position(of: Int(s))
                return .array([.number(Double(p.row)), .number(Double(p.column))])
            })
            return .object(o)
        }
        let c = try decode(LauncherConfig.self, input["config"])
        return .object([
            "panelPage": pageJSON(c.panelPage),
            "panelGrid": sizeJSON(columns: c.panelGrid.columns, rows: c.panelGrid.rows, pageSize: c.panelGrid.pageSize),
            "panelList": sizeJSON(columns: c.panelList.columns, rows: c.panelList.rows, pageSize: c.panelList.pageSize),
            "panelStyle": .string(c.panelStyle.rawValue), "categoryPlacement": .string(c.categoryPlacement.rawValue),
            "panelSize": .object(["columnWidth": .number(c.panelSize.columnWidth), "itemHeight": .number(c.panelSize.itemHeight)]),
        ])
    }

    /// `{installed, probes}` (probes are items, turned into entries) → `[{linear, index}]` resolved uris.
    static func entryResolve(_ input: JSONValue) throws -> JSONValue {
        guard case .array(let installedJSON)? = input["installed"], case .array(let probes)? = input["probes"] else {
            throw FixtureError(description: "entry.resolve needs installed and probes")
        }
        let installed = try installedJSON.map(fixtureItem)
        let index = EntryResolver.Index(installed)
        return .array(try probes.map { p in
            let e = Entry(item: try fixtureItem(p))
            return .object(["linear": optional(EntryResolver.resolve(e, in: installed)?.uri), "index": optional(index.resolve(e)?.uri)])
        })
    }
}
