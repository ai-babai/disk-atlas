import AtlasCore
import SwiftUI

struct MapTile: Identifiable, Equatable {
    var id: Int
    var name: String
    var bytes: Int64
    var rect: CGRect = .zero
}

enum TreemapLayout {
    static func tiles(
        _ entries: [Entry], logical: Bool, in bounds: CGRect, limit: Int = 60, totalCount: Int? = nil,
        totalBytes: Int64? = nil
    ) -> [MapTile] {
        let sorted = entries.filter { (logical ? $0.logicalBytes : $0.bytes) > 0 }.sorted {
            (logical ? $0.logicalBytes : $0.bytes) > (logical ? $1.logicalBytes : $1.bytes)
        }
        var items = sorted.prefix(limit).map {
            MapTile(id: $0.id, name: $0.name, bytes: logical ? $0.logicalBytes : $0.bytes)
        }
        let remainingCount = (totalCount ?? sorted.count) - items.count
        let remainder =
            (totalBytes ?? sorted.reduce(Int64(0)) { $0 + (logical ? $1.logicalBytes : $1.bytes) })
            - items.reduce(Int64(0)) { $0 + $1.bytes }
        if remainingCount > 0 && remainder > 0 {
            items.append(MapTile(id: -1, name: L10n.text("Ещё \(remainingCount)"), bytes: remainder))
        }
        guard !items.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        let total = items.reduce(0.0) { $0 + Double($1.bytes) }
        let scale = bounds.width * bounds.height / total
        var remaining = bounds
        var result: [MapTile] = []
        var cursor = 0
        func worst(_ areas: [Double], _ side: Double) -> Double {
            let sum = areas.reduce(0, +)
            guard let low = areas.min(), let high = areas.max(), low > 0, side > 0 else { return .infinity }
            return max(side * side * high / (sum * sum), sum * sum / (side * side * low))
        }
        while cursor < items.count {
            let side = min(remaining.width, remaining.height)
            var row = [items[cursor]]
            var areas = [Double(items[cursor].bytes) * scale]
            cursor += 1
            while cursor < items.count {
                let next = Double(items[cursor].bytes) * scale
                if worst(areas + [next], side) > worst(areas, side) { break }
                areas.append(next)
                row.append(items[cursor])
                cursor += 1
            }
            let area = areas.reduce(0, +)
            if remaining.width >= remaining.height {
                let width = area / max(remaining.height, 0.0001)
                var y = remaining.minY
                for (index, var item) in row.enumerated() {
                    let height = areas[index] / max(width, 0.0001)
                    item.rect = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    result.append(item)
                    y += height
                }
                remaining.origin.x += width
                remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = area / max(remaining.width, 0.0001)
                var x = remaining.minX
                for (index, var item) in row.enumerated() {
                    let width = areas[index] / max(height, 0.0001)
                    item.rect = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    result.append(item)
                    x += width
                }
                remaining.origin.y += height
                remaining.size.height = max(0, remaining.height - height)
            }
        }
        return result
    }
}

struct TreemapView: View {
    @ObservedObject var store: AtlasStore
    var body: some View {
        if let index = store.index {
            TreemapSurface(
                index: index, folder: store.folderID, logical: store.logical, language: store.language,
                selection: store.mapHighlight, duplicateFocus: store.visibleDuplicateFocus, store: store
            ).equatable()
        }
    }
}

