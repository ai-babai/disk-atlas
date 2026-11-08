import XCTest

@testable import AtlasCore

final class FileTypeTests: XCTestCase {
    func testCommonFormatsAndAmbiguitiesWithoutReadingFiles() {
        let examples: [(FileKind, [String])] = [
            (.video, ["holiday.MPEG", "clip.m2ts"]), (.audio, ["voice.OPUS", "track.aif"]),
            (.image, ["photo.HEIF", "scan.tif", "camera.CR3"]),
            (.document, ["budget.numbers", "slides.ODP", "notes.markdown"]),
            (.archive, ["backup.tar.zst", "disk.vhdx", "Docker.raw"]),
            (
                .code,
                ["Dockerfile", "Makefile", "CMakeLists.txt", "view.jsx", "config.yml", "model.onnx", "data.parquet"]
            ), (.other, ["camera.raw", "segment.ts", "README", "unknown.newformat"]),
        ]
        for (kind, names) in examples {
            for name in names {
                XCTAssertEqual(FileKind.classify(URL(fileURLWithPath: "/not-present/" + name)), kind, name)
            }
        }
        XCTAssertEqual(FileKind.classify(URL(fileURLWithPath: "/not-present/weights.bin")), .code)
        XCTAssertNil(FileFormat.detail("weights.bin"))
        XCTAssertEqual(FileFormat.extensionKey("/not-present/IMAGE.PNG"), "png")
        XCTAssertEqual(FileFormat.extensionTitle("png"), ".png")
        XCTAssertFalse(FileFormat.extensionTitle("").isEmpty)
    }

    func testFunctionalHintsDoNotChangePhysicalDirectoryIdentity() {
        for name in [
            "Editor.app", "Library.framework", "Plugin.bundle", "Photos.photoslibrary", "Mac.pvm", "Disk.sparsebundle",
        ] { XCTAssertNotNil(FileFormat.detail(name, directory: true), name) }
        XCTAssertNil(FileFormat.detail("ordinary.folder", directory: true))
        XCTAssertNil(FileFormat.detail("fake.app", directory: false))
        for name in ["mac.dmg", "linux.qcow2", "model.gguf", "store.sqlite3", "data.arrow", "camera.raw", "segment.ts"]
        { XCTAssertNotNil(FileFormat.detail(name), name) }
    }

    private func scanned() throws -> Snapshot {
        let root = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Editor.app")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let files = [("photo.PNG", 13), ("second.png", 7), ("README", 5), ("Makefile", 3), ("camera.raw", 11)]
        for (name, count) in files {
            try Data(repeating: 42, count: count).write(to: root.appendingPathComponent(name))
        }
        try Data(repeating: 7, count: 17).write(to: package.appendingPathComponent("icon.png"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("alias.png").path, withDestinationPath: "photo.PNG")
        return try DiskScanner().scan(path: root.path)
    }

    func testExtensionTotalsAndQueriesAgreeAcrossNestedPackagesAndSizeMetrics() throws {
        let snapshot = try scanned()
        let index = PresentationIndex(snapshot)
        let images = index.extensions(of: 0, kind: .image, logical: true)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].suffix, "png")
        XCTAssertEqual(images[0].count, 3)
        XCTAssertEqual(images[0].bytes, 37)
        let unknown = index.extensions(of: 0, kind: .other, logical: true)
        XCTAssertEqual(unknown.map(\.suffix), ["raw", ""])
        XCTAssertEqual(unknown.map(\.bytes), [11, 5])
        XCTAssertEqual(unknown.map(\.count), [1, 1])
        let package = try XCTUnwrap(snapshot.entries.first { $0.name == "Editor.app" })
        XCTAssertTrue(package.isDirectory)
        XCTAssertEqual(index.extensions(of: package.id, kind: .image, logical: true).first?.bytes, 17)
        XCTAssertEqual(index.extensions(of: -1, kind: .image, logical: false).count, 0)
        XCTAssertEqual(index.extensions(of: package.id, kind: .audio, logical: true).count, 0)
        let rows = index.rows(
            folder: 0, logical: true, query: "", kinds: [.image], filesOnly: false, extensionFilter: "PNG")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.entries.map(\.name), ["icon.png", "photo.PNG", "second.png"])
        let allocated = index.extensions(of: 0, kind: .image, logical: false)
        XCTAssertEqual(allocated[0].bytes, rows.entries.reduce(0) { $0 + $1.bytes })
        XCTAssertEqual(
            index.rows(
                folder: 0, logical: true, query: "photo", kinds: [.image], filesOnly: true, extensionFilter: "png"
            ).count, 1)
        XCTAssertEqual(
            index.rows(folder: 0, logical: true, query: "", kinds: [], filesOnly: false, extensionFilter: "").count, 2)
        XCTAssertEqual(
            index.rows(
                folder: package.id, logical: true, query: "", kinds: [], filesOnly: false, limit: 0,
                extensionFilter: "png"
            ).count, 1)
    }

    func testLegacySnapshotsReclassifyWithoutSourcesAndKeepLinksFoldersAndTotals() throws {
        var original = try scanned()  // Sources are removed before decoding below.
        for i in original.entries.indices where !original.entries[i].isDirectory && original.entries[i].kind != .link {
            original.entries[i].kind = .other
        }
        let decoded = try Snapshot.decode(Snapshot.encoder.encode(original))
        XCTAssertEqual(decoded.entries.first { $0.name == "photo.PNG" }?.kind, .image)
        XCTAssertEqual(decoded.entries.first { $0.name == "Makefile" }?.kind, .code)
        XCTAssertEqual(decoded.entries.first { $0.name == "alias.png" }?.kind, .link)
        XCTAssertEqual(decoded.entries.first { $0.name == "Editor.app" }?.kind, .folder)
        XCTAssertEqual(decoded.rootEntry.bytes, original.rootEntry.bytes)
        XCTAssertEqual(decoded.rootEntry.fileCount, original.rootEntry.fileCount)
    }

    func testReclassificationStillRejectsInvalidSnapshotStructureAndTotals() throws {
        let original = Fixtures.snapshot([10, 20])
        let corruptions: [(inout Snapshot) -> Void] = [
            { $0.entries[1].id = 0 }, { $0.entries[1].bytes = -1 }, { $0.entries[1].parent = 2 },
            { $0.entries[0].children = [1, 1] }, { $0.entries[0].children = [1] }, { $0.roots = [] },
            { $0.entries[0].bytes += 1 }, { $0.entries[1].bytes = .max },
        ]
        for corrupt in corruptions {
            var value = original
            corrupt(&value)
            XCTAssertThrowsError(try Snapshot.decode(Snapshot.encoder.encode(value)))
        }
    }

    func testCancelledExtensionSummaryNeverPublishesPartialTotals() async throws {
        let index = PresentationIndex(try scanned())
        let job = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return index.extensions(of: 0, kind: .image, logical: true)
        }
        let values = await job.value
        XCTAssertTrue(values.isEmpty)
    }
}
