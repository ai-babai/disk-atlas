import Foundation

public struct DuplicateResultPage: Sendable {
    public let groups: [DuplicateGroup]
    public let count: Int
    public let repeatedBytes: Int64
}

/// A projection of confirmed metadata. Querying never touches source files or changes the saved report.
public final class DuplicateResultIndex: Sendable {
    private struct Item: Sendable {
        let group: DuplicateGroup
        init(_ group: DuplicateGroup) { self.group = group }
        func match(_ options: DuplicateOptions, scope: String?) throws -> Int? {
            for (index, file) in group.files.enumerated() {
                if index % 1024 == 0 { try Task.checkCancellation() }
                if !options.kinds.isEmpty && !options.kinds.contains(FileKind.classify(URL(fileURLWithPath: file.path)))
                {
                    continue
                }
                if !options.matchesDate(file.modified) { continue }
                if let scope, file.path != scope, !file.path.hasPrefix(scope == "/" ? "/" : scope + "/") { continue }
                return index
            }
            return nil
        }
        func projection(_ index: Int) -> DuplicateGroup {
            var value = group
            if index != 0 {
                value.files.swapAt(0, index)
                value.displayName = URL(fileURLWithPath: value.files[0].path).lastPathComponent
            }
            return value
        }
    }
    private let items: [Item]
    public init(_ groups: [DuplicateGroup]) { items = groups.map(Item.init) }

    public func query(
        options: DuplicateOptions, scope: String? = nil, sort: DuplicateSort = .repeatedBytes, descending: Bool = true,
        limit: Int = 500
    ) throws -> DuplicateResultPage {
        var matches: [DuplicateGroup] = []
        for (offset, item) in items.enumerated() {
            if offset % 1024 == 0 { try Task.checkCancellation() }
            let bytes = item.group.fileBytes
            guard item.group.files.count > 1, bytes >= options.minimumBytes,
                options.maximumBytes.map({ bytes <= $0 }) ?? true
            else { continue }
            if let index = try item.match(options, scope: scope) { matches.append(item.projection(index)) }
        }
        let ordered = try sort.ordered(matches, descending: descending)
        return DuplicateResultPage(
            groups: Array(ordered.prefix(max(0, limit))), count: ordered.count,
            repeatedBytes: matches.reduce(0) { $0 + $1.repeatedBytes })
    }
}

extension DuplicateOptions {
    /// Coverage describes the original check, including restrictions from older CLI reports.
    public func covers(_ requested: DuplicateOptions) -> Bool {
        guard minimumBytes <= requested.minimumBytes else { return false }
        if let maximumBytes, requested.maximumBytes.map({ $0 > maximumBytes }) ?? true { return false }
        if !kinds.isEmpty && (requested.kinds.isEmpty || !requested.kinds.isSubset(of: kinds)) { return false }
        if let modifiedAfter, requested.modifiedAfter.map({ $0 < modifiedAfter }) ?? true { return false }
        if let modifiedBefore, requested.modifiedBefore.map({ $0 > modifiedBefore }) ?? true { return false }
        return true
    }
}