/// Progress, search, history and panel updates do not invalidate the map.
private struct TreemapSurface: View, Equatable {
    let index: PresentationIndex
    let folder: Int
    let logical: Bool
    let language: String
    let selection: Int?
    let duplicateFocus: DuplicateMapFocus?
    let store: AtlasStore
    @State private var interaction = MapInteraction()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index === rhs.index && lhs.folder == rhs.folder && lhs.logical == rhs.logical
            && lhs.language == rhs.language && lhs.selection == rhs.selection
            && lhs.duplicateFocus === rhs.duplicateFocus
    }
    var body: some View {
        GeometryReader { geometry in
            let entry = index.snapshot.entries[folder]
            let tiles = TreemapLayout.tiles(
                index.children(of: folder, logical: logical, limit: 60), logical: logical,
                in: CGRect(origin: .zero, size: geometry.size), totalCount: entry.children.count,
                totalBytes: logical ? entry.logicalBytes : entry.bytes)
            let ancestors = index.mapSelectionAncestors(selection, within: folder)
            let hasArea =
                selection.map {
                    logical ? index.snapshot.entries[$0].logicalBytes > 0 : index.snapshot.entries[$0].bytes > 0
                } ?? false
            let focused = MapSelectionGeometry.target(tiles, ancestors: ancestors, hasArea: hasArea)?.id
            let detail = duplicateFocus?.detail(in: folder, tiles: tiles)
            ZStack(alignment: .topLeading) {
                Palette.soft
                if tiles.isEmpty {
                    ContentUnavailableView(
                        L10n.text("Нет занятых блоков"), systemImage: "square.dashed",
                        description: Text(L10n.text("Папка пуста или данные недоступны.")))
                }
                ForEach(tiles) { tile in
                    tileView(tile, siblings: tiles, focused: focused, detail: detail).frame(
                        width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3)
                    ).position(x: tile.rect.midX, y: tile.rect.midY)
                }
                if detail == .overview, let duplicateFocus {
                    DuplicateTileHighlight(copies: duplicateFocus.counts[folder, default: 0], radius: 9)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle()).gesture(
                SpatialTapGesture().onEnded { tap in
                    let target = MapHitTesting.target(
                        tiles, parent: folder, point: tap.location, index: index, logical: logical)
                    switch interaction.action(
                        target: target, index: index, point: tap.location, time: ProcessInfo.processInfo.systemUptime)
                    {
                    case .select(let id): store.selectFromMap(id)
                    case .activate(let id): store.activate(id)
                    case .group(let group): store.selectMapGroup(group)
                    case .none: store.clearMapSelection()
                    }
                })
        }.onChange(of: selection) { _, value in if value == nil { interaction = MapInteraction() } }
    }

    private func tileView(_ tile: MapTile, siblings: [MapTile], focused: Int?, detail: DuplicateMapFocus.Detail?)
        -> some View
    {
        TreemapTile(
            tile: tile, index: index, logical: logical, language: language,
            selection: focused == tile.id ? selection : nil, duplicateFocus: detail == .overview ? nil : duplicateFocus,
            duplicateCopies: detail == .overview
                ? 0 : duplicateFocus?.copies(in: tile, parent: folder, siblings: siblings) ?? 0,
            coarseDuplicates: detail == .folders, parent: folder, siblings: siblings, store: store
        ).equatable()
    }

}

