import SwiftUI
import HMLauncherCore

/// Popover list to pick one plugin, device or preset from Live's list (one row per plugin, best format).
struct ItemPicker: View {
    let items: [PluginItem]
    var title: String
    let onPick: (PluginItem) -> Void
    @State private var query = ""

    private var matches: [PluginItem] {
        let all = PluginVariants.collapse(items).map(\.preferred)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = SearchMatcher.Prepared(query)
        var hits: [(item: PluginItem, score: Int)] = []
        for i in all {
            if let score = SearchMatcher.score(SearchMatcher.Prepared(i.name), q) { hits.append((i, score)) }
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.item.name.localizedCaseInsensitiveCompare(b.item.name) == .orderedAscending
        }
        return hits.prefix(40).map { $0.item }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(title).font(DS.Font.columnTitle).foregroundColor(DS.textPrimary)
            SearchField(placeholder: Loc.t("Plugin, Device oder Preset …", "Plugin, device or preset …"), text: $query)
            ScrollView {
                LazyVStack(spacing: 1) {
                    if query.isEmpty {
                        HintText(text: Loc.t("Tipp los, um zu suchen.", "Start typing to search."), icon: nil).padding(.top, DS.Space.s)
                    }
                    ForEach(matches, id: \.uri) { item in
                        Button { onPick(item) } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: IconCatalog.symbolName(for: IconGuesser.guess(item)))
                                    .font(.system(size: 12)).foregroundColor(DS.textSecondary).frame(width: 18)
                                Text(item.name).font(DS.Font.body).foregroundColor(DS.textPrimary).lineLimit(1)
                                Spacer()
                                Text(UsageKind(item.source).title).font(DS.Font.caption).foregroundColor(DS.textTertiary)
                            }
                            .padding(.horizontal, DS.Space.s)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .modifier(HoverHighlight())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 280)
        }
        .padding(DS.Space.l)
        .frame(width: 380)
        .background(DS.surface)
    }
}

