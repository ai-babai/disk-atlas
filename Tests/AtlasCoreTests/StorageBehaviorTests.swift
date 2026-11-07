import Darwin
import XCTest

@testable import AtlasCore

final class StorageBehaviorTests: XCTestCase {
    func testDuplicateSamplesRejectDifferentEdgesAndMiddleWithoutChangingSources() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data(repeating: 65, count: 1_200_000)
        try original.write(to: root.appendingPathComponent("one.bin"))
        try original.write(to: root.appendingPathComponent("copy.bin"))
        for (name, offset) in [("head.bin", 0), ("middle.bin", 600_000), ("tail.bin", 1_199_999)] {
            var data = original
            data[offset] = 66
            try data.write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("one.bin"))
        let snapshot = try DiskScanner().scan(path: root.path)
        let finder = DuplicateFinder()
        let plan = try finder.prepare(snapshot, options: DuplicateOptions())
        let report = try finder.run(plan)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].files.count, 2)
        XCTAssertEqual(
            Set(report.groups[0].files.map { URL(fileURLWithPath: $0.path).lastPathComponent }),
            ["one.bin", "copy.bin"])
        XCTAssertLessThan(report.readBytes, Int64(original.count * 5 * 3))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("one.bin")), original)
        let control = DuplicateControl()
        control.cancel()
        XCTAssertTrue(try finder.run(plan, control: control).cancelled)
    }
    func testChangedPathIsNeverFollowed() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let copy = root.appendingPathComponent("copy")
        try Data(repeating: 42, count: 2048).write(to: first)
        try Data(repeating: 42, count: 2048).write(to: copy)
        let finder = DuplicateFinder()
        let plan = try finder.prepare(DiskScanner().scan(path: root.path), options: DuplicateOptions())
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: first)
        let report = try finder.run(plan)
        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertGreaterThan(report.skipped, 0)
    }
    func testGeneratedLargestListsAndFilteredTotals() throws {
        var random = SeededRandom()
        for _ in 0..<24 {
            let sizes = (0..<80).map { _ in Int64(random.next() % 10_000) }
            let snapshot = Fixtures.snapshot(sizes)
            let index = PresentationIndex(snapshot)
            for limit in [0, 1, 17, 1000] {
                let rows = index.rows(folder: 0, logical: true, query: "", kinds: [], filesOnly: true, limit: limit)
                XCTAssertEqual(rows.count, sizes.count)
                XCTAssertEqual(rows.entries.map(\.logicalBytes), Array(sizes.sorted(by: >).prefix(limit)))
            }
            var options = DuplicateOptions()
            options.minimumBytes = 2000
            options.maximumBytes = 7000
            let filtered = try ViewFilter.apply(snapshot, options: options)
            XCTAssertEqual(filtered.rootEntry.logicalBytes, sizes.filter { (2000...7000).contains($0) }.reduce(0, +))
            XCTAssertEqual(snapshot.rootEntry.logicalBytes, sizes.reduce(0, +))
        }
    }
    func testHistoryRemovalDeletesReportButPreservesSource() async throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data(repeating: 11, count: 4096)
        try data.write(to: source.appendingPathComponent("one"))
        try data.write(to: source.appendingPathComponent("two"))
        let snapshot = try DiskScanner().scan(path: source.path)
        let finder = DuplicateFinder()
        let report = try finder.run(finder.prepare(snapshot, options: DuplicateOptions()))
        let history = ScanHistory(directory: root.appendingPathComponent("history"))
        let record = try await history.archive(snapshot)
        let size = try await history.saveDuplicates(report, id: record.id)
        XCTAssertGreaterThan(size, 0)
        let saved = try await history.loadDuplicates(id: record.id)
        XCTAssertEqual(saved?.0.groups.count, 1)
        try await history.remove(ids: [record.id])
        let bytes = try await history.storageBytes()
        XCTAssertEqual(bytes, 0)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("one")), data)
    }
}
