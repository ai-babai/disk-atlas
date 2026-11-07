import XCTest

@testable import AtlasCore

final class MapSelectionRowTests: XCTestCase {
    private func nestedSnapshot() -> Snapshot {
        var value = Fixtures.snapshot([900, 700, 500, 400, 300, 200])
        value.entries[0].children = [1, 4, 5, 6]
        value.entries[1].kind = .folder
        value.entries[1].children = [2]
        value.entries[2].parent = 1
        value.entries[2].kind = .folder
        value.entries[2].children = [3]
        value.entries[2].path = value.entries[1].path + "/Nested"
        value.entries[3].parent = 2
        value.entries[3].path = value.entries[2].path + "/movie.mov"
        value.entries[3].kind = .video
        return value
    }

    func testOrdinaryFolderListRevealsNestedFolderBesideVisibleAncestor() {
        let index = PresentationIndex(nestedSnapshot())
        let original = index.rows(folder: 0, logical: false, query: "", kind: nil, filesOnly: false, limit: 2)
        XCTAssertEqual(original.entries.map(\.id), [1, 4])
        let revealed = index.revealingMapSelection(2, folder: 0, in: original.entries)
        XCTAssertEqual(revealed.map(\.id), [1, 2, 4])
        XCTAssertEqual(revealed[1].parent, 1)
        XCTAssertEqual(original.count, 4)
        XCTAssertEqual(original.entries.map(\.id), [1, 4])
        XCTAssertEqual(index.revealingMapSelection(nil, folder: 0, in: original.entries).map(\.id), [1, 4])
    }

    func testRevealKeepsFilteredResultsAndBoundsContextToOneRow() {
        let index = PresentationIndex(nestedSnapshot())
        let matching = index.rows(folder: 0, logical: false, query: "", kinds: [.document], filesOnly: true, limit: 1)
        let result = index.revealingMapSelection(3, folder: 0, in: matching.entries)
        XCTAssertEqual(result.map(\.id), [3, 4])
        XCTAssertEqual(matching.count, 3)
        let replaced = index.revealingMapSelection(2, folder: 0, in: matching.entries)
        XCTAssertEqual(replaced.map(\.id), [2, 4])
        let empty = index.revealingMapSelection(3, folder: 0, in: [])
        XCTAssertEqual(empty.map(\.id), [3])
        let childScope = index.revealingMapSelection(3, folder: 1, in: [index.snapshot.entries[2]])
        XCTAssertEqual(childScope.map(\.id), [2, 3])
    }

    func testVisibleInvalidAndOutOfScopeSelectionsCannotDuplicateOrLeakRows() {
        let index = PresentationIndex(nestedSnapshot())
        let rows = [index.snapshot.entries[3]]
        for id in [nil, -1, 100, 0, 1, 3, 4] as [Int?] {
            XCTAssertEqual(index.revealingMapSelection(id, folder: 2, in: rows).map(\.id), [3])
        }
        let all = index.rows(folder: 0, logical: true, query: "", kind: nil, filesOnly: false).entries
        for id in 1..<index.snapshot.entries.count {
            let result = index.revealingMapSelection(id, folder: 0, in: all)
            XCTAssertEqual(result.filter { $0.id == id }.count, 1)
            XCTAssertLessThanOrEqual(result.count, all.count + 1)
            XCTAssertEqual(result.filter { $0.id != id }.map(\.id), all.filter { $0.id != id }.map(\.id))
        }
    }
}
