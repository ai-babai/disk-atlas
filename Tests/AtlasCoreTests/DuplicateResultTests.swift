import XCTest

@testable import AtlasCore

final class DuplicateResultTests: XCTestCase {
    private func group(_ id: String, _ paths: [String], bytes: Int64 = 100) throws -> DuplicateGroup {
        DuplicateGroup(id: id, files: try paths.map { try Fixtures.file($0, bytes: bytes) })
    }
    func testReloadedReportBuildsIndexWithoutSourceAccessOrChangingEvidence() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ScanHistory(directory: directory)
        let record = try await history.archive(Fixtures.snapshot([100, 100]))
        let original = DuplicateReport(
            roots: ["/missing"], snapshotCreated: Date(timeIntervalSince1970: 1000),
            checkedAt: Date(timeIntervalSince1970: 2000), options: DuplicateOptions(),
            groups: [try group("mixed", ["/missing/a.txt", "/missing/Images/photo.png"])], skipped: 0, hardLinks: 0,
            issues: [], readBytes: 1234, elapsed: 1, cancelled: false)
        _ = try await history.saveDuplicates(original, id: record.id)
        let saved = try await history.loadDuplicates(id: record.id)
        let report = try XCTUnwrap(saved?.0)
        let lookup = try DuplicateLookup(report)
        var filter = DuplicateOptions()
        filter.kinds = [.image]
        XCTAssertEqual(try lookup.results.query(options: filter).count, 1)
        XCTAssertEqual(try lookup.results.query(options: DuplicateOptions()).count, 1)
        XCTAssertEqual(lookup.count(in: "/missing", directory: true), 2)
        XCTAssertEqual(lookup.byPath["/missing/a.txt"], "mixed")
        XCTAssertEqual(report.checkedAt, original.checkedAt)
        XCTAssertEqual(report.readBytes, original.readBytes)
        XCTAssertEqual(report.options, original.options)
        XCTAssertEqual(report.groups[0].files.map(\.path), original.groups[0].files.map(\.path))
    }
    func testNarrowAndWidenUseSavedMetadataAndKeepEveryPeer() throws {
        let mixed = try group("mixed", ["/missing/docs/a.txt", "/missing/images/photo.png"])
        let video = try group("video", ["/missing/videos/one.mp4", "/missing/videos/two.mov"], bytes: 300)
        let index = DuplicateResultIndex([mixed, video])
        var images = DuplicateOptions()
        images.kinds = [.image]
        let filtered = try index.query(options: images)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.groups[0].files.map(\.path), ["/missing/images/photo.png", "/missing/docs/a.txt"])
        XCTAssertEqual(filtered.groups[0].displayName, "photo.png")
        XCTAssertEqual(filtered.repeatedBytes, 100)
        XCTAssertEqual(mixed.files[0].path, "/missing/docs/a.txt")
        let restored = try index.query(options: DuplicateOptions())
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.repeatedBytes, 400)
        XCTAssertEqual(restored.groups.map(\.id), ["video", "mixed"])
        XCTAssertEqual(try index.query(options: images).groups[0].files.count, 2)
    }
    func testSizeDatesAndScopeMatchTheSameCopy() throws {
        let first = try group("a", ["/data/Photos/image.jpg", "/data/Documents/copy.txt"])
        let sibling = try group("b", ["/data/Photos-old/a.png", "/data/Photos-old/b.png"], bytes: 200)
        let index = DuplicateResultIndex([first, sibling])
        var options = DuplicateOptions()
        options.kinds = [.image]
        options.minimumBytes = 100
        options.maximumBytes = 100
        XCTAssertEqual(try index.query(options: options, scope: "/data/Photos").count, 1)
        XCTAssertEqual(try index.query(options: options, scope: "/data/Documents").count, 0)
        XCTAssertEqual(try index.query(options: options, scope: "/data/Photos-old").count, 0)
        XCTAssertEqual(try index.query(options: options, scope: "/").count, 1)
        XCTAssertEqual(try index.query(options: options, scope: first.files[0].path).count, 1)
        options.minimumBytes = 101
        XCTAssertEqual(try index.query(options: options).count, 0)
        options = DuplicateOptions()
        options.modifiedAfter = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(try index.query(options: options).count, 0)
        options.modifiedAfter = nil
        options.modifiedBefore = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(try index.query(options: options).count, 0)
    }
    func testPaginationCountsAllMatchesAndCancellationFails() async throws {
        let values = try (0..<20).map { n in
            try group("\(n)", ["/missing/\(n)/a.png", "/missing/\(n)/b.png"], bytes: Int64(n))
        }
        let index = DuplicateResultIndex(values + [DuplicateGroup(id: "empty", files: [])])
        let page = try index.query(options: DuplicateOptions(), sort: .fileBytes, descending: false, limit: 2)
        XCTAssertEqual(page.groups.map(\.fileBytes), [0, 1])
        XCTAssertEqual(page.count, 20)
        XCTAssertEqual(page.repeatedBytes, 190)
        XCTAssertTrue(try index.query(options: DuplicateOptions(), limit: -1).groups.isEmpty)
        XCTAssertEqual(try DuplicateResultIndex([]).query(options: DuplicateOptions()).count, 0)
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try index.query(options: DuplicateOptions())
        }
        do {
            _ = try await worker.value
            XCTFail("Cancelled query must stop")
        } catch is CancellationError {}
    }
    func testCoverageCannotClaimUncheckedSizesKindsOrDates() {
        var checked = DuplicateOptions()
        var requested = DuplicateOptions()
        XCTAssertTrue(checked.covers(requested))
        checked.minimumBytes = 100
        XCTAssertFalse(checked.covers(requested))
        requested.minimumBytes = 100
        XCTAssertTrue(checked.covers(requested))
        checked.maximumBytes = 1000
        XCTAssertFalse(checked.covers(requested))
        requested.maximumBytes = 500
        XCTAssertTrue(checked.covers(requested))
        requested.maximumBytes = 1001
        XCTAssertFalse(checked.covers(requested))
        requested.maximumBytes = 500
        checked.kinds = [.image, .video]
        XCTAssertFalse(checked.covers(requested))
        requested.kinds = [.image]
        XCTAssertTrue(checked.covers(requested))
        requested.kinds = [.document]
        XCTAssertFalse(checked.covers(requested))
        requested.kinds = [.image]
        checked.modifiedAfter = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(checked.covers(requested))
        requested.modifiedAfter = Date(timeIntervalSince1970: 101)
        XCTAssertTrue(checked.covers(requested))
        requested.modifiedAfter = Date(timeIntervalSince1970: 99)
        XCTAssertFalse(checked.covers(requested))
        requested.modifiedAfter = checked.modifiedAfter
        checked.modifiedBefore = Date(timeIntervalSince1970: 200)
        XCTAssertFalse(checked.covers(requested))
        requested.modifiedBefore = Date(timeIntervalSince1970: 199)
        XCTAssertTrue(checked.covers(requested))
        requested.modifiedBefore = Date(timeIntervalSince1970: 201)
        XCTAssertFalse(checked.covers(requested))
    }
    func testGeneratedFiltersAreMonotoneAndScopeNeverHidesPeers() throws {
        let groups = try (0..<50).map { n in
            try group("\(n)", ["/scope/\(n).png", "/outside/\(n).txt"], bytes: Int64(n))
        }
        let index = DuplicateResultIndex(groups)
        for lower in 0..<50 {
            var options = DuplicateOptions()
            options.minimumBytes = Int64(lower)
            options.kinds = [.image]
            let page = try index.query(options: options, scope: "/scope")
            XCTAssertEqual(page.count, 50 - lower)
            XCTAssertEqual(page.groups.flatMap(\.files).count, 2 * (50 - lower))
            XCTAssertEqual(Set(page.groups.map(\.id)), Set((lower..<50).map(String.init)))
        }
    }
}
