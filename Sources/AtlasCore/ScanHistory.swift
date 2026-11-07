import Foundation

public struct ScanHistoryRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var roots: [String]
    public var created: Date
    public var bytes: Int64
    public var logicalBytes: Int64
    public var entryCount: Int
    public var elapsed: Double
    public var cancelled: Bool

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
        records = decoded.sorted { $0.created > $1.created }
        return records!
    }

    public func archive(_ snapshot: Snapshot) throws -> ScanHistoryRecord {
        var current = try list()
        if let existing = current.first(where: { $0.matches(snapshot) }) { return existing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let record = ScanHistoryRecord(id: UUID(), roots: snapshot.scanRoots, created: snapshot.created,
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
        current.append(record)
        current.sort { $0.created > $1.created }
        do { try saveManifest(current) }
        catch { try? FileManager.default.removeItem(at: target); throw error }
        records = current
        return record
    }

    public func load(_ record: ScanHistoryRecord) throws -> Snapshot {
        let data = try Data(contentsOf: url(for: record))
        let decoded = try (data as NSData).decompressed(using: .lzfse) as Data
        return try Snapshot.decode(decoded)
    }

    private func url(for record: ScanHistoryRecord) -> URL {
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
