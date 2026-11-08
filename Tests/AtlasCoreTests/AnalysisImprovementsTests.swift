import Darwin
import XCTest

@testable import AtlasCore

final class AnalysisImprovementsTests: XCTestCase {
    func testSearchMatchesTheSameCopyAsTypeAndScopeWithoutSourceFiles() throws {
        let files = try ["/missing/Photos/Café.PNG", "/missing/Docs/copy.txt"].map { try Fixtures.file($0, bytes: 42) }
        let index = try DuplicateResultIndex([DuplicateGroup(id: "one", files: files)])
        var options = DuplicateOptions()
        options.kinds = [.image]
        XCTAssertEqual(try index.query(options: options, scope: "/missing/Photos", search: " CAFE ").count, 1)
        XCTAssertEqual(try index.query(options: options, scope: "/missing/Docs", search: "cafe").count, 0)
        XCTAssertEqual(try index.query(options: options, search: "copy").count, 0)
        XCTAssertEqual(try index.query(options: DuplicateOptions(), search: "copy").groups[0].files.count, 2)
        XCTAssertEqual(try index.query(options: DuplicateOptions(), search: "copy").groups[0].displayName, "copy.txt")
        XCTAssertEqual(try index.query(options: DuplicateOptions(), search: "not present").repeatedBytes, 0)
    }
    func testEveryGroupCanBeRequestedBeyondFirstFiveHundred() throws {
        let groups = try (0..<1201).map { try Fixtures.group(id: String($0), bytes: Int64($0), copies: 2) }
        let index = try DuplicateResultIndex(groups)
        let first = try index.query(options: DuplicateOptions())
        let next = try index.query(options: DuplicateOptions(), limit: 1000)
        let all = try index.query(options: DuplicateOptions(), limit: 1500)
        XCTAssertEqual(first.groups.count, 500)
        XCTAssertEqual(next.groups.count, 1000)
        XCTAssertEqual(all.groups.count, 1201)
        XCTAssertEqual(next.groups.prefix(500).map(\.id), first.groups.map(\.id))
        XCTAssertEqual(all.groups.prefix(1000).map(\.id), next.groups.map(\.id))
        XCTAssertEqual(first.count, all.count)
        XCTAssertEqual(first.repeatedBytes, all.repeatedBytes)
        XCTAssertEqual(try index.query(options: DuplicateOptions(), search: "/1200/").groups.map(\.id), ["1200"])
    }
    func testCancelledIndexConstructionDoesNotPublishPartialSearchData() async throws {
        let group = try Fixtures.group(id: "cancel", bytes: 10, copies: 2)
        let job = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DuplicateResultIndex([group])
        }
        do {
            _ = try await job.value
            XCTFail("Cancelled indexing succeeded")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testMetadataPolicyRestoredAfterNestedCallsAndErrors() throws {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        enum Failure: Error { case expected }
        XCTAssertThrowsError(
            try MetadataIO.withoutCloudDownloads {
                XCTAssertEqual(
                    getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD),
                    IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
                try MetadataIO.withoutCloudDownloads { throw Failure.expected }
            })
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), previous)
        XCTAssertEqual(try MetadataIO.withoutCloudDownloads { 7 }, 7)
        XCTAssertEqual(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD), previous)
    }
    func testScanRecordsLocalCloudStateAndLegacyMetadataStaysUnknown() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([42]).write(to: root.appendingPathComponent("local.txt"))
        let snapshot = try DiskScanner().scan(path: root.path)
        XCTAssertTrue(snapshot.entries.allSatisfy { $0.cloudOnly == false })
        let facts = try XCTUnwrap(BranchFactsIndex(snapshot).facts(for: 0))
        XCTAssertTrue(facts.cloudMetadataKnown)
        XCTAssertEqual(facts.cloudFiles, 0)
        XCTAssertFalse(facts.partial)
        let legacy = Fixtures.snapshot([10, 20])
        let decoded = try Snapshot.decode(Snapshot.encoder.encode(legacy))
        XCTAssertNil(decoded.entries[1].cloudOnly)
        XCTAssertFalse(try XCTUnwrap(BranchFactsIndex(decoded).facts(for: 0)).cloudMetadataKnown)
    }
    func testCompositeScanKeepsValidRootsHardLinksAndIncompleteEvidence() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: a.appendingPathComponent("file.txt"))
        try FileManager.default.linkItem(
            at: a.appendingPathComponent("file.txt"), to: b.appendingPathComponent("link.txt"))
        try Data(repeating: 2, count: 20).write(to: b.appendingPathComponent("other.txt"))
        let invalid = root.appendingPathComponent("not-a-folder")
        try Data([3]).write(to: invalid)
        let paths = [a.path, b.path, invalid.path]
        let snapshot = try DiskScanner().scan(paths: paths)
        XCTAssertEqual(snapshot.rootEntry.logicalBytes, 30)
        XCTAssertEqual(snapshot.rootEntry.fileCount, 3)
        XCTAssertEqual(snapshot.rootEntry.children.count, 2)
        XCTAssertEqual(snapshot.entries.filter(\.sharedLink).count, 1)
        XCTAssertEqual(snapshot.issueCount, 1)
        XCTAssertEqual(snapshot.issues.first?.path, try DiskScanner.canonicalPath(invalid.path))
        XCTAssertTrue(try XCTUnwrap(BranchFactsIndex(snapshot).facts(for: 0)).partial)
        let token = ScanCancellation()
        token.cancel()
        XCTAssertTrue(try DiskScanner().scan(paths: paths, cancellation: token).cancelled)
        XCTAssertThrowsError(try DiskScanner().scan(paths: []))
    }
    func testBranchFactsAggregateAndMarkOnlyAffectedBranches() throws {
        var snapshot = Fixtures.snapshot([10, 20, 30])
        snapshot.entries[1].kind = .folder
        snapshot.entries[1].children = [3]
        snapshot.entries[3].parent = 1
        snapshot.entries[0].children = [1, 2]
        for i in snapshot.entries.indices { snapshot.entries[i].cloudOnly = i == 3 }
        snapshot.issues = [ScanIssue(path: snapshot.entries[1].path + "/unread/nested", message: "Unavailable")]
        snapshot.issueCount = 1
        let index = BranchFactsIndex(snapshot)
        XCTAssertEqual(index.facts(for: 0)?.folders, 1)
        XCTAssertEqual(index.facts(for: 0)?.cloudFiles, 1)
        XCTAssertEqual(index.facts(for: 1)?.cloudFiles, 1)
        XCTAssertEqual(index.facts(for: 1)?.partial, true)
        XCTAssertEqual(index.facts(for: 2)?.partial, false)
        XCTAssertNil(index.facts(for: -1))
        snapshot.issues = [ScanIssue(path: "/elsewhere/file", message: "Unavailable")]
        snapshot.cancelled = true
        XCTAssertEqual(BranchFactsIndex(snapshot).facts(for: 2)?.partial, true)
    }
}