/// Settings page "Shape Search": type a search, see the results exactly as the quick search ranks them, and pin,
/// reorder or hide results for that search term. The rules apply to the panel filter and the quick search.
struct SearchTuningPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @State private var query = ProcessInfo.processInfo.environment["HM_SEARCH_QUERY"] ?? "" // developer aid for screenshots
    @State private var addingPin = false

    private var normalized: String { SearchTuning.normalize(query) }
    private var effectiveRule: SearchRule? { SearchTuning.rule(for: query, in: model.config.searchRules) }

    private var results: [QuickResult] {
        guard !normalized.isEmpty else { return [] }
        return QuickSearch(config: model.config, items: catalog.items, usage: model.usage.counts).results(query)
    }

    /// usage key → plugin, for naming hidden results.
    private var itemsByKey: [String: PluginItem] {
        let keys = PluginVariants.Keys(catalog.items)
        var map: [String: PluginItem] = [:]
        for g in PluginVariants.collapse(catalog.items) { map[keys.key(g.preferred)] = map[keys.key(g.preferred)] ?? g.preferred }
        return map
    }

    var body: some View {
        PageContainer(title: Loc.t("Suche formen", "Shape Search"),
                      subtitle: Loc.t("Tipp einen Suchbegriff und bestimm, was oben steht und was gar nicht erscheint. Gilt im Panel und in der Schnellsuche – auch für längere Eingaben (eine Regel für „ser“ gilt auch bei „serum“).",
                                      "Type a search and decide what comes first and what never shows. Applies to the panel and the quick search – also to longer input (a rule for “ser” also applies to “serum”)."),
                      maxWidth: 1040, scrolls: false) { EmptyView() } content: {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    SearchField(placeholder: Loc.t("Suchbegriff, z. B. „ser“", "Search term, e.g. “ser”"), text: $query)
                        .frame(maxWidth: 420)
                    if normalized.isEmpty { emptyState } else { resultsCard }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                rulesColumn.frame(width: 280)
            }
        }
    }

    // MARK: Results

    private var emptyState: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 30)).foregroundColor(DS.textTertiary)
            Text(Loc.t("Tipp oben einen Suchbegriff", "Type a search term above")).font(DS.Font.bodyStrong).foregroundColor(DS.textSecondary)
            Text(Loc.t("Du siehst dann die Treffer in der Reihenfolge, in der sie im Panel und in der Schnellsuche erscheinen.",
                       "You'll see the results in the order they appear in the panel and the quick search."))
                .font(DS.Font.caption).foregroundColor(DS.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .dsCard()
    }

    private var resultsCard: some View {
        let rule = effectiveRule
        let pinned = Set(rule?.pinned ?? [])
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                SectionLabel(text: Loc.t("Treffer für „\(normalized)“", "Results for “\(normalized)”"))
                Spacer()
                if let rule, rule.query != normalized {
                    Text(Loc.t("Regel von „\(rule.query)“ gilt", "Rule for “\(rule.query)” applies"))
                        .font(DS.Font.caption).foregroundColor(.accent)
                }
                Button { addingPin = true } label: { Label(Loc.t("Anderes Plugin anpinnen …", "Pin another plugin …"), systemImage: "pin") }
                    .buttonStyle(.borderless).font(DS.Font.caption)
                    .popover(isPresented: $addingPin, arrowEdge: .bottom) {
                        ItemPicker(items: catalog.items, title: Loc.t("Bei „\(normalized)“ ganz oben zeigen", "Show first for “\(normalized)”")) { item in
                            model.config.pinSearchResult(PluginVariants.Keys(catalog.items).key(item), for: query)
                            addingPin = false
                        }
                    }
            }
            ScrollView {
                VStack(spacing: 0) {
                    if results.isEmpty {
                        Text(Loc.t("Keine Treffer", "No results")).font(DS.Font.body).foregroundColor(DS.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        if index > 0 { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 76) }
                        resultRow(index, result, isPinned: pinned.contains(result.row.usageKey))
                    }
                    hiddenSection(rule)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
        }
    }

    private func resultRow(_ index: Int, _ result: QuickResult, isPinned: Bool) -> some View {
        let r = result.row
        let key = r.usageKey
        let uses = model.usage.counts[key] ?? 0
        return HStack(spacing: DS.Space.m) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(isPinned ? .onAccent : DS.textSecondary)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(isPinned ? Color.accent : (index < 9 ? DS.raised : .clear)))
            Image(systemName: IconCatalog.symbolName(for: r.iconID))
                .font(.system(size: 12)).foregroundColor(Color(label: r.colorID) ?? DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(DS.raised))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(r.title).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary).lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.accent)
                    }
                }
                Text([result.place ?? Loc.t("Alle Plugins", "All plugins"), uses > 0 ? Loc.t("\(uses)× eingefügt", "inserted \(uses)×") : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5)).foregroundColor(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.m)
            if isPinned {
                IconButton(symbol: "chevron.up", help: Loc.t("Weiter nach oben", "Move up")) {
                    model.config.movePinnedSearchResult(key, by: -1, for: query)
                }
                IconButton(symbol: "chevron.down", help: Loc.t("Weiter nach unten", "Move down")) {
                    model.config.movePinnedSearchResult(key, by: 1, for: query)
                }
                IconButton(symbol: "pin.slash", help: Loc.t("Nicht mehr anpinnen", "Unpin")) {
                    model.config.unpinSearchResult(key, for: query)
                }
            } else {
                IconButton(symbol: "pin", help: Loc.t("Bei dieser Suche ganz oben zeigen", "Show first for this search")) {
                    model.config.pinSearchResult(key, for: query)
                }
            }
            IconButton(symbol: "eye.slash", help: Loc.t("Bei dieser Suche nie zeigen", "Never show for this search")) {
                model.config.hideSearchResult(key, for: query)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 50)
        .background(isPinned ? Color.accent.opacity(0.06) : .clear)
    }

    @ViewBuilder
    private func hiddenSection(_ rule: SearchRule?) -> some View {
        if let hidden = rule?.hidden, !hidden.isEmpty {
            let names = itemsByKey
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionLabel(text: Loc.t("Ausgeblendet", "Hidden"))
                ForEach(hidden, id: \.self) { key in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "eye.slash").font(.system(size: 11)).foregroundColor(DS.textTertiary).frame(width: 18)
                        Text(names[key]?.name ?? UsageStats.readableName(key)).font(DS.Font.body).foregroundColor(DS.textSecondary).strikethrough()
                        Spacer()
                        Button(Loc.t("Wieder zeigen", "Show again")) { model.config.unhideSearchResult(key, for: query) }
                            .buttonStyle(.borderless).font(DS.Font.caption)
                    }
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.canvas.opacity(0.5))
            .hairline(.top)
        }
    }

    // MARK: Rules

    private var rulesColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionLabel(text: Loc.t("Deine Regeln", "Your rules"))
            if model.config.searchRules.isEmpty {
                Text(Loc.t("Noch keine. Pinne oder blende links einen Treffer aus, dann entsteht eine Regel.",
                           "None yet. Pin or hide a result on the left to create one."))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard(padding: DS.Space.m)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.config.searchRules.enumerated()), id: \.element.id) { i, rule in
                        if i > 0 { Rectangle().fill(DS.hairline).frame(height: 1) }
                        ruleRow(rule)
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
            }
        }
    }

    private func ruleRow(_ rule: SearchRule) -> some View {
        let active = effectiveRule?.id == rule.id
        return HStack(spacing: DS.Space.s) {
            Button { query = rule.query } label: {
                HStack(spacing: DS.Space.s) {
                    Text(rule.query)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(active ? .onBrandBlue : DS.textPrimary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.brandBlue : DS.raised))
                    Text([rule.pinned.isEmpty ? nil : Loc.t("\(rule.pinned.count) oben", "\(rule.pinned.count) pinned"),
                          rule.hidden.isEmpty ? nil : Loc.t("\(rule.hidden.count) aus", "\(rule.hidden.count) hidden")]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(DS.Font.caption).foregroundColor(DS.textTertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            IconButton(symbol: "trash", help: Loc.t("Regel löschen", "Delete rule")) { model.config.removeSearchRule(rule.id) }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 42)
    }
}
