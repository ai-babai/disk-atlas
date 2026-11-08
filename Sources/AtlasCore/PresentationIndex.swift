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
    let traversal: [Int]
    let ranges: [Int: Range<Int>]
    private let allocatedKinds: [Int: [KindTotal]]
    private let logicalKinds: [Int: [KindTotal]]

    public let facts: BranchFactsIndex

    public init(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        facts = BranchFactsIndex(snapshot)
        allocatedChildren = Self.childOrders(snapshot.entries, logical: false)
        logicalChildren = Self.childOrders(snapshot.entries, logical: true)
        (traversal, ranges) = Self.traversalIndex(snapshot.entries)
        allocatedKinds = Self.kindTotals(snapshot.entries, logical: false)
        logicalKinds = Self.kindTotals(snapshot.entries, logical: true)
    }
    private static func childOrders(_ entries: [Entry], logical: Bool) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        for entry in entries where entry.isDirectory {
            result[entry.id] = entry.children.sorted {
                let a = logical ? entries[$0].logicalBytes : entries[$0].bytes
                let b = logical ? entries[$1].logicalBytes : entries[$1].bytes
                return a == b ? entries[$0].path < entries[$1].path : a > b
            }
        }
        return result
    }
    private static func traversalIndex(_ entries: [Entry]) -> ([Int], [Int: Range<Int>]) {
        var positions = [Int](repeating: 0, count: entries.count)
        var ranges: [Int: Range<Int>] = [:]
        var traversal: [Int] = []
        traversal.reserveCapacity(entries.count)
        var stack: [(Int, Bool)] = [(0, false)]
        while let (id, exiting) = stack.popLast() {
            if exiting {
                ranges[id] = (positions[id] + 1)..<traversal.count
                continue
            }
            positions[id] = traversal.count
            traversal.append(id)
            if entries[id].isDirectory {
                stack.append((id, true))
                for child in entries[id].children.reversed() { stack.append((child, false)) }
            }
        }
        return (traversal, ranges)
    }
    private static func kindTotals(_ entries: [Entry], logical: Bool) -> [Int: [KindTotal]] {
        var totals: [Int: [FileKind: Int64]] = [:]
        for entry in entries.reversed() where entry.fileCount > 0 {
            guard let parent = entry.parent else { continue }
            if entry.isDirectory {
                for (kind, bytes) in totals[entry.id] ?? [:] { totals[parent, default: [:]][kind, default: 0] += bytes }
            } else {
                totals[parent, default: [:]][entry.kind, default: 0] += logical ? entry.logicalBytes : entry.bytes
            }
        }
        return totals.mapValues { $0.map { KindTotal(kind: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes } }
    }

    public func children(of id: Int, logical: Bool, limit: Int = .max) -> [Entry] {
        ((logical ? logicalChildren[id] : allocatedChildren[id]) ?? []).prefix(limit).map { snapshot.entries[$0] }
    }

    public func totals(of id: Int, logical: Bool) -> [KindTotal] {
        (logical ? logicalKinds[id] : allocatedKinds[id]) ?? []
    }

    public func rows(folder: Int, logical: Bool, query: String, kind: FileKind?, filesOnly: Bool, limit: Int = 1000)
        -> (entries: [Entry], count: Int)
    {
        rows(
            folder: folder, logical: logical, query: query, kinds: kind.map { [$0] } ?? [], filesOnly: filesOnly,
            limit: limit)
    }

    public func rows(
        folder: Int, logical: Bool, query: String, kinds: Set<FileKind>, filesOnly: Bool, limit: Int = 1000,
        sort: EntrySort = .size, descending: Bool = true, including: Int? = nil, groupRoots: [Int]? = nil,
        extensionFilter: String? = nil
    ) -> (entries: [Entry], count: Int) {
        let direct = query.isEmpty && kinds.isEmpty && !filesOnly && extensionFilter == nil
        if let result = defaultRows(
            folder: folder, logical: logical, direct: direct, groupRoots: groupRoots, including: including, sort: sort,
            descending: descending, limit: limit)
        {
            return result
        }
        let candidates = rowCandidates(folder: folder, direct: direct, groupRoots: groupRoots)
        let request = RowQuery(
            logical: logical, query: query, kinds: kinds, filesOnly: filesOnly, limit: limit, sort: sort,
            descending: descending, extensionFilter: extensionFilter?.lowercased())
        var result = request.select(candidates, entries: snapshot.entries)
        if direct, let including, snapshot.entries.indices.contains(including), candidates.contains(including),
            !result.entries.contains(where: { $0.id == including }), limit > 0
        {
            if result.entries.count == limit { result.entries.removeLast() }
            result.entries.append(snapshot.entries[including])
            result.entries.sort(by: request.before)
        }
        return result
    }

    private func defaultRows(
        folder: Int, logical: Bool, direct: Bool, groupRoots: [Int]?, including: Int?, sort: EntrySort,
        descending: Bool, limit: Int
    ) -> (entries: [Entry], count: Int)? {
        guard direct, groupRoots == nil, including == nil, sort == .size || sort == .share, descending else {
            return nil
        }
        let ids = (logical ? logicalChildren[folder] : allocatedChildren[folder]) ?? []
        return (ids.prefix(max(0, limit)).map { snapshot.entries[$0] }, ids.count)
    }

    private func rowCandidates(folder: Int, direct: Bool, groupRoots: [Int]?) -> FlattenSequence<[ArraySlice<Int>]> {
        if direct { return [(groupRoots ?? snapshot.entries[folder].children)[...]].joined() }
        guard let groupRoots else { return [ranges[folder].map { traversal[$0] } ?? []].joined() }
        var slices: [ArraySlice<Int>] = []
        for id in groupRoots {
            slices.append([id][...])
            if let range = ranges[id] { slices.append(traversal[range]) }
        }
        return slices.joined()
    }
}