private struct TreemapTile: View, Equatable {
    let tile: MapTile
    let index: PresentationIndex
    let logical: Bool
    let language: String
    let selection: Int?
    let duplicateFocus: DuplicateMapFocus?
    let duplicateCopies: Int
    let coarseDuplicates: Bool
    let parent: Int
    let siblings: [MapTile]
    let store: AtlasStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var entry: Entry? { tile.id >= 0 ? index.snapshot.entries[tile.id] : nil }
    private var isFolder: Bool { entry?.isDirectory == true }
    private var showsChildren: Bool { isFolder && tile.rect.width > 60 && tile.rect.height > 66 }
    private var selected: Bool { selection != nil && (selection == tile.id || !showsChildren) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tile == rhs.tile && lhs.index === rhs.index && lhs.logical == rhs.logical && lhs.language == rhs.language
            && lhs.selection == rhs.selection && lhs.duplicateFocus === rhs.duplicateFocus
            && lhs.duplicateCopies == rhs.duplicateCopies && lhs.coarseDuplicates == rhs.coarseDuplicates
    }
    var body: some View {
        artwork.clipped().contentShape(Rectangle()).help(
            "\(tile.name) · \(byteString(tile.bytes))" + (isFolder ? L10n.text("\nДвойной щелчок — открыть папку") : "")
        ).accessibilityElement(children: .ignore).accessibilityLabel("\(tile.name), \(byteString(tile.bytes))")
            .accessibilityAddTraits(.isButton).animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
            .accessibilityAction {
                if let entry {
                    store.selectFromMap(entry.id)
                } else {
                    store.selectMapGroup(MapHitTesting.group(siblings, parent: parent, index: index, logical: logical))
                }
            }.accessibilityActions {
                if let entry, entry.isDirectory { Button(L10n.text("Открыть папку")) { store.navigate(entry.id) } }
            }.contextMenu { actions }
    }
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(
                isFolder ? MapPalette.folder() : MapPalette.fill(entry?.kind ?? .other))
            if isFolder { RoundedRectangle(cornerRadius: 5).strokeBorder(MapPalette.folderLine, lineWidth: 1) }
            if showsChildren, let entry {
                NestedMapArtwork(
                    index: index, parent: entry.id, logical: logical, language: language,
                    selection: selected ? nil : selection, duplicateFocus: coarseDuplicates ? nil : duplicateFocus,
                    duplicateCopies: coarseDuplicates ? 0 : duplicateCopies
                ).equatable().allowsHitTesting(false)
            }
            if tile.rect.width > 45 && tile.rect.height > 28 { label }
            RoundedRectangle(cornerRadius: 5).strokeBorder(
                selected ? (isFolder ? Palette.ink : MapPalette.fileText) : Color.clear, lineWidth: 2)
            if duplicateCopies > 0 && (coarseDuplicates || !showsChildren) {
                DuplicateTileHighlight(copies: duplicateCopies, radius: 5)
            }
        }
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if tile.rect.height > 42 {
                Text(byteString(tile.bytes)).font(.system(size: 10, design: .monospaced)).lineLimit(1).opacity(0.8)
            }
        }.padding(8).foregroundStyle(isFolder ? Palette.ink : MapPalette.fileText)
    }
    @ViewBuilder private var actions: some View {
        if let entry {
            if entry.isDirectory { Button(L10n.text("Открыть папку")) { store.navigate(entry.id) } }
            Button(L10n.text("Показать в Finder")) { store.reveal(entry) }
            Button(L10n.text("Скопировать путь")) { store.copy(entry.path) }
        }
    }

}

enum MapTarget: Equatable {
    case entry(Int)
    case aggregate(MapGroup)
    case none
}

enum NestedMapGeometry {
    static func labelHeight(_ rect: CGRect) -> CGFloat { rect.width > 90 && rect.height > 40 ? 17 : 0 }
    static func childBounds(_ rect: CGRect, entry: Entry?, depth: Int) -> CGRect? {
        guard entry?.isDirectory == true, depth < 7, rect.width > 55, rect.height > 35 else { return nil }
        let label = labelHeight(rect)
        return CGRect(
            x: rect.minX + 2, y: rect.minY + label + 2, width: rect.width - 4, height: rect.height - label - 4)
    }
    static func target(
        index: PresentationIndex, parent: Int, logical: Bool, bounds: CGRect, point: CGPoint, depth: Int = 0
    ) -> MapTarget? {
        let snapshot = index.snapshot
        let entry = snapshot.entries[parent]
        let tiles = TreemapLayout.tiles(
            index.children(of: parent, logical: logical, limit: 40), logical: logical, in: bounds, limit: 40,
            totalCount: entry.children.count, totalBytes: logical ? entry.logicalBytes : entry.bytes)
        for tile in tiles {
            let rect = tile.rect.insetBy(dx: 1, dy: 1)
            guard rect.width > 1, rect.height > 1, rect.contains(point) else { continue }
            guard tile.id >= 0 else {
                return .aggregate(MapHitTesting.group(tiles, parent: parent, index: index, logical: logical))
            }
            let child = snapshot.entries[tile.id]
            if let interior = childBounds(rect, entry: child, depth: depth), interior.contains(point) {
                return target(
                    index: index, parent: child.id, logical: logical, bounds: interior, point: point, depth: depth + 1)
                    ?? .entry(child.id)
            }
            return .entry(child.id)
        }
        return nil
    }
}

