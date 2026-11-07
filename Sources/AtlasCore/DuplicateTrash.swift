import Foundation

/// An ephemeral selection. A checked box always means “move to Trash”.
public struct DuplicateTrashSelection: Sendable {
    public private(set) var paths = Set<String>()
    public init() {}
    public func count(in group: DuplicateGroup) -> Int { group.files.filter { paths.contains($0.path) }.count }
    public mutating func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard group.files.contains(where: { $0.path == file.path }) else { return }
        if paths.remove(file.path) == nil { paths.insert(file.path) }
    }
    public mutating func toggle(_ group: DuplicateGroup) {
        if count(in: group) == group.files.count {
            paths.subtract(group.files.map(\.path))
        } else {
            paths.formUnion(group.files.map(\.path))
        }
    }
}

/// Immutable review data. Remaining copies and fully selected groups are explicit.
public struct DuplicateTrashPlan: Sendable, Identifiable {
    public struct Batch: Sendable {
        public let groupID: String
        public let keeper: DuplicateFile?
        public let reference: DuplicateFile
        public let files: [DuplicateFile]
    }
    public let id = UUID()
    public let checkedAt: Date
    public let snapshotCreated: Date
    public let batches: [Batch]
    public let files: [DuplicateFile]
    public let bytes: Int64
    public let verificationBytes: Int64
    public var removesWholeGroups: Bool { batches.contains { $0.keeper == nil } }

    public init(report: DuplicateReport, paths: Set<String>) throws {
        checkedAt = report.checkedAt
        snapshotCreated = report.snapshotCreated
        guard !paths.isEmpty else { throw AtlasError.message("Выбери копии для корзины.") }
        batches = try report.groups.compactMap { try Self.batch($0, paths: paths, roots: report.roots) }
        files = batches.flatMap(\.files)
        let selected = files.map(\.path)
        bytes = try Self.totalBytes(files)
        verificationBytes =
            try Self.totalBytes(batches.flatMap { batch in batch.files.filter { $0.path != batch.reference.path } }) * 2
        guard Set(selected) == paths, selected.count == paths.count else {
            throw AtlasError.message("Выбор не соответствует отчёту. Повтори поиск дубликатов.")
        }
    }
    private static func totalBytes(_ files: [DuplicateFile]) throws -> Int64 {
        try files.reduce(Int64(0)) { total, file in
            let next = total.addingReportingOverflow(file.bytes)
            guard !next.overflow, next.partialValue <= Int64.max / 2 else {
                throw AtlasError.message("Некорректный суммарный размер файлов.")
            }
            return next.partialValue
        }
    }
    private static func batch(_ group: DuplicateGroup, paths: Set<String>, roots: [String]) throws -> Batch? {
        let files = group.files.filter { paths.contains($0.path) }
        guard !files.isEmpty else { return nil }
        try validate(group, roots: roots)
        let keeper = group.files.first(where: { !paths.contains($0.path) })
        return Batch(groupID: group.id, keeper: keeper, reference: keeper ?? group.files[0], files: files)
    }
    private static func validate(_ group: DuplicateGroup, roots: [String]) throws {
        let identities = Set(group.files.map { "\($0.device):\($0.inode)" })
        guard group.files.count > 1, identities.count == group.files.count else {
            throw AtlasError.message("Некорректная группа или жёсткие ссылки. Повтори поиск дубликатов.")
        }
        for file in group.files {
            guard file.bytes >= 0, file.bytes == group.fileBytes, safePath(file.path),
                roots.contains(where: { $0 == "/" || file.path.hasPrefix($0 + "/") })
            else { throw AtlasError.message("Файл вне области поиска или группа повреждена.") }
        }
    }
    private static func safePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

}

extension DuplicateReport {
    public func removing(_ paths: Set<String>) -> DuplicateReport {
        var value = self
        value.groups = groups.compactMap { group in
            var group = group
            group.files.removeAll { paths.contains($0.path) }
            guard group.files.count > 1 else { return nil }
            group.displayName = URL(fileURLWithPath: group.files[0].path).lastPathComponent
            group.locations = Array(
                Set(group.files.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().lastPathComponent })
            ).sorted()
            if paths.contains(group.preferredPath ?? "") { group.preferredPath = nil }
            return group
        }
        return value
    }
}
