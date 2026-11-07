import Foundation

public enum ViewFilter {
    /// Stable IDs keep navigation/selection valid. Only the derived view changes.
    public static func apply(_ snapshot: Snapshot, options: DuplicateOptions) throws -> Snapshot {
        var result = snapshot
        for id in result.entries.indices.reversed() {
            if id % 1024 == 0 { try Task.checkCancellation() }
            if result.entries[id].isDirectory {
                let children = result.entries[id].children.filter { result.entries[$0].fileCount > 0 }
                result.entries[id].children = children
                result.entries[id].bytes = children.reduce(0) { $0 + result.entries[$1].bytes }
                result.entries[id].logicalBytes = children.reduce(0) { $0 + result.entries[$1].logicalBytes }
                result.entries[id].fileCount = children.reduce(0) { $0 + result.entries[$1].fileCount }
            } else {
                let file = result.entries[id]
                let match =
                    file.logicalBytes >= options.minimumBytes
                    && (options.maximumBytes.map { file.logicalBytes <= $0 } ?? true)
                    && options.matchesDate(file.modified)
                if !match {
                    result.entries[id].bytes = 0
                    result.entries[id].logicalBytes = 0
                    result.entries[id].fileCount = 0
                }
            }
        }
        return result
    }
}
