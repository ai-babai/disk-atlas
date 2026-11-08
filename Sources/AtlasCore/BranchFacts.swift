import Foundation

public struct BranchFacts: Sendable {
    public var folders = 0
    public var cloudFiles = 0
    public var cloudMetadataKnown = true
    public var partial = false
    init(entry: Entry, cancelled: Bool) {
        cloudMetadataKnown = entry.cloudOnly != nil
        cloudFiles = !entry.isDirectory && entry.cloudOnly == true ? 1 : 0
        partial = cancelled || (entry.isDirectory && entry.cloudOnly == true)
    }
    mutating func include(_ child: BranchFacts, directory: Bool) {
        folders += child.folders + (directory ? 1 : 0)
        cloudFiles += child.cloudFiles
        cloudMetadataKnown = cloudMetadataKnown && child.cloudMetadataKnown
        partial = partial || child.partial
    }
}

/// Aggregated once off-main; inspector selection never walks the tree or touches the filesystem.
public struct BranchFactsIndex: Sendable {
    private let values: [BranchFacts]
    public init(_ snapshot: Snapshot) {
        let entries = snapshot.entries
        var values = entries.map { BranchFacts(entry: $0, cancelled: snapshot.cancelled) }
        for id in Self.partialEntries(snapshot) { values[id].partial = true }
        for entry in entries.reversed() {
            guard let parent = entry.parent else { continue }
            values[parent].include(values[entry.id], directory: entry.isDirectory)
        }
        if snapshot.issueCount > 0, !values.isEmpty { values[0].partial = true }
        self.values = values
    }
    private static func partialEntries(_ snapshot: Snapshot) -> Set<Int> {
        guard !snapshot.issues.isEmpty else { return [] }
        let paths = Dictionary(snapshot.entries.map { ($0.path, $0.id) }, uniquingKeysWith: { first, _ in first })
        return Set(snapshot.issues.compactMap { nearestParent($0.path, paths: paths) })
    }
    private static func nearestParent(_ path: String, paths: [String: Int]) -> Int? {
        var current = path
        while true {
            if let id = paths[current] { return id }
            if current == "/" { return nil }
            current = (current as NSString).deletingLastPathComponent
            if current.isEmpty { return nil }
        }
    }
    public func facts(for id: Int) -> BranchFacts? { values.indices.contains(id) ? values[id] : nil }
}