private struct NestedMapArtwork: View, Equatable {
    let index: PresentationIndex
    let parent: Int
    let logical: Bool
    let language: String
    let selection: Int?
    let duplicateFocus: DuplicateMapFocus?
    let duplicateCopies: Int
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index === rhs.index && lhs.parent == rhs.parent && lhs.logical == rhs.logical
            && lhs.language == rhs.language && lhs.selection == rhs.selection
            && lhs.duplicateFocus === rhs.duplicateFocus && lhs.duplicateCopies == rhs.duplicateCopies
    }
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let interior = CGRect(x: 5, y: 40, width: max(0, size.width - 10), height: max(0, size.height - 45))
            let matched = paintChildren(
                snapshot: index.snapshot, parent: parent, bounds: interior, depth: 0, context: &context)
            if duplicateCopies > 0 && !matched {
                DuplicateMapHighlight.draw(
                    CGRect(origin: .zero, size: size), copies: duplicateCopies, radius: 5, context: &context)
            }
            if let selection {
                let node = index.snapshot.entries[selection]
                let rect =
                    MapSelectionGeometry.highlight(
                        index: index, parent: parent, selection: selection, logical: logical,
                        ancestors: index.mapSelectionAncestors(selection, within: parent),
                        hasArea: logical ? node.logicalBytes > 0 : node.bytes > 0, bounds: interior)
                    ?? CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let outline = Path(roundedRect: rect, cornerRadius: 2)
                context.stroke(outline, with: .color(MapPalette.fileText), lineWidth: 3)
                context.stroke(outline, with: .color(Palette.ink), lineWidth: 1.5)
            }
        }
    }
    private func paintChildren(
        snapshot: Snapshot, parent: Int, bounds: CGRect, depth: Int, context: inout GraphicsContext
    ) -> Bool {
        let tiles = TreemapLayout.tiles(
            index.children(of: parent, logical: logical, limit: 40), logical: logical, in: bounds, limit: 40,
            totalCount: snapshot.entries[parent].children.count,
            totalBytes: logical ? snapshot.entries[parent].logicalBytes : snapshot.entries[parent].bytes)
        var matched = false
        for tile in tiles {
            matched = paintTile(tile, siblings: tiles, parent: parent, depth: depth, context: &context) || matched
        }
        return matched
    }
    private func paintTile(
        _ tile: MapTile, siblings: [MapTile], parent: Int, depth: Int, context: inout GraphicsContext
    ) -> Bool {
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        guard rect.width > 1, rect.height > 1 else { return false }
        let node = tile.id >= 0 ? index.snapshot.entries[tile.id] : nil
        let isFolder = node?.isDirectory == true
        let color = isFolder ? MapPalette.folder(depth: depth + 1) : MapPalette.fill(node?.kind ?? .other)
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
        if isFolder {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5),
                with: .color(MapPalette.folderLine), lineWidth: 1)
        }
        paintLabel(tile.name, rect: rect, isFolder: isFolder, context: &context)
        var matched = false
        if let childBounds = NestedMapGeometry.childBounds(rect, entry: node, depth: depth), let node {
            matched = paintChildren(
                snapshot: index.snapshot, parent: node.id, bounds: childBounds, depth: depth + 1, context: &context)
        }
        let copies = duplicateFocus?.copies(in: tile, parent: parent, siblings: siblings) ?? 0
        if copies > 0 && !matched && rect.width > 3 && rect.height > 3 {
            DuplicateMapHighlight.draw(rect, copies: copies, radius: 2, context: &context)
            return true
        }
        return matched
    }
    private func paintLabel(_ name: String, rect: CGRect, isFolder: Bool, context: inout GraphicsContext) {
        guard NestedMapGeometry.labelHeight(rect) > 0 else { return }
        var clipped = context
        clipped.clip(to: Path(CGRect(x: rect.minX + 4, y: rect.minY + 3, width: rect.width - 8, height: 14)))
        clipped.draw(
            Text(name).font(.system(size: 9, weight: .medium)).foregroundColor(
                isFolder ? Palette.ink : MapPalette.fileText), at: CGPoint(x: rect.minX + 4, y: rect.minY + 3),
            anchor: .topLeading)
    }
}
