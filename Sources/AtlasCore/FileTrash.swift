import Darwin
import Foundation

/// Review captures current identities. Moving never follows a replaced parent or target.
public struct FileTrashItem: Identifiable, Sendable {
    public var id: Int { entry.id }
    public let entry: Entry
    private let device: Int32
    private let inode: UInt64
    private let mode: UInt16
    private let modified: timespec
    private let changed: timespec
    private let parentPath: String

    init(_ entry: Entry) throws {
        self.entry = entry
        let info = try Self.info(entry.path)
        try Self.checkSnapshot(entry, info: info)
        device = info.st_dev
        inode = info.st_ino
        mode = info.st_mode
        modified = info.st_mtimespec
        changed = info.st_ctimespec
        parentPath = URL(fileURLWithPath: entry.path).deletingLastPathComponent().resolvingSymlinksInPath().path
    }
    public func validate() throws {
        let info = try Self.info(entry.path)
        let parent = URL(fileURLWithPath: entry.path).deletingLastPathComponent().resolvingSymlinksInPath().path
        guard parent == parentPath, info.st_dev == device, info.st_ino == inode, info.st_mode == mode,
            Self.equal(info.st_mtimespec, modified), Self.equal(info.st_ctimespec, changed)
        else { throw AtlasError.message("Объект изменился. Обнови анализ и проверь выбор ещё раз.") }
    }
    private static func equal(_ a: timespec, _ b: timespec) -> Bool { a.tv_sec == b.tv_sec && a.tv_nsec == b.tv_nsec }
    private static func info(_ path: String) throws -> stat {
        var value = stat()
        guard path.withCString({ lstat($0, &value) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
        }
        return value
    }
    private static func checkSnapshot(_ entry: Entry, info: stat) throws {
        let type = info.st_mode & S_IFMT
        let expected = entry.isDirectory ? S_IFDIR : entry.kind == .link ? S_IFLNK : S_IFREG
        let date = Double(info.st_mtimespec.tv_sec)
        guard type == expected, abs(date - entry.modified.timeIntervalSince1970) < 0.001 else {
            throw AtlasError.message("Объект изменился после анализа. Обнови анализ перед переносом в Корзину.")
        }
        if type == S_IFREG && !entry.sharedLink && info.st_size != entry.logicalBytes {
            throw AtlasError.message("Размер файла изменился. Обнови анализ перед переносом в Корзину.")
        }
    }
}

public struct FileTrashPlan: Identifiable, Sendable {
    public let id = UUID()
    public let items: [FileTrashItem]
    public var hasFolders: Bool { items.contains { $0.entry.isDirectory } }
    public var bytes: Int64 { items.reduce(0) { $0 + $1.entry.bytes } }

    public init(snapshot: Snapshot, selected: Set<Int>) throws {
        guard !selected.isEmpty, selected.allSatisfy(snapshot.entries.indices.contains) else {
            throw AtlasError.message("Выбери файлы или папки для корзины.")
        }
        for id in selected { try Self.validatePath(snapshot.entries[id], snapshot: snapshot) }
        items = try FileTrashSelection.roots(in: snapshot, selected: selected).map(FileTrashItem.init)
    }
    private static func validatePath(_ entry: Entry, snapshot: Snapshot) throws {
        let url = URL(fileURLWithPath: entry.path)
        guard entry.path.hasPrefix("/"), !entry.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
            entry.path != "/", !(snapshot.isComposite && entry.id == 0),
            snapshot.scanRoots.contains(where: { $0 == "/" || entry.path == $0 || entry.path.hasPrefix($0 + "/") })
        else { throw AtlasError.message("Объект вне области анализа.") }
        if entry.isDirectory, try url.resourceValues(forKeys: [.isVolumeKey]).isVolume == true {
            throw AtlasError.message("Том нельзя переместить в Корзину.")
        }
    }
}
