import AtlasCore
import SwiftUI

/// Follow only the selected branch through the same bounded rectangles used for drawing.
enum MapSelectionGeometry {
    static func target(_ tiles: [MapTile], ancestors: Set<Int>, hasArea: Bool) -> MapTile? {
        guard !ancestors.isEmpty else { return nil }
        return tiles.first { ancestors.contains($0.id) } ?? (hasArea ? tiles.first { $0.id < 0 } : nil)
    }

    static func highlight(
        index: PresentationIndex, parent: Int, selection: Int, logical: Bool, ancestors: Set<Int>, hasArea: Bool,
        bounds: CGRect, depth: Int = 0
    ) -> CGRect? {
        let entry = index.snapshot.entries[parent]
        let tiles = TreemapLayout.tiles(
            index.children(of: parent, logical: logical, limit: 40), logical: logical, in: bounds, limit: 40,
            totalCount: entry.children.count, totalBytes: logical ? entry.logicalBytes : entry.bytes)
        guard let tile = target(tiles, ancestors: ancestors, hasArea: hasArea) else { return nil }
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        guard rect.width > 1, rect.height > 1 else { return nil }
        if tile.id == selection { return rect }
        let node = tile.id >= 0 ? index.snapshot.entries[tile.id] : nil
        if let interior = NestedMapGeometry.childBounds(rect, entry: node, depth: depth), let node,
            let nested = highlight(
                index: index, parent: node.id, selection: selection, logical: logical, ancestors: ancestors,
                hasArea: hasArea, bounds: interior, depth: depth + 1)
        {
            return nested
        }
        return rect
    }
}
