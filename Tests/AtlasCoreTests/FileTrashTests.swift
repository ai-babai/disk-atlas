import XCTest

@testable import AtlasCore

final class FileTrashTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = try Fixtures.directory().resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: root.appendingPathComponent("Folder/a.txt"))
        try Data("second".utf8).write(to: root.appendingPathComponent("b.txt"))
        return root
    }
    func testReviewNormalizesFolderChildOverlapAndValidatesWithoutMoving() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try DiskScanner().scan(path: root.path)
        let selected = Set(snapshot.entries.dropFirst().map(\.id))
        let plan = try FileTrashPlan(snapshot: snapshot, selected: selected)
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertTrue(plan.hasFolders)
        XCTAssertGreaterThan(plan.bytes, 0)
        for item in plan.items { try item.validate() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Folder/a.txt").path))
        XCTAssertThrowsError(try FileTrashPlan(snapshot: snapshot, selected: []))
        XCTAssertThrowsError(try FileTrashPlan(snapshot: snapshot, selected: [-1]))
        XCTAssertThrowsError(try FileTrashPlan(snapshot: snapshot, selected: [100]))
    }
    func testChangedOrReplacedFilesAreRejectedAfterReview() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try DiskScanner().scan(path: root.path)
        let file = try XCTUnwrap(snapshot.entries.first { $0.name == "b.txt" })
        let plan = try FileTrashPlan(snapshot: snapshot, selected: [file.id])
        try Data("changed contents".utf8).write(to: URL(fileURLWithPath: file.path))
        XCTAssertThrowsError(try plan.items[0].validate())
        XCTAssertThrowsError(try FileTrashPlan(snapshot: snapshot, selected: [file.id]))
        try FileManager.default.removeItem(atPath: file.path)
        XCTAssertThrowsError(try plan.items[0].validate())
        XCTAssertThrowsError(try FileTrashPlan(snapshot: snapshot, selected: [file.id]))
    }
    func testForgedPathsTypesAndSizesCannotEnterReview() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try DiskScanner().scan(path: root.path)
        let file = try XCTUnwrap(snapshot.entries.first { $0.name == "b.txt" })
        var value = snapshot
        value.entries[file.id].logicalBytes += 1
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [file.id]))
        value.entries[file.id] = file
        value.entries[file.id].kind = .folder
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [file.id]))
        value.entries[file.id].path = "/"
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [file.id]))
        value.entries[file.id].path = root.path + "/../elsewhere"
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [file.id]))
        value.entries[file.id].path = "/outside-root"
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [file.id]))
        value.roots = [root.path, "/other"]
        XCTAssertThrowsError(try FileTrashPlan(snapshot: value, selected: [0]))
    }
    func testParentRedirectAndSymlinkTargetAreHandledAsDistinctObjects() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("b.txt"))
        let snapshot = try DiskScanner().scan(path: root.path)
        let entry = try XCTUnwrap(snapshot.entries.first { $0.name == "link" })
        let plan = try FileTrashPlan(snapshot: snapshot, selected: [entry.id])
        try plan.items[0].validate()
        let file = try XCTUnwrap(snapshot.entries.first { $0.name == "a.txt" })
        let nestedPlan = try FileTrashPlan(snapshot: snapshot, selected: [file.id])
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("Folder"), to: root.appendingPathComponent("Moved"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Folder"), withDestinationURL: root.appendingPathComponent("Moved"))
        XCTAssertThrowsError(try nestedPlan.items[0].validate())
    }
}
