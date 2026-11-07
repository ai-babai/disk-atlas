import XCTest

@testable import AtlasCore

final class MapSelectionTests: XCTestCase {
    func testSelectionFollowsParentIDsWithoutChangingMapScope() {
        var snapshot = Fixtures.snapshot([900, 700, 500, 400])
        snapshot.entries[0].children = [1, 4]
        snapshot.entries[1].kind = .folder
        snapshot.entries[1].children = [2]
        snapshot.entries[2].parent = 1
        snapshot.entries[2].kind = .folder
        snapshot.entries[2].children = [3]
        snapshot.entries[3].parent = 2
        let index = PresentationIndex(snapshot)
        XCTAssertEqual(index.mapSelectionAncestors(3, within: 0), [1, 2, 3])
        XCTAssertEqual(index.mapSelectionAncestors(3, within: 1), [2, 3])
        XCTAssertEqual(index.mapSelectionAncestors(3, within: 2), [3])
        XCTAssertEqual(index.mapSelectionAncestors(4, within: 1), [])
        XCTAssertEqual(index.snapshot.entries[3].parent, 2)
        XCTAssertEqual(index.snapshot.entries[0].children, [1, 4])
    }
    func testEmptyCurrentRootAndInvalidSelectionsHaveNoHighlightBranch() {
        let index = PresentationIndex(Fixtures.snapshot([900, 700]))
        XCTAssertEqual(index.mapSelectionAncestors(nil, within: 0), [])
        XCTAssertEqual(index.mapSelectionAncestors(0, within: 0), [])
        XCTAssertEqual(index.mapSelectionAncestors(-1, within: 0), [])
        XCTAssertEqual(index.mapSelectionAncestors(100, within: 0), [])
        XCTAssertEqual(index.mapSelectionAncestors(1, within: 100), [])
    }
}
