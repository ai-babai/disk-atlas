import Foundation

@testable import AtlasCore

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64 = 0xD15C_A71A5
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

enum Fixtures {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("disk-atlas-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func file(_ path: String, bytes: Int64) throws -> DuplicateFile {
        let value: [String: Any] = [
            "path": path, "bytes": bytes, "modified": "2026-01-01T00:00:00Z", "created": "2025-01-01T00:00:00Z",
            "device": 0, "inode": 1, "modifiedSeconds": 0, "modifiedNanos": 0, "changedSeconds": 0, "changedNanos": 0,
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DuplicateFile.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static func group(id: String, bytes: Int64, copies: Int, name: String? = nil) throws -> DuplicateGroup {
        let files = try (0..<copies).map { try file("/Volumes/Synthetic/\(id)/copy-\($0).dat", bytes: bytes) }
        return DuplicateGroup(id: id, files: files, displayName: name)
    }
    static func snapshot(_ sizes: [Int64]) -> Snapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var entries = [
            Entry(
                id: 0, parent: nil, name: "Synthetic", path: "/Volumes/Synthetic", kind: .folder,
                bytes: sizes.reduce(0, +), logicalBytes: sizes.reduce(0, +), fileCount: sizes.count, modified: date,
                sharedLink: false, children: sizes.indices.map { $0 + 1 })
        ]
        for (i, size) in sizes.enumerated() {
            entries.append(
                Entry(
                    id: i + 1, parent: 0, name: String(format: "file-%04d", i), path: "/Volumes/Synthetic/file-\(i)",
                    kind: .document, bytes: size, logicalBytes: size, fileCount: 1,
                    modified: date.addingTimeInterval(Double(i)), sharedLink: false, children: []))
        }
        return Snapshot(
            root: "/Volumes/Synthetic", created: date, elapsed: 0, volumeTotal: 1_000_000, volumeFree: 500_000,
            entries: entries, issues: [], issueCount: 0, cancelled: false)
    }
}
