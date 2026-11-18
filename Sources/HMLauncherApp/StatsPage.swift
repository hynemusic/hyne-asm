import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

/// Settings page "Stats": what gets inserted most, plus export / import / reset of the insert counts
/// (they rank search results, so they're worth keeping).
struct StatsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: PluginCatalog
    @State private var summary = UsageSummary(stats: [], total: 0, byKind: [])
    @State private var topCount = 10
    @State private var pendingImport: [String: Int]?
    @State private var confirmReset = false
    @State private var info: String?
    @State private var removing: UsageStat?

    var body: some View {
        PageContainer(title: Loc.t("Statistik", "Stats"),
                      subtitle: Loc.t("Was du am häufigsten einfügst. Diese Zahlen sortieren auch deine Suchergebnisse.",
                                      "What you insert most. These numbers also rank your search results.")) {
            HStack(spacing: DS.Space.s) {
                Button { importFile() } label: { Label(Loc.t("Importieren …", "Import …"), systemImage: "square.and.arrow.down") }
                Button { exportFile() } label: { Label(Loc.t("Exportieren …", "Export …"), systemImage: "square.and.arrow.up") }
                    .disabled(summary.total == 0)
                Button(role: .destructive) { confirmReset = true } label: { Label(Loc.t("Zurücksetzen …", "Reset …"), systemImage: "arrow.counterclockwise") }
                    .disabled(summary.total == 0)
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let info {
                    Label(info, systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundColor(DS.success)
                }
                if summary.total == 0 { emptyState } else {
                    tiles
                    topChart
                    kindCard
                    allList
                }
            }
            .padding(.bottom, DS.Space.l)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UsageStore.didChange)) { _ in refresh() }
        .onReceive(catalog.$items.dropFirst()) { _ in refresh() }
        .confirmationDialog(Loc.t("Zählerstände importieren", "Import insert counts"), isPresented: Binding(
            get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button(Loc.t("Zu meinen hinzufügen", "Add to mine")) { applyImport(replace: false) }
            Button(Loc.t("Meine ersetzen", "Replace mine"), role: .destructive) { applyImport(replace: true) }
        } message: {
            Text(Loc.t("„Hinzufügen“ zählt beide zusammen. „Ersetzen“ sichert deine jetzigen Zahlen vorher als Backup.",
                       "“Add” sums both. “Replace” backs up your current numbers first."))
        }
        .confirmationDialog(Loc.t("„\(removing?.name ?? "")“ aus der Statistik entfernen?", "Remove “\(removing?.name ?? "")” from the stats?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(Loc.t("Entfernen", "Remove"), role: .destructive) {
                if let stat = removing {
                    model.usage.remove(stat.key)
                    info = Loc.t("„\(stat.name)“ entfernt.", "Removed “\(stat.name)”.")
                }
                removing = nil
            }
        } message: {
            Text(Loc.t("Sein Zähler (\(removing?.count ?? 0)×) wird gelöscht – in der Suche rutscht es dann nicht mehr nach oben. Das Plugin selbst bleibt.",
                       "Its count (\(removing?.count ?? 0)×) is deleted, so it no longer moves up in search. The plugin itself stays."))
        }
        .confirmationDialog(Loc.t("Statistik zurücksetzen?", "Reset stats?"), isPresented: $confirmReset) {
            Button(Loc.t("Zurücksetzen", "Reset"), role: .destructive) { reset() }
        } message: {
            Text(Loc.t("Alle Zählerstände werden gelöscht, die Suche sortiert dann wieder neutral. Ein Backup landet im App-Ordner.",
                       "All counts are cleared and search goes back to neutral ranking. A backup is saved in the app's folder."))
        }
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundColor(DS.textTertiary)
            Text(Loc.t("Noch nichts eingefügt", "Nothing inserted yet")).font(DS.Font.bodyStrong).foregroundColor(DS.textSecondary)
            Text(Loc.t("Füg Plugins über das Panel oder die Schnellsuche ein – hier siehst du dann, was du am meisten nutzt.",
                       "Insert plugins from the panel or quick search – this page then shows what you use most."))
                .font(DS.Font.caption).foregroundColor(DS.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .dsCard()
    }

    private var tiles: some View {
        HStack(spacing: DS.Space.m) {
            tile(Loc.t("Eingefügt", "Inserts"), "\(summary.total)", symbol: "plus.square.on.square")
            tile(Loc.t("Verschiedene", "Different"), "\(summary.stats.count)", symbol: "square.stack.3d.up")
            tile(Loc.t("Meistgenutzt", "Most used"), summary.stats.first?.name ?? "–", symbol: "crown", small: true)
            tile(Loc.t("Anteil Top 10", "Top 10 share"), "\(Int((summary.topShare(10) * 100).rounded())) %", symbol: "chart.pie")
        }
    }

    private func tile(_ title: String, _ value: String, symbol: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundColor(.accent)
                Text(title.uppercased()).font(DS.Font.sectionLabel).tracking(0.6).foregroundColor(DS.textTertiary)
            }
            Text(value)
                .font(.system(size: small ? 17 : 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 32, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: DS.Space.m)
    }

    private var topChart: some View {
        let top = Array(summary.stats.prefix(topCount))
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack {
                SectionLabel(text: Loc.t("Am häufigsten eingefügt", "Most inserted"))
                Spacer()
                Picker("", selection: $topCount) {
                    Text("Top 10").tag(10)
                    Text("Top 25").tag(25)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            VStack(spacing: 6) {
                ForEach(Array(top.enumerated()), id: \.element.id) { rank, stat in
                    barRow(rank, stat, max: top.first?.count ?? 1)
                }
            }
            legend
        }
        .dsCard()
    }

    /// Name on the left, bar scaled to the most used one, count at the bar's end.
    private func barRow(_ rank: Int, _ stat: UsageStat, max: Int) -> some View {
        HStack(spacing: DS.Space.m) {
            Text("\(rank + 1)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
                .frame(width: 18, alignment: .trailing)
            Text(stat.name).font(DS.Font.body).foregroundColor(DS.textPrimary).lineLimit(1)
                .frame(width: 210, alignment: .leading)
            GeometryReader { geo in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(stat.kind).gradient)
                        .frame(width: Swift.max(6, (geo.size.width - 34) * CGFloat(stat.count) / CGFloat(Swift.max(max, 1))))
                    Text("\(stat.count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundColor(DS.textSecondary)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
        }
        .frame(height: 24)
        .opacity(stat.isAvailable ? 1 : 0.5)
        .help("\(stat.name) · \(stat.kind.title) · \(stat.count)")
    }

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionLabel(text: Loc.t("Nach Art", "By type"))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(summary.byKind, id: \.kind) { part in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(part.kind).gradient)
                            .frame(width: max(4, (geo.size.width - CGFloat(summary.byKind.count - 1) * 2)
                                                * CGFloat(part.count) / CGFloat(max(summary.total, 1))))
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: DS.Space.xl) {
                ForEach(summary.byKind, id: \.kind) { part in
                    HStack(spacing: 6) {
                        Circle().fill(color(part.kind)).frame(width: 8, height: 8)
                        Text(part.kind.title).font(DS.Font.body).foregroundColor(DS.textSecondary)
                        Text("\(percent(part.count)) · \(part.count)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary)
                    }
                }
            }
        }
        .dsCard()
    }

    private var legend: some View {
        HStack(spacing: DS.Space.l) {
            ForEach(summary.byKind, id: \.kind) { part in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(color(part.kind)).frame(width: 10, height: 10)
                    Text(part.kind.title).font(DS.Font.caption).foregroundColor(DS.textTertiary)
                }
            }
        }
    }

    private var allList: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                SectionLabel(text: Loc.t("Alle", "All"))
                Spacer()
                Text(Loc.t("Ausgegraut: nicht mehr in Live gefunden", "Greyed out: no longer found in Live"))
                    .font(DS.Font.caption).foregroundColor(DS.textTertiary)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(summary.stats.enumerated()), id: \.element.id) { rank, stat in
                    if rank > 0 { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 84) }
                    statRow(rank, stat)
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.l).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.hairline))
        }
    }

    private func statRow(_ rank: Int, _ stat: UsageStat) -> some View {
        let tint = Color(label: stat.colorID)
        return HStack(spacing: DS.Space.m) {
            Text("\(rank + 1)").font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary).frame(width: 24, alignment: .trailing)
            Image(systemName: IconCatalog.symbolName(for: stat.iconID))
                .font(.system(size: 12))
                .foregroundColor(tint ?? DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill((tint ?? .ink).opacity(tint == nil ? 0.06 : 0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.name).font(DS.Font.bodyStrong).foregroundColor(DS.textPrimary).lineLimit(1)
                Text(stat.kind.title).font(.system(size: 10.5)).foregroundColor(DS.textTertiary)
            }
            .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: DS.Space.l)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.raised)
                    Capsule().fill(color(stat.kind)).frame(width: geo.size.width * CGFloat(stat.share / max(summary.stats.first?.share ?? 1, 0.0001)))
                }
            }
            .frame(width: 160, height: 6)
            Text(percent(stat.count)).font(DS.Font.caption.monospacedDigit()).foregroundColor(DS.textTertiary).frame(width: 40, alignment: .trailing)
            Text("\(stat.count)").font(DS.Font.bodyStrong.monospacedDigit()).foregroundColor(DS.textPrimary).frame(width: 40, alignment: .trailing)
            IconButton(symbol: "xmark", help: Loc.t("Aus der Statistik entfernen", "Remove from stats")) { removing = stat }
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: 48)
        .opacity(stat.isAvailable ? 1 : 0.5)
    }

    private func percent(_ count: Int) -> String {
        guard summary.total > 0 else { return "0 %" }
        let p = Double(count) / Double(summary.total) * 100
        return p < 1 ? "<1 %" : "\(Int(p.rounded())) %"
    }

    private func color(_ kind: UsageKind) -> Color {
        switch kind {
        case .plugins: return .brandBlue
        case .live: return .brandCoral
        case .maxForLive: return Color(red: 0.25, green: 0.78, blue: 0.70)
        case .presets: return Color(red: 1.0, green: 0.76, blue: 0.32)
        }
    }

    // MARK: Actions

    private func refresh() {
        summary = UsageStats.summarize(model.usage.counts, items: catalog.items, config: model.config)
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: UsageExport.fileExtension) ?? .json]
        panel.nameFieldStringValue = "HYNE ASM " + Loc.t("Statistik", "Stats")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UsageExport(counts: model.usage.counts).data().write(to: url, options: .atomic)
            info = Loc.t("Exportiert: \(url.lastPathComponent)", "Exported: \(url.lastPathComponent)")
        } catch { fail(error) }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: UsageExport.fileExtension) ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImport = try UsageExport.read(Data(contentsOf: url))
        } catch {
            fail(Loc.t("Das ist keine HYNE-ASM-Statistikdatei.", "This is not a HYNE ASM stats file."))
        }
    }

    private func applyImport(replace: Bool) {
        guard let counts = pendingImport else { return }
        pendingImport = nil
        if replace {
            backup()
            model.usage.replaceAll(counts)
        } else {
            model.usage.merge(counts)
        }
        info = Loc.t("\(counts.count) Einträge importiert.", "Imported \(counts.count) entries.")
    }

    private func reset() {
        backup()
        model.usage.reset()
        info = Loc.t("Zurückgesetzt. Backup im App-Ordner gesichert.", "Reset. A backup was saved in the app's folder.")
    }

    /// Before counts are thrown away: a copy next to usage.json ("usage-backup-<date>.hmlusage").
    private func backup() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = UsageStore.defaultURL.deletingLastPathComponent()
            .appendingPathComponent("usage-backup-\(stamp).\(UsageExport.fileExtension)")
        try? UsageExport(counts: model.usage.counts).data().write(to: url, options: .atomic)
    }

    private func fail(_ error: Any) {
        let alert = NSAlert()
        alert.messageText = Loc.t("Hat nicht geklappt", "That didn't work")
        alert.informativeText = (error as? Error)?.localizedDescription ?? "\(error)"
        alert.runModal()
    }
}
