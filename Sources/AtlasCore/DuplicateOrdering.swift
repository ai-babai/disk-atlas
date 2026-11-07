import Foundation

public enum DuplicateSort: String, CaseIterable, Sendable {
    case repeatedBytes, fileBytes, copies, name

    public var title: String {
        switch self {
        case .repeatedBytes: return L10n.text("Повторный объём")
        case .fileBytes: return L10n.text("Размер копии")
        case .copies: return L10n.text("Копии")
        case .name: return L10n.text("Имя")
        }
    }

    public func ordered(_ groups: [DuplicateGroup], descending: Bool) throws -> [DuplicateGroup] {
        var comparisons = 0
        return try groups.sorted { left, right in
            comparisons += 1
            if comparisons % 1024 == 0 { try Task.checkCancellation() }
            let order = compare(left, right)
            if order == .orderedSame { return left.id < right.id }
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
    }

    private func compare(_ left: DuplicateGroup, _ right: DuplicateGroup) -> ComparisonResult {
        if self == .name { return name(left).localizedStandardCompare(name(right)) }
        let a = amount(left)
        let b = amount(right)
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    private func amount(_ group: DuplicateGroup) -> Int64 {
        switch self {
        case .repeatedBytes: return group.repeatedBytes
        case .fileBytes: return group.fileBytes
        case .copies: return Int64(group.files.count)
        case .name: return 0
        }
    }

    private func name(_ group: DuplicateGroup) -> String {
        group.displayName ?? group.files.first.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? group.id
    }
}
