import AtlasCore
import SwiftUI

struct MapTile: Identifiable {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            if let index = store.index {
                let snapshot = index.snapshot
                let children = index.children(of: store.folderID, logical: store.logical, limit: 60)
                let tiles = TreemapLayout.tiles(
                    children, logical: store.logical, in: CGRect(origin: .zero, size: geometry.size),
                    totalCount: snapshot.entries[store.folderID].children.count,
                    totalBytes: store.size(snapshot.entries[store.folderID]))
                ZStack(alignment: .topLeading) {
                    Palette.soft
                    if tiles.isEmpty {
                        ContentUnavailableView(
                            L10n.text("Нет занятых блоков"), systemImage: "square.dashed",
                            description: Text(L10n.text("Папка пуста или данные недоступны.")))
                    }
                    ForEach(tiles) { tile in
                        tileView(tile, snapshot: snapshot, index: index).frame(
                            width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3)
                        ).position(x: tile.rect.midX, y: tile.rect.midY)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    @ViewBuilder private func tileView(_ tile: MapTile, snapshot: Snapshot, index: PresentationIndex) -> some View {
        let entry = tile.id >= 0 ? snapshot.entries[tile.id] : nil
        let isFolder = entry?.isDirectory == true
        let selected = store.selection == tile.id
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(
                isFolder ? Palette.mark : (entry?.kind.tint ?? FileKind.other.tint).opacity(0.68))
            if isFolder, let entry, tile.rect.width > 60, tile.rect.height > 66 {
                NestedMapArtwork(
                    index: index, parent: entry.id, logical: store.logical, language: store.language,
                    selection: store.selection
                ).equatable().allowsHitTesting(false)
            }
            if tile.rect.width > 45 && tile.rect.height > 28 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tile.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if tile.rect.height > 42 {
                        Text(byteString(tile.bytes)).font(.system(size: 10, design: .monospaced)).lineLimit(1).opacity(
                            0.8)
                    }
                }.padding(8).foregroundStyle(isFolder ? Palette.ink : Color.black.opacity(0.85))
            }
            RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Palette.ink : Color.clear, lineWidth: 2)
        }.clipped().contentShape(Rectangle()).gesture(
            SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture()).onEnded { value in
                switch value {
                case .first(let tap):
                    if case .entry(let id) = target(tile, point: tap.location, snapshot: snapshot, index: index) {
                        store.activate(id)
                    }
                case .second(let tap):
                    if case .entry(let id) = target(tile, point: tap.location, snapshot: snapshot, index: index) {
                        store.selectFromMap(id)
                    }
                }
            }
        ).help(
            "\(tile.name) · \(byteString(tile.bytes))" + (isFolder ? L10n.text("\nДвойной щелчок — открыть папку") : "")
        ).accessibilityElement(children: .ignore).accessibilityLabel("\(tile.name), \(byteString(tile.bytes))")
            .accessibilityAddTraits(.isButton).animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
            .accessibilityAction { if let entry { store.selectFromMap(entry.id) } }.accessibilityAction(
                named: L10n.text("Открыть папку")
            ) { if let entry { store.navigate(entry.id) } }.contextMenu {
                if let entry {
                    if entry.isDirectory { Button(L10n.text("Открыть папку")) { store.navigate(entry.id) } }
                    Button(L10n.text("Показать в Finder")) { store.reveal(entry) }
                    Button(L10n.text("Скопировать путь")) { store.copy(entry.path) }
                }
            }
    }

    private func target(_ tile: MapTile, point: CGPoint, snapshot: Snapshot, index: PresentationIndex) -> MapTarget {
        guard tile.id >= 0 else { return .aggregate }
        let entry = snapshot.entries[tile.id]
        if entry.isDirectory, tile.rect.width > 60, tile.rect.height > 66 {
            let bounds = CGRect(x: 5, y: 40, width: max(0, tile.rect.width - 13), height: max(0, tile.rect.height - 48))
            if bounds.contains(point) {
                return NestedMapGeometry.target(
                    index: index, parent: entry.id, logical: store.logical, bounds: bounds, point: point)
                    ?? .entry(entry.id)
            }
        }
        return .entry(entry.id)
    }
}

enum MapTarget: Equatable {
    case entry(Int)
    case aggregate
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
            guard tile.id >= 0 else { return .aggregate }
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
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index === rhs.index && lhs.parent == rhs.parent && lhs.logical == rhs.logical
            && lhs.language == rhs.language && lhs.selection == rhs.selection
    }
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let interior = CGRect(x: 5, y: 40, width: max(0, size.width - 10), height: max(0, size.height - 45))
            paintChildren(snapshot: index.snapshot, parent: parent, bounds: interior, depth: 0, context: &context)
        }
    }
    private func paintChildren(
        snapshot: Snapshot, parent: Int, bounds: CGRect, depth: Int, context: inout GraphicsContext
    ) {
        let tiles = TreemapLayout.tiles(
            index.children(of: parent, logical: logical, limit: 40), logical: logical, in: bounds, limit: 40,
            totalCount: snapshot.entries[parent].children.count,
            totalBytes: logical ? snapshot.entries[parent].logicalBytes : snapshot.entries[parent].bytes)
        for tile in tiles {
            let rect = tile.rect.insetBy(dx: 1, dy: 1)
            guard rect.width > 1, rect.height > 1 else { continue }
            let node = tile.id >= 0 ? snapshot.entries[tile.id] : nil
            let color = node?.kind.tint ?? FileKind.other.tint
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.62)))
            let labelHeight = NestedMapGeometry.labelHeight(rect)
            if labelHeight > 0 {
                var clipped = context
                clipped.clip(to: Path(CGRect(x: rect.minX + 4, y: rect.minY + 3, width: rect.width - 8, height: 14)))
                clipped.draw(
                    Text(tile.name).font(.system(size: 9, weight: .medium)).foregroundColor(.black.opacity(0.8)),
                    at: CGPoint(x: rect.minX + 4, y: rect.minY + 3), anchor: .topLeading)
            }
            if let childBounds = NestedMapGeometry.childBounds(rect, entry: node, depth: depth), let node {
                paintChildren(
                    snapshot: snapshot, parent: node.id, bounds: childBounds, depth: depth + 1, context: &context)
            }
            if tile.id == selection {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 2), with: .color(Palette.ink),
                    lineWidth: 2)
            }
        }
    }
}
