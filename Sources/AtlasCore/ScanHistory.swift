import Foundation
import Darwin

public struct ScanHistoryRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var roots: [String]
    public var created: Date
    public var bytes: Int64
    public var logicalBytes: Int64
    public var entryCount: Int
    public var elapsed: Double
    public var cancelled: Bool
    public var archiveBytes: Int64? = nil
    public var duplicateBytes: Int64? = nil
    public var storedBytes: Int64? { archiveBytes.map { $0 + (duplicateBytes ?? 0) } }

    func matches(_ snapshot: Snapshot) -> Bool {
        roots == snapshot.scanRoots && created.timeIntervalSince1970.rounded(.down) == snapshot.created.timeIntervalSince1970.rounded(.down)
        && elapsed == snapshot.elapsed && entryCount == snapshot.entries.count
        && bytes == snapshot.rootEntry.bytes && logicalBytes == snapshot.rootEntry.logicalBytes
    }
}

/// Serial background storage; the sidebar only holds these lightweight records.
public actor ScanHistory {
    private let directory: URL
    private var records: [ScanHistoryRecord]?

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Disk Atlas/History", isDirectory: true)) {
        self.directory = directory
    }

    public func list() throws -> [ScanHistoryRecord] {
        if let records { return records }
        let manifest = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { records = []; return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ScanHistoryRecord].self, from: Data(contentsOf: manifest))
        records = decoded.map { record in
            var record = record
            record.archiveBytes = (try? FileManager.default.attributesOfItem(atPath: url(for: record).path)[.size] as? NSNumber)?.int64Value
            record.duplicateBytes = (try? FileManager.default.attributesOfItem(atPath: duplicateURL(record.id).path)[.size] as? NSNumber)?.int64Value
            return record
        }.sorted { $0.created > $1.created }
        return records!
    }

    public func archive(_ snapshot: Snapshot) throws -> ScanHistoryRecord {
        var current = try list()
        if let existing = current.first(where: { $0.matches(snapshot) }) { return existing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var record = ScanHistoryRecord(id: UUID(), roots: snapshot.scanRoots, created: snapshot.created,
                                       bytes: snapshot.rootEntry.bytes, logicalBytes: snapshot.rootEntry.logicalBytes,
                                       entryCount: snapshot.entries.count, elapsed: snapshot.elapsed, cancelled: snapshot.cancelled)
        let encoded = try Snapshot.encoder.encode(snapshot)
        guard encoded.count <= 2 * 1024 * 1024 * 1024 else {
            throw AtlasError.message("Нужен обычный файл снимка размером до 2 ГБ.")
        }
        let compressed = try (encoded as NSData).compressed(using: .lzfse) as Data
        let target = url(for: record)
        try compressed.write(to: target, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        record.archiveBytes = Int64(compressed.count)
        current.append(record)
        current.sort { $0.created > $1.created }
        do { try saveManifest(current) }
        catch { try? FileManager.default.removeItem(at: target); throw error }
        records = current
        return record
    }

    public nonisolated func load(_ record: ScanHistoryRecord) async throws -> Snapshot {
        let data = try Data(contentsOf: url(for: record))
        let decoded = try (data as NSData).decompressed(using: .lzfse) as Data
        return try Snapshot.decode(decoded)
    }

    public func saveDuplicates(_ report: DuplicateReport, id: UUID) throws -> Int64 {
        var current = try list()
        guard let index = current.firstIndex(where: { $0.id == id }) else { throw AtlasError.message("Снимок больше не сохранён в истории.") }
        let data = try Snapshot.encoder.encode(report)
        guard data.count <= 256 * 1024 * 1024 else { throw AtlasError.message("Слишком большой отчёт дубликатов.") }
        let target = duplicateURL(id)
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        current[index].duplicateBytes = Int64(data.count)
        try saveManifest(current); records = current
        return Int64(data.count)
    }

    public nonisolated func loadDuplicates(id: UUID) async throws -> (DuplicateReport, Int64)? {
        let target = duplicateURL(id)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 256 * 1024 * 1024 else { throw AtlasError.message("Слишком большой отчёт дубликатов.") }
        let data = try Data(contentsOf: target)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(DuplicateReport.self, from: data)
        return (report, Int64(data.count))
    }

    private nonisolated func duplicateURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".duplicates.json") }

    public func storageBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == "index.json" || archiveID($0) != nil }
            .reduce(Int64(0)) { total, url in
                total + ((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
            }
    }

    /// Deletes only UUID-named, app-owned archives and the history index.
    /// Source folders and user-exported snapshots are never targets.
    public func remove(ids: Set<UUID>, all: Bool = false) throws {
        var current = all ? ((try? list()) ?? []) : try list()
        let targets: [URL]
        if all, FileManager.default.fileExists(atPath: directory.path) {
            targets = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { archiveID($0) != nil }
        } else { targets = current.filter { ids.contains($0.id) }.flatMap { [url(for: $0), duplicateURL($0.id)] } }
        var failure: Error?
        var removed = Set<UUID>()
        for target in targets {
            do {
                try removeFile(target)
                if target.lastPathComponent.hasSuffix(".atlas.lzfse"), let id = archiveID(target) { removed.insert(id) }
            } catch { if failure == nil { failure = error } }
        }
        // Also forget records whose archive was already removed outside the app.
        current.removeAll { removed.contains($0.id) || ((all || ids.contains($0.id)) && !FileManager.default.fileExists(atPath: url(for: $0).path)) }
        if current.isEmpty {
            let manifest = directory.appendingPathComponent("index.json")
            try removeFile(manifest)
        } else { try saveManifest(current) }
        records = current
        if let failure { throw failure }
    }

    private func removeFile(_ url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { unlink($0!) }
        if result != 0 && errno != ENOENT { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private nonisolated func archiveID(_ url: URL) -> UUID? {
        for suffix in [".atlas.lzfse", ".duplicates.json"] where url.lastPathComponent.hasSuffix(suffix) {
            return UUID(uuidString: String(url.lastPathComponent.dropLast(suffix.count)))
        }
        return nil
    }

    private nonisolated func url(for record: ScanHistoryRecord) -> URL {
        directory.appendingPathComponent(record.id.uuidString + ".atlas.lzfse")
    }

    private func saveManifest(_ records: [ScanHistoryRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let target = directory.appendingPathComponent("index.json")
        try encoder.encode(records).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}
