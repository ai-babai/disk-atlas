import AppKit
import AtlasCore

/// Selection is immediate and never navigates. Activation requires a second
/// click on the same entry; aggregate tiles select a temporary list scope.
struct MapInteraction {
    enum Action: Equatable {
        case select(Int)
        case activate(Int)
        case group(MapGroup)
        case none
    }
    private struct Hit {
        let index: ObjectIdentifier
        let id: Int
        let point: CGPoint
        let time: TimeInterval
    }
    private var previous: Hit?

    mutating func action(target: MapTarget, index: PresentationIndex, point: CGPoint, time: TimeInterval) -> Action {
        if case .aggregate(let group) = target {
            previous = nil
            return .group(group)
        }
        guard case .entry(let id) = target else {
            previous = nil
            return .none
        }
        if let hit = previous, hit.id == id, hit.index == ObjectIdentifier(index),
            time - hit.time < NSEvent.doubleClickInterval, hypot(point.x - hit.point.x, point.y - hit.point.y) < 5
        {
            previous = nil
            return .activate(hit.id)
        }
        previous = Hit(index: ObjectIdentifier(index), id: id, point: point, time: time)
        return .select(id)
    }
}

enum MapHitTesting {
    static func group(_ tiles: [MapTile], parent: Int, index: PresentationIndex, logical: Bool) -> MapGroup {
        MapGroup(snapshot: index.snapshot, parent: parent, visible: Set(tiles.map(\.id)), logical: logical)
    }
    static func target(
        _ tile: MapTile, siblings: [MapTile], parent: Int, point: CGPoint, index: PresentationIndex, logical: Bool
    ) -> MapTarget {
        guard tile.id >= 0 else { return .aggregate(group(siblings, parent: parent, index: index, logical: logical)) }
        let entry = index.snapshot.entries[tile.id]
        if entry.isDirectory, tile.rect.width > 60, tile.rect.height > 66 {
            let bounds = CGRect(x: 5, y: 40, width: max(0, tile.rect.width - 13), height: max(0, tile.rect.height - 48))
            if bounds.contains(point) {
                return NestedMapGeometry.target(
                    index: index, parent: entry.id, logical: logical, bounds: bounds, point: point) ?? .entry(entry.id)
            }
        }
        return .entry(entry.id)
    }
    static func target(_ tiles: [MapTile], parent: Int, point: CGPoint, index: PresentationIndex, logical: Bool)
        -> MapTarget
    {
        for tile in tiles {
            let frame = tile.rect.insetBy(dx: 1.5, dy: 1.5)
            if frame.contains(point) {
                return target(
                    tile, siblings: tiles, parent: parent,
                    point: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), index: index, logical: logical)
            }
        }
        return .none
    }
}
