import XCTest

@testable import AtlasCore

final class DuplicateTrashTests: XCTestCase {
    private func group(_ id: String = "a", copies: Int = 3) throws -> DuplicateGroup {
        var value = try Fixtures.group(id: id, bytes: 100, copies: copies)
        for index in value.files.indices { value.files[index].inode = UInt64(index + 1) }
        return value
    }
    private func report(_ groups: [DuplicateGroup]) -> DuplicateReport {
        DuplicateReport(
            roots: ["/Volumes/Synthetic"], snapshotCreated: Date(timeIntervalSince1970: 100),
            checkedAt: Date(timeIntervalSince1970: 200), options: DuplicateOptions(), groups: groups, skipped: 0,
            hardLinks: 0, issues: [], readBytes: 0, elapsed: 0, cancelled: false)
    }
    func testGeneratedSelectionsAllowEveryCopyAndGroupToggleIsReversible() throws {
        var random = SeededRandom()
        for copies in 2...20 {
            let value = try group(copies: copies)
            var selection = DuplicateTrashSelection()
            for _ in 0..<100 {
                let file = value.files[Int(random.next() % UInt64(copies))]
                selection.toggle(file, in: value)
                XCTAssertLessThanOrEqual(selection.count(in: value), copies)
            }
            selection = DuplicateTrashSelection()
            selection.toggle(value)
            XCTAssertTrue(selection.paths.contains(value.files[0].path))
            XCTAssertEqual(selection.count(in: value), copies)
            selection.toggle(value)
            XCTAssertTrue(selection.paths.isEmpty)
            selection.toggle(value.files[0], in: value)
            selection.toggle(value)
            XCTAssertEqual(selection.count(in: value), copies)
            let foreign = try Fixtures.file("/outside", bytes: 1)
            let before = selection.paths
            selection.toggle(foreign, in: value)
            XCTAssertEqual(selection.paths, before)
        }
    }
    func testReviewIdentifiesExactlyTheSelectedFilesAndTheKeeper() throws {
        let value = try group()
        let source = report([value])
        let plan = try DuplicateTrashPlan(report: source, paths: Set(value.files.dropFirst().map(\.path)))
        XCTAssertEqual(plan.batches.count, 1)
        XCTAssertEqual(plan.batches[0].keeper?.path, value.files[0].path)
        XCTAssertEqual(plan.files.count, 2)
        XCTAssertEqual(plan.bytes, 200)
        XCTAssertEqual(plan.checkedAt, source.checkedAt)
        XCTAssertEqual(plan.snapshotCreated, source.snapshotCreated)
        XCTAssertEqual(plan.batches[0].groupID, value.id)
        XCTAssertThrowsError(try DuplicateTrashPlan(report: source, paths: []))
        XCTAssertThrowsError(try DuplicateTrashPlan(report: source, paths: ["/unknown"]))
        let all = try DuplicateTrashPlan(report: source, paths: Set(value.files.map(\.path)))
        XCTAssertNil(all.batches[0].keeper)
        XCTAssertEqual(all.batches[0].reference.path, value.files[0].path)
        XCTAssertTrue(all.removesWholeGroups)
        XCTAssertEqual(all.files.count, 3)
        XCTAssertEqual(all.verificationBytes, 400)
        XCTAssertFalse(plan.removesWholeGroups)
        XCTAssertEqual(plan.verificationBytes, 400)
        let other = try group("b")
        let one = try DuplicateTrashPlan(report: report([value, other]), paths: [value.files[0].path])
        XCTAssertEqual(one.files.map(\.path), [value.files[0].path])
    }
    func testInvalidGroupsAndOutOfScopePathsCannotBecomeAReviewPlan() throws {
        let original = try group()
        var sameIdentity = original
        sameIdentity.files[1].inode = sameIdentity.files[0].inode
        var wrongSize = original
        wrongSize.files[1].bytes = 101
        var outside = original
        outside.files[1].path = "/outside/copy"
        var traversal = original
        traversal.files[1].path = "/Volumes/Synthetic/a/../copy"
        for invalid in [sameIdentity, wrongSize, outside, traversal] {
            XCTAssertThrowsError(try DuplicateTrashPlan(report: report([invalid]), paths: [invalid.files[1].path]))
        }
        XCTAssertThrowsError(
            try DuplicateTrashPlan(report: report([original, original]), paths: [original.files[1].path]))
        var huge = original
        for i in huge.files.indices { huge.files[i].bytes = Int64.max }
        XCTAssertThrowsError(
            try DuplicateTrashPlan(report: report([huge]), paths: Set(huge.files.dropFirst().map(\.path))))
        var zero = original
        for i in zero.files.indices { zero.files[i].bytes = 0 }
        XCTAssertEqual(try DuplicateTrashPlan(report: report([zero]), paths: [zero.files[1].path]).bytes, 0)
    }
    func testReportRemovalAndScopedCountersIncludeNestedPeersWithoutPrefixLeaks() throws {
        var first = try group("project")
        first.preferredPath = first.files[0].path
        let sibling = try group("project-other", copies: 2)
        let source = report([first, sibling])
        let lookup = try DuplicateLookup(source)
        XCTAssertEqual(lookup.count(in: "/Volumes/Synthetic/project", directory: true), 3)
        XCTAssertEqual(lookup.count(in: "/Volumes/Synthetic", directory: true), 5)
        XCTAssertEqual(lookup.count(in: "/", directory: true), 5)
        XCTAssertEqual(lookup.count(in: first.files[0].path, directory: false), 1)
        XCTAssertEqual(lookup.count(in: "/unknown", directory: false), 0)
        XCTAssertEqual(lookup.count(in: "/unknown", directory: true), 0)
        XCTAssertEqual(lookup.groups(in: "/Volumes/Synthetic/project").map(\.id), [first.id])
        XCTAssertEqual(lookup.groups(in: first.files[0].path).map(\.id), [first.id])
        XCTAssertEqual(lookup.groups(in: "/").count, 2)
        let remaining = source.removing([first.files[0].path])
        XCTAssertNil(remaining.groups[0].preferredPath)
        XCTAssertEqual(remaining.groups[0].displayName, "copy-1.dat")
        XCTAssertEqual(remaining.groups[0].locations, ["project"])
        XCTAssertEqual(remaining.repeatedBytes, 200)
        let final = remaining.removing([first.files[1].path])
        XCTAssertEqual(final.groups.map(\.id), [sibling.id])
        XCTAssertEqual(try DuplicateLookup(final).count(in: "/Volumes/Synthetic/project", directory: true), 0)
        XCTAssertEqual(source.groups[0].files.count, 3)
    }
    func testReconfirmationRejectsChangedFilesAndCancellationWithoutWrites() throws {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(repeating: 41, count: 2_100_000)
        for name in ["a", "b"] { try data.write(to: root.appendingPathComponent(name)) }
        let finder = DuplicateFinder()
        let snapshot = try DiskScanner().scan(path: root.path)
        let result = try finder.run(finder.prepare(snapshot, options: DuplicateOptions()))
        let a = result.groups[0].files[0]
        let b = result.groups[0].files[1]
        let plan = try DuplicateTrashPlan(report: result, paths: [b.path])
        XCTAssertEqual(plan.files.count, 1)
        var read = 0
        XCTAssertTrue(try finder.confirm(b, matches: a, control: DuplicateControl(), advanced: { read += $0 }))
        XCTAssertEqual(read, data.count * 2)
        var differentSize = b
        differentSize.bytes += 1
        XCTAssertFalse(try finder.confirm(differentSize, matches: a, control: DuplicateControl()))
        let cancelled = DuplicateControl()
        cancelled.cancel()
        XCTAssertThrowsError(try finder.confirm(b, matches: a, control: cancelled))
        try Data(repeating: 42, count: data.count).write(to: URL(fileURLWithPath: b.path))
        XCTAssertThrowsError(try finder.confirm(b, matches: a, control: DuplicateControl()))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: a.path)), data)
    }
}
