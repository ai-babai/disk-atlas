import Foundation

public struct ExtensionTotal: Identifiable, Sendable {
    public var suffix: String
    public var bytes: Int64 = 0
    public var count: Int = 0
    public var id: String { suffix }
}

extension PresentationIndex {
    /// Computed only for the expanded category; no per-folder extension index in memory.
    public func extensions(of folder: Int, kind: FileKind, logical: Bool) -> [ExtensionTotal] {
        guard let range = ranges[folder] else { return [] }
        var totals: [String: ExtensionTotal] = [:]
        for (offset, id) in traversal[range].enumerated() {
            if offset % 1024 == 0 && Task.isCancelled { return [] }
            let entry = snapshot.entries[id]
            guard !entry.isDirectory, entry.kind == kind else { continue }
            let key = FileFormat.extensionKey(entry.path)
            var value = totals[key] ?? ExtensionTotal(suffix: key)
            value.bytes += logical ? entry.logicalBytes : entry.bytes
            value.count += 1
            totals[key] = value
        }
        return totals.values.sorted { $0.bytes == $1.bytes ? $0.suffix < $1.suffix : $0.bytes > $1.bytes }
    }
}
