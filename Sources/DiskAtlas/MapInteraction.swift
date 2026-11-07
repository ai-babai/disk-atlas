import AppKit
import AtlasCore

/// Respond to the first click immediately. The second click keeps the original
/// target even if revealing its parent has already changed the visible map.
struct MapInteraction {
    enum Action: Equatable {
        case select(Int)
        case activate(Int)
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
        if let hit = previous, hit.index == ObjectIdentifier(index), time - hit.time < NSEvent.doubleClickInterval,
            hypot(point.x - hit.point.x, point.y - hit.point.y) < 5
        {
            previous = nil
            return .activate(hit.id)
        }
        guard case .entry(let id) = target else {
            previous = nil
            return .none
        }
        previous = Hit(index: ObjectIdentifier(index), id: id, point: point, time: time)
        return .select(id)
    }
}

enum MapHitTesting {
    static func target(_ tile: MapTile, point: CGPoint, index: PresentationIndex, logical: Bool) -> MapTarget {
        guard tile.id >= 0 else { return .aggregate }
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
    static func target(_ tiles: [MapTile], point: CGPoint, index: PresentationIndex, logical: Bool) -> MapTarget {
        for tile in tiles {
            let frame = tile.rect.insetBy(dx: 1.5, dy: 1.5)
            if frame.contains(point) {
                return target(
                    tile, point: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), index: index,
                    logical: logical)
            }
        }
        return .aggregate
    }
}
