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
        let searchPaths: [String]
        init(_ group: DuplicateGroup) throws {
            self.group = group
            searchPaths = try group.files.enumerated().map { offset, file in
                if offset % 1024 == 0 { try Task.checkCancellation() }
                return Self.searchKey(file.path)
            }
        }
        static func searchKey(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        func match(_ options: DuplicateOptions, scope: String?, search: String) throws -> Int? {
            for (index, file) in group.files.enumerated() {
                if index % 1024 == 0 { try Task.checkCancellation() }
                if matches(file, options: options, scope: scope), search.isEmpty || searchPaths[index].contains(search)
                {
                    return index
                }
            }
            return nil
        }
        private func matches(_ file: DuplicateFile, options: DuplicateOptions, scope: String?) -> Bool {
            guard options.kinds.isEmpty || options.kinds.contains(FileKind.classify(URL(fileURLWithPath: file.path))),
                options.matchesDate(file.modified)
            else { return false }
            if let scope, file.path != scope, !file.path.hasPrefix(scope == "/" ? "/" : scope + "/") { return false }
            return true
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
    public init(_ groups: [DuplicateGroup]) throws {
        try Task.checkCancellation()
        items = try groups.map(Item.init)
    }

    public func query(
        options: DuplicateOptions, scope: String? = nil, sort: DuplicateSort = .repeatedBytes, descending: Bool = true,
        limit: Int = 500, search: String = ""
    ) throws -> DuplicateResultPage {
        let search = Item.searchKey(search.trimmingCharacters(in: .whitespacesAndNewlines))
        var matches: [DuplicateGroup] = []
        for (offset, item) in items.enumerated() {
            if offset % 1024 == 0 { try Task.checkCancellation() }
            let bytes = item.group.fileBytes
            guard item.group.files.count > 1, bytes >= options.minimumBytes,
                options.maximumBytes.map({ bytes <= $0 }) ?? true
            else { continue }
            if let index = try item.match(options, scope: scope, search: search) {
                matches.append(item.projection(index))
            }
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
