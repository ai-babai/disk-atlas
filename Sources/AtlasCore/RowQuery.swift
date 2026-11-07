import Foundation

/// One bounded ordering/filter operation for ordinary lists and a map group's roots.
struct RowQuery {
    let logical: Bool
    let query: String
    let kinds: Set<FileKind>
    let filesOnly: Bool
    let limit: Int
    let sort: EntrySort
    let descending: Bool

    func before(_ a: Entry, _ b: Entry) -> Bool {
        let order = compare(a, b)
        if order == .orderedSame { return a.path < b.path }
        return descending ? order == .orderedDescending : order == .orderedAscending
    }
    private func compare(_ a: Entry, _ b: Entry) -> ComparisonResult {
        switch sort {
        case .name: return a.name.localizedStandardCompare(b.name)
        case .created: return creationOrder(a.created, b.created)
        case .modified: return a.modified.compare(b.modified)
        case .size, .share:
            let x = logical ? a.logicalBytes : a.bytes
            let y = logical ? b.logicalBytes : b.bytes
            return x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
        }
    }
    private func creationOrder(_ a: Date?, _ b: Date?) -> ComparisonResult {
        if a == nil && b != nil { return descending ? .orderedAscending : .orderedDescending }
        if a != nil && b == nil { return descending ? .orderedDescending : .orderedAscending }
        return (a ?? .distantPast).compare(b ?? .distantPast)
    }
    private func matches(_ entry: Entry) -> Bool {
        if filesOnly && entry.isDirectory { return false }
        if !kinds.isEmpty && !kinds.contains(entry.kind) { return false }
        return query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)
    }
    func select<S: Sequence>(_ candidates: S, entries: [Entry]) -> (entries: [Entry], count: Int)
    where S.Element == Int {
        var heap: [Int] = []
        var count = 0
        for (offset, id) in candidates.enumerated() {
            if offset % 1024 == 0 && Task.isCancelled { break }
            guard matches(entries[id]) else { continue }
            count += 1
            guard limit > 0 else { continue }
            if heap.count < limit {
                heap.append(id)
                siftUp(&heap, entries: entries)
            } else if before(entries[id], entries[heap[0]]) {
                heap[0] = id
                siftDown(&heap, entries: entries)
            }
        }
        return (heap.map { entries[$0] }.sorted(by: before), count)
    }
    private func siftUp(_ heap: inout [Int], entries: [Entry]) {
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            if !before(entries[heap[parent]], entries[heap[child]]) { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }
    private func siftDown(_ heap: inout [Int], entries: [Entry]) {
        var parent = 0
        while parent * 2 + 1 < heap.count {
            var child = parent * 2 + 1
            if child + 1 < heap.count && before(entries[heap[child]], entries[heap[child + 1]]) { child += 1 }
            if !before(entries[heap[parent]], entries[heap[child]]) { break }
            heap.swapAt(child, parent)
            parent = child
        }
    }
}
