import XCTest

@testable import AtlasCore

final class DuplicateOrderingTests: XCTestCase {
    func testEachKeyHasIndependentMeaningAndDirection() throws {
        let a = try Fixtures.group(id: "a", bytes: 100, copies: 5, name: "Alpha")
        let b = try Fixtures.group(id: "b", bytes: 300, copies: 2, name: "Beta")
        let c = try Fixtures.group(id: "c", bytes: 200, copies: 3, name: "Gamma")
        let input = [b, c, a]
        XCTAssertEqual(try DuplicateSort.repeatedBytes.ordered(input, descending: true).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(try DuplicateSort.fileBytes.ordered(input, descending: true).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(try DuplicateSort.copies.ordered(input, descending: true).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(try DuplicateSort.name.ordered(input, descending: false).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(try DuplicateSort.fileBytes.ordered(input, descending: false).map(\.id), ["a", "c", "b"])
    }
    func testGeneratedOrdersPreservePermutationMonotonicityAndTies() throws {
        var random = SeededRandom()
        let groups = try (0..<96).map { i in
            try Fixtures.group(
                id: String(format: "%04d", i), bytes: Int64(random.next() % 1000), copies: Int(random.next() % 5) + 2,
                name: "item-\(random.next()%20)")
        }
        for key in DuplicateSort.allCases {
            for descending in [true, false] {
                let ordered = try key.ordered(groups.shuffled(using: &random), descending: descending)
                XCTAssertEqual(Set(ordered.map(\.id)), Set(groups.map(\.id)))
                XCTAssertEqual(ordered.count, groups.count)
                XCTAssertEqual(try key.ordered(ordered, descending: descending).map(\.id), ordered.map(\.id))
                for (a, b) in zip(ordered, ordered.dropFirst()) {
                    if key == .name {
                        let comparison = a.displayName!.localizedStandardCompare(b.displayName!)
                        XCTAssertNotEqual(comparison, descending ? .orderedAscending : .orderedDescending)
                        if comparison == .orderedSame { XCTAssertLessThan(a.id, b.id) }
                    } else {
                        let amount: (DuplicateGroup) -> Int64 = { group in
                            switch key {
                            case .repeatedBytes: return group.repeatedBytes
                            case .fileBytes: return group.fileBytes
                            default: return Int64(group.files.count)
                            }
                        }
                        if descending {
                            XCTAssertGreaterThanOrEqual(amount(a), amount(b))
                        } else {
                            XCTAssertLessThanOrEqual(amount(a), amount(b))
                        }
                        if amount(a) == amount(b) { XCTAssertLessThan(a.id, b.id) }
                    }
                }
            }
        }
    }
    func testEmptyMissingNamesAndLocalizedLabels() throws {
        let empty = DuplicateGroup(id: "empty", files: [])
        let fallback = try Fixtures.group(id: "fallback", bytes: 0, copies: 2)
        for key in DuplicateSort.allCases {
            XCTAssertTrue(try key.ordered([], descending: true).isEmpty)
            XCTAssertEqual(try key.ordered([empty], descending: false).first?.id, "empty")
            _ = try key.ordered([empty, fallback], descending: false)
        }
        let previous = L10n.language
        defer { L10n.language = previous }
        for language in ["en", "ru"] {
            L10n.language = language
            for key in DuplicateSort.allCases { XCTAssertFalse(key.title.isEmpty) }
        }
    }
    func testCancelledLargeSortStops() async throws {
        let sample = try Fixtures.group(id: "seed", bytes: 1, copies: 2)
        let values = (0..<4000).map { n -> DuplicateGroup in
            var value = sample
            value.id = String(n)
            return value
        }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DuplicateSort.name.ordered(values, descending: false)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled sort must stop")
        } catch is CancellationError {}
    }
}
