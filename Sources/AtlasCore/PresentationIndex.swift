import Foundation

public enum EntrySort: String, CaseIterable, Sendable { case name, created, modified, size, share }

public struct KindTotal: Sendable, Identifiable {
    public var kind: FileKind
    public var bytes: Int64
    public var id: FileKind { kind }
}

/// Immutable indexes built off the UI thread once per snapshot.
public final class PresentationIndex: Sendable {
    public let snapshot: Snapshot
    private let allocatedChildren: [Int: [Int]]
    private let logicalChildren: [Int: [Int]]
    private let traversal: [Int]
    private let ranges: [Int: Range<Int>]
    private let allocatedKinds: [Int: [KindTotal]]
    private let logicalKinds: [Int: [KindTotal]]

    public init(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        let entries = snapshot.entries
        func sorted(_ ids: [Int], logical: Bool) -> [Int] {
            ids.sorted {
                let a = logical ? entries[$0].logicalBytes : entries[$0].bytes
                let b = logical ? entries[$1].logicalBytes : entries[$1].bytes
                return a == b ? entries[$0].path < entries[$1].path : a > b
            }
        }
        var physical: [Int: [Int]] = [:], logical: [Int: [Int]] = [:]
        for entry in entries where entry.isDirectory {
            physical[entry.id] = sorted(entry.children, logical: false)
            logical[entry.id] = sorted(entry.children, logical: true)
        }
        allocatedChildren = physical; logicalChildren = logical

        var positions = [Int](repeating: 0, count: entries.count)
        var ranges: [Int: Range<Int>] = [:]
        var traversal: [Int] = []
        traversal.reserveCapacity(entries.count)
        var cursor = 0
        var stack: [(Int, Bool)] = [(0, false)]
        while let (id, exiting) = stack.popLast() {
            if exiting { ranges[id] = (positions[id] + 1)..<cursor; continue }
            positions[id] = cursor; traversal.append(id); cursor += 1
            if entries[id].isDirectory {
                stack.append((id, true))
                for child in entries[id].children.reversed() { stack.append((child, false)) }
            }
        }
        self.traversal = traversal; self.ranges = ranges

        var a: [Int: [FileKind: Int64]] = [:], l: [Int: [FileKind: Int64]] = [:]
        for entry in entries.reversed() where entry.fileCount > 0 {
            guard let parent = entry.parent else { continue }
            if entry.isDirectory {
                for (kind, bytes) in a[entry.id] ?? [:] { a[parent, default: [:]][kind, default: 0] += bytes }
                for (kind, bytes) in l[entry.id] ?? [:] { l[parent, default: [:]][kind, default: 0] += bytes }
            } else {
                a[parent, default: [:]][entry.kind, default: 0] += entry.bytes
                l[parent, default: [:]][entry.kind, default: 0] += entry.logicalBytes
            }
        }
        allocatedKinds = a.mapValues { $0.map { KindTotal(kind: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes } }
        logicalKinds = l.mapValues { $0.map { KindTotal(kind: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes } }
    }

    public func children(of id: Int, logical: Bool, limit: Int = .max) -> [Entry] {
        ((logical ? logicalChildren[id] : allocatedChildren[id]) ?? []).prefix(limit).map { snapshot.entries[$0] }
    }

    public func totals(of id: Int, logical: Bool) -> [KindTotal] {
        (logical ? logicalKinds[id] : allocatedKinds[id]) ?? []
    }

    public func rows(folder: Int, logical: Bool, query: String, kind: FileKind?, filesOnly: Bool, limit: Int = 1000) -> (entries: [Entry], count: Int) {
        rows(folder: folder, logical: logical, query: query, kinds: kind.map { [$0] } ?? [], filesOnly: filesOnly, limit: limit)
    }

    public func rows(folder: Int, logical: Bool, query: String, kinds: Set<FileKind>, filesOnly: Bool, limit: Int = 1000, sort: EntrySort = .size, descending: Bool = true, including: Int? = nil) -> (entries: [Entry], count: Int) {
        if including == nil && query.isEmpty && kinds.isEmpty && !filesOnly && (sort == .size || sort == .share) && descending {
            let ids = (logical ? logicalChildren[folder] : allocatedChildren[folder]) ?? []
            return (ids.prefix(limit).map { snapshot.entries[$0] }, ids.count)
        }
        let direct = query.isEmpty && kinds.isEmpty && !filesOnly
        let candidates = direct ? ArraySlice((allocatedChildren[folder] ?? [])) : ranges[folder].map { traversal[$0] } ?? []
        // A bounded heap finds the top visible results without sorting millions
        // of descendants. DFS ranges avoid scanning unrelated branches.
        var heap: [Int] = []
        heap.reserveCapacity(limit)
        var count = 0
        func before(_ a: Entry, _ b: Entry) -> Bool {
            let order: ComparisonResult
            switch sort {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .created:
                if a.created == nil || b.created == nil {
                    if (a.created == nil) != (b.created == nil) { return a.created != nil }
                }
                let x = a.created ?? .distantPast, y = b.created ?? .distantPast
                order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            case .modified:
                order = a.modified == b.modified ? .orderedSame : a.modified < b.modified ? .orderedAscending : .orderedDescending
            case .size, .share:
                let x = logical ? a.logicalBytes : a.bytes, y = logical ? b.logicalBytes : b.bytes
                order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            }
            return order == .orderedSame ? a.path < b.path : descending ? order == .orderedDescending : order == .orderedAscending
        }
        func worse(_ a: Int, _ b: Int) -> Bool { before(snapshot.entries[b], snapshot.entries[a]) }
        for (offset, id) in candidates.enumerated() {
            if offset % 1024 == 0 && Task.isCancelled { break }
            let entry = snapshot.entries[id]
            if filesOnly && entry.isDirectory { continue }
            if !kinds.isEmpty && !kinds.contains(entry.kind) { continue }
            if !query.isEmpty && !entry.name.localizedCaseInsensitiveContains(query) { continue }
            count += 1
            if heap.count < limit {
                heap.append(id)
                var child = heap.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    if !worse(heap[child], heap[parent]) { break }
                    heap.swapAt(child, parent); child = parent
                }
            } else if limit > 0 && worse(heap[0], id) {
                heap[0] = id
                var parent = 0
                while parent * 2 + 1 < heap.count {
                    var child = parent * 2 + 1
                    if child + 1 < heap.count && worse(heap[child + 1], heap[child]) { child += 1 }
                    if !worse(heap[child], heap[parent]) { break }
                    heap.swapAt(child, parent); parent = child
                }
            }
        }
        // A map hit must remain visible even outside the bounded first page.
        if direct, limit > 0, let id = including, snapshot.entries.indices.contains(id),
           snapshot.entries[id].parent == folder, snapshot.entries[folder].children.contains(id), !heap.contains(id) {
            if heap.count == limit { heap.removeFirst() }
            heap.append(id)
        }
        let result = heap.sorted { worse($1, $0) }.map { snapshot.entries[$0] }
        return (result, count)
    }
}
