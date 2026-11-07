import XCTest

@testable import AtlasCore

final class DuplicateEfficiencyTests: XCTestCase {
    private func fingerprint(_ data: Data, chunk: Int) throws -> String {
        let hasher = try ContentFingerprint()
        data.withUnsafeBytes { bytes in
            for start in stride(from: 0, to: bytes.count, by: chunk) {
                hasher.update(UnsafeRawBufferPointer(rebasing: bytes[start..<min(start + chunk, bytes.count)]))
            }
        }
        return hasher.finalize()
    }
    func testXXH3ReferenceVectorsAndStreamingBoundaries() throws {
        let vectors = [
            "": "99aa06d3014798d86001c324468d497f", "a": "a96faf705af16834e6c632b61e964e1f",
            "abc": "06b05ab6733a618578af5f94892f3950",
        ]
        for (input, expected) in vectors {
            XCTAssertEqual(try fingerprint(Data(input.utf8), chunk: 1), "xxh3-128:" + expected)
        }
        let data = Data((0..<70_000).map { UInt8(truncatingIfNeeded: $0) })
        let expected = try fingerprint(data, chunk: data.count)
        for chunk in [1, 16, 63, 240, 1024, 65_536] { XCTAssertEqual(try fingerprint(data, chunk: chunk), expected) }
        let emptyUpdate = try ContentFingerprint()
        emptyUpdate.update(UnsafeRawBufferPointer(start: nil, count: 0))
        XCTAssertEqual(emptyUpdate.finalize(), "xxh3-128:" + vectors[""]!)
    }
    func testLargePairSkipsWholeFileHashButStillRejectsDifferentMiddle() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(repeating: 42, count: 1_200_000)
        let first = root.appendingPathComponent("one.mov")
        let second = root.appendingPathComponent("two.mov")
        try data.write(to: first)
        try data.write(to: second)
        let finder = DuplicateFinder()
        let plan = try finder.prepare(DiskScanner().scan(path: root.path), options: DuplicateOptions())
        let report = try finder.run(plan)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.readBytes, Int64(data.count * 2 + 131_072 * 2))
        var different = data
        different[600_000] = 43
        try different.write(to: second)
        let updated = try finder.prepare(DiskScanner().scan(path: root.path), options: DuplicateOptions())
        XCTAssertTrue(try finder.run(updated).groups.isEmpty)
        XCTAssertEqual(try Data(contentsOf: first), data)
        XCTAssertEqual(try Data(contentsOf: second), different)
    }
    func testFullHashForThreeCandidatesAndFingerprintCollisionPartitioning() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = Data(repeating: 65, count: 1_200_000)
        var b = a
        b[600_000] = 66
        for (name, data) in [("a", a), ("a-copy", a), ("b", b), ("b-copy", b)] {
            try data.write(to: root.appendingPathComponent(name))
        }
        let finder = DuplicateFinder()
        let plan = try finder.prepare(DiskScanner().scan(path: root.path), options: DuplicateOptions())
        XCTAssertEqual(try finder.run(plan).groups.map(\.files.count).sorted(), [2, 2])
        let worker = DuplicateRun(
            plan: plan, finder: finder, control: DuplicateControl(), progress: { _ in }, found: { _ in })
        try worker.confirm(plan.buckets.flatMap { $0 }, fingerprint: "forced-collision")
        XCTAssertEqual(worker.groups.map(\.files.count).sorted(), [2, 2])
        XCTAssertEqual(Set(worker.groups.map(\.id)).count, 2)
    }
    func testCancellationInterruptsLookupEncodingAndKeepsSavedReport() async throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ScanHistory(directory: root)
        let record = try await history.archive(Fixtures.snapshot([100, 100]))
        let report = DuplicateReport(
            roots: ["/Volumes/Synthetic"], snapshotCreated: record.created, checkedAt: record.created,
            options: DuplicateOptions(), groups: [try Fixtures.group(id: "copy", bytes: 100, copies: 3)], skipped: 0,
            hardLinks: 0, issues: [], readBytes: 1000, elapsed: 1, cancelled: false)
        _ = try await history.saveDuplicates(report, id: record.id)
        let saved = try Data(contentsOf: root.appendingPathComponent(record.id.uuidString + ".duplicates.json"))
        for operation in 0..<3 {
            let task = Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                switch operation {
                case 0: _ = try DuplicateLookup(report)
                case 1: _ = try Snapshot.encoder.encode(report)
                default: _ = try await history.saveDuplicates(report, id: record.id)
                }
            }
            do {
                try await task.value
                XCTFail("Cancelled operation must stop")
            } catch is CancellationError {}
        }
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(record.id.uuidString + ".duplicates.json")), saved)
        let loaded = try await history.loadDuplicates(id: record.id)
        XCTAssertEqual(loaded?.0.groups[0].files.count, 3)
        let lookup = try DuplicateLookup(report)
        XCTAssertEqual(lookup.count(in: "/Volumes/Synthetic", directory: true), 3)
        XCTAssertEqual(lookup.count(in: "/", directory: true), 3)
    }
}
