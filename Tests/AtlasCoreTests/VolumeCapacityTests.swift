import XCTest

@testable import AtlasCore

final class VolumeCapacityTests: XCTestCase {
    func testStartupCapacityReadsMountedVolumeWithoutScanning() throws {
        let volume = try VolumeCapacity.read()
        XCTAssertFalse(volume.name.isEmpty)
        XCTAssertGreaterThan(volume.total, 0)
        XCTAssertGreaterThanOrEqual(volume.available, 0)
        XCTAssertLessThanOrEqual(volume.available, volume.total)
    }
    func testMissingVolumeDoesNotProduceFabricatedCapacity() {
        XCTAssertThrowsError(try VolumeCapacity.read(at: URL(fileURLWithPath: "/missing-" + UUID().uuidString)))
    }
}
