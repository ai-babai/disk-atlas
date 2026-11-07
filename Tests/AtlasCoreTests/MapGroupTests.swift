import XCTest

@testable import AtlasCore

final class MapGroupTests: XCTestCase {
    func testGroupContainsOnlyOmittedChildrenAndTheirOwnDescendants() {
        var snapshot = Fixtures.snapshot([900, 700, 500, 400])
        snapshot.entries[0].children = [1, 3, 4]
        snapshot.entries[1].kind = .folder
        snapshot.entries[1].children = [2]
        snapshot.entries[2].parent = 1
        snapshot.entries[2].kind = .video
        let index = PresentationIndex(snapshot)
        let group = MapGroup(snapshot: snapshot, parent: 0, visible: [3, -1], logical: false)
        XCTAssertEqual(group.roots, [1, 4])
        XCTAssertEqual(group.bytes, 1300)
        XCTAssertFalse(group.title.isEmpty)
        let direct = index.rows(
            folder: 0, logical: false, query: "", kinds: [], filesOnly: false, groupRoots: group.roots)
        XCTAssertEqual(direct.entries.map(\.id), [1, 4])
        let largest = index.rows(
            folder: 0, logical: false, query: "", kinds: [], filesOnly: true, groupRoots: group.roots)
        XCTAssertEqual(largest.entries.map(\.id), [2, 4])
        let filtered = index.rows(
            folder: 0, logical: true, query: "file", kinds: [.video], filesOnly: true, groupRoots: group.roots)
        XCTAssertEqual(filtered.entries.map(\.id), [2])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(index.snapshot.entries[0].children, [1, 3, 4])
        XCTAssertEqual(
            index.rows(folder: 0, logical: false, query: "absent", kinds: [], filesOnly: false, groupRoots: group.roots)
                .count, 0)
    }
    func testBoundedOrderingMatchesFullResultsAcrossModesAndDirections() {
        var snapshot = Fixtures.snapshot((0..<90).map { Int64($0 % 11) })
        for id in 1..<snapshot.entries.count {
            snapshot.entries[id].created = id % 3 == 0 ? nil : Date(timeIntervalSince1970: Double(id % 7))
            snapshot.entries[id].logicalBytes = Int64(id % 9)
        }
        let index = PresentationIndex(snapshot)
        for sort in EntrySort.allCases {
            for descending in [true, false] { verify(index, sort: sort, descending: descending) }
        }
    }
    private func verify(_ index: PresentationIndex, sort: EntrySort, descending: Bool) {
        let all = index.rows(
            folder: 0, logical: true, query: "file", kinds: [], filesOnly: true, sort: sort, descending: descending)
        let page = index.rows(
            folder: 0, logical: true, query: "file", kinds: [], filesOnly: true, limit: 7, sort: sort,
            descending: descending)
        XCTAssertEqual(page.entries.map(\.id), Array(all.entries.prefix(7)).map(\.id))
        XCTAssertEqual(page.count, 90)
        XCTAssertEqual(Set(all.entries.map(\.id)).count, 90)
        let empty = index.rows(
            folder: 0, logical: false, query: "file", kinds: [], filesOnly: true, limit: 0, sort: sort)
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.count, 90)
    }
    func testRemovalRecountsAncestorsAndKeepsPortableSnapshotValid() throws {
        var snapshot = Fixtures.snapshot([900, 700, 500])
        snapshot.entries[0].children = [1, 3]
        snapshot.entries[1].kind = .folder
        snapshot.entries[1].children = [2]
        snapshot.entries[2].parent = 1
        snapshot.entries[2].path = snapshot.entries[1].path + "/child"
        let updated = snapshot.removingFilePaths([snapshot.entries[1].path])
        XCTAssertEqual(updated.entries[0].children, [1])
        XCTAssertEqual(updated.rootEntry.bytes, 500)
        XCTAssertEqual(updated.rootEntry.fileCount, 1)
        XCTAssertEqual(updated.entries.map(\.id), [0, 1])
        XCTAssertEqual(updated.entries[1].path, snapshot.entries[3].path)
        XCTAssertEqual(try Snapshot.decode(Snapshot.encoder.encode(updated)).entries.count, 2)
        XCTAssertEqual(snapshot.entries[0].children, [1, 3])
        XCTAssertEqual(
            PresentationIndex(updated).rows(folder: 0, logical: false, query: "file", kinds: [], filesOnly: true)
                .entries.map(\.id), [1])
    }
}
