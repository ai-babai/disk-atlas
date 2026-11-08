import Foundation

/// Snapshot-only totals: a folder includes its descendants, even when the list is filtered.
public enum FileTrashSelection {
    public static func roots(in snapshot: Snapshot, selected: Set<Int>) -> [Entry] {
        let entries = selected.filter(snapshot.entries.indices.contains).map { snapshot.entries[$0] }.sorted {
            ($0.path + "/") < ($1.path + "/")
        }
        var roots: [Entry] = []
        for entry in entries {
            if let previous = roots.last, previous.isDirectory, entry.path.hasPrefix(previous.path + "/") { continue }
            roots.append(entry)
        }
        return roots
    }

    public static func bytes(in snapshot: Snapshot, selected: Set<Int>, logical: Bool) -> Int64 {
        roots(in: snapshot, selected: selected).reduce(0) { $0 + (logical ? $1.logicalBytes : $1.bytes) }
    }
}
