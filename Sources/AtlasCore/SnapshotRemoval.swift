import Foundation

extension Snapshot {
    /// Prune moved branches and keep the current snapshot valid for export/reopen.
    public func removingFilePaths(_ paths: Set<String>) -> Snapshot {
        var removed = Set<Int>()
        for entry in entries {
            if paths.contains(entry.path) || entry.parent.map({ removed.contains($0) }) == true {
                removed.insert(entry.id)
            }
        }
        var value = self
        value.entries = compactEntries(removing: removed)
        for id in value.entries.indices.reversed() where value.entries[id].isDirectory { value.recount(id) }
        return value
    }
    private func compactEntries(removing removed: Set<Int>) -> [Entry] {
        var mapping = [Int](repeating: -1, count: entries.count)
        var result: [Entry] = []
        for entry in entries where entry.id == 0 || !removed.contains(entry.id) {
            mapping[entry.id] = result.count
            result.append(entry)
        }
        for id in result.indices {
            result[id].id = id
            result[id].parent = result[id].parent.map { mapping[$0] }
            result[id].children = result[id].children.map { mapping[$0] }.filter { $0 >= 0 }
        }
        return result
    }
    private mutating func recount(_ id: Int) {
        let children = entries[id].children.map { entries[$0] }
        entries[id].bytes = children.reduce(0) { $0 + $1.bytes }
        entries[id].logicalBytes = children.reduce(0) { $0 + $1.logicalBytes }
        entries[id].fileCount = children.reduce(0) { $0 + $1.fileCount }
    }
}
