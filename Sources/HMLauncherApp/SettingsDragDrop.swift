import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HMLauncherCore

// MARK: - Row drop handling

enum DropSpot: Equatable { case before, after, into }

struct DropMarker: Equatable {
    let id: UUID
    let spot: DropSpot
}

@MainActor
final class DropState: ObservableObject {
    @Published var marker: DropMarker?
}

/// Upper/lower half of a plugin row = before/after it; a folder row takes drops *into* it, except its top edge.
struct RowDropDelegate: DropDelegate {
    let row: SettingsViewRow
    let drop: DropState
    let perform: (DropSpot, [NSItemProvider]) -> Bool

    private func spot(_ info: DropInfo) -> DropSpot {
        let y = info.location.y
        if row.isFolder { return y < 10 ? .before : .into }
        return y < 21 ? .before : .after
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [browserDragType, entriesDragType, .fileURL, .text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let m = DropMarker(id: row.id, spot: spot(info))
        if drop.marker != m { drop.marker = m }
        return DropProposal(operation: info.hasItemsConforming(to: [entriesDragType]) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        if drop.marker?.id == row.id { drop.marker = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let s = spot(info)
        drop.marker = nil
        return perform(s, info.itemProviders(for: [browserDragType, entriesDragType, .fileURL, .text]))
    }
}

/// What the drop delegate needs to know about a row.
struct SettingsViewRow {
    let id: UUID
    let isFolder: Bool
}

/// The entries of the drag in progress (set when it starts, consumed by the drop) — in-process and synchronous.
@MainActor
enum EntryDrag {
    static var ids: [UUID]?
}

/// Drag preview: a small yellow badge with the number of entries being dragged.
struct DragCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(DS.Font.keyCombo)
            .foregroundColor(.onAccent)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.accent))
    }
}

/// The browser selection being dragged (set when the drag starts, taken by the drop).
@MainActor
enum BrowserDrag {
    static var selection: BrowserSelection?
}

/// The category being dragged (set when the drag starts) — in-process and synchronous like `EntryDrag`.
@MainActor
enum CategoryDrag {
    static var id: UUID?
}

struct CategoryMarker: Equatable {
    let id: UUID
    let after: Bool
}

/// Lets every category except Favorites be dragged by its row.
struct CategoryDragSource: ViewModifier {
    let enabled: Bool
    let id: UUID
    let name: String

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                CategoryDrag.id = id
                EntryDrag.ids = nil
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: categoryDragType.identifier, visibility: .ownProcess) { done in
                    done(Data(id.uuidString.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                Text(name)
                    .font(DS.Font.secondaryStrong)
                    .foregroundColor(.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accent))
            }
        } else {
            content
        }
    }
}

/// A category row takes two kinds of drops: another category (reorder: upper half = before, lower half = after)
/// and plugins/entries (they move into this category).
struct CategoryDropDelegate: DropDelegate {
    let category: UUID
    let isFavorites: Bool
    @Binding var marker: CategoryMarker?
    @Binding var entryTarget: UUID?
    let moveCategory: (UUID?) -> Void
    let dropEntries: ([NSItemProvider]) -> Bool

    private func isCategoryDrag(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [categoryDragType]) }

    /// Favorites is always first, so a category dropped on it lands right after it.
    private func after(_ info: DropInfo) -> Bool { isFavorites || info.location.y >= 15 }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [categoryDragType, browserDragType, entriesDragType, .fileURL, .text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isCategoryDrag(info) {
            let m = CategoryMarker(id: category, after: after(info))
            if marker != m { marker = m }
            if entryTarget != nil { entryTarget = nil }
            return DropProposal(operation: .move)
        }
        if entryTarget != category { entryTarget = category }
        return DropProposal(operation: info.hasItemsConforming(to: [entriesDragType]) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        if marker?.id == category { marker = nil }
        if entryTarget == category { entryTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        marker = nil
        entryTarget = nil
        if isCategoryDrag(info) {
            moveCategory(after(info) ? nextCategory : category)
            return true
        }
        return dropEntries(info.itemProviders(for: [browserDragType, entriesDragType, .fileURL, .text]))
    }

    /// Filled in by the list: the category below this one (nil = this is the last one).
    var nextCategory: UUID?
}

/// Which part of the settings browser a group belongs to; the browser draws a label where the part changes.
