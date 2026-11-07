import Foundation

/// A frozen set of omitted direct children, never a filesystem directory.
public struct MapGroup: Equatable, Sendable {
    public let parent: Int
    public let roots: [Int]
    public let bytes: Int64
    public var title: String { L10n.text("Ещё \(roots.count)") }
    public init(snapshot: Snapshot, parent: Int, visible: Set<Int>, logical: Bool) {
        self.parent = parent
        roots = snapshot.entries[parent].children.filter { !visible.contains($0) }
        bytes = roots.reduce(0) { $0 + (logical ? snapshot.entries[$1].logicalBytes : snapshot.entries[$1].bytes) }
    }
}
