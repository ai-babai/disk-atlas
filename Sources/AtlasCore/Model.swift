import Darwin
import Foundation

public enum FileKind: String, Codable, CaseIterable, Sendable {
    case folder, video, audio, image, document, archive, code, other, link

    public var title: String {
        switch self {
        case .folder: return L10n.text("Папки")
        case .video: return L10n.text("Видео")
        case .audio: return L10n.text("Аудио")
        case .image: return L10n.text("Изображения")
        case .document: return L10n.text("Документы")
        case .archive: return L10n.text("Архивы")
        case .code: return L10n.text("Код и данные")
        case .other: return L10n.text("Остальное")
        case .link: return L10n.text("Ссылки")
        }
    }

    public static func classify(_ url: URL) -> FileKind { FileFormat.kind(url) }
}

public struct Entry: Codable, Identifiable, Sendable {
    public var id: Int
    public var parent: Int?
    public var name: String
    public var path: String
    public var kind: FileKind
    public var bytes: Int64
    public var logicalBytes: Int64
    public var fileCount: Int
    public var modified: Date
    public var created: Date? = nil
    public var sharedLink: Bool
    public var children: [Int]
    public var cloudOnly: Bool? = nil
    public var isDirectory: Bool { kind == .folder }
    // Running estimate of the uncompressed snapshot, not RAM or source-file size.
    public var estimatedMetadataBytes: Int64 { Int64(220 + name.utf8.count + path.utf8.count) }
}

public struct ScanIssue: Codable, Sendable {
    public var path: String
    public var message: String
}

public struct ScanProgress: Sendable {
    public var entries: Int
    public var bytes: Int64
    public var currentPath: String
    public var metadataBytes: Int64 = 0
}

public struct Snapshot: Codable, Sendable {
    public var version: Int = 1
    public var root: String
    public var roots: [String]?
    public var created: Date
    public var elapsed: Double
    public var volumeTotal: Int64
    public var volumeFree: Int64
    public var entries: [Entry]
    public var issues: [ScanIssue]
    public var issueCount: Int
    public var cancelled: Bool
    public var rootEntry: Entry { entries[0] }
    public var scanRoots: [String] { roots ?? [root] }
    public var isComposite: Bool { scanRoots.count > 1 }

    public func children(of id: Int, logical: Bool = false) -> [Entry] {
        entries[id].children.map { entries[$0] }.sorted {
            let a = logical ? $0.logicalBytes : $0.bytes
            let b = logical ? $1.logicalBytes : $1.bytes
            return a == b ? $0.path < $1.path : a > b
        }
    }

    public func descendants(of id: Int) -> [Entry] {
        let prefix = entries[id].path == "/" ? "/" : entries[id].path + "/"
        return entries.filter { $0.id != id && $0.path.hasPrefix(prefix) }
    }

    public func save(to url: URL, overwrite: Bool = false) throws {
        let data = try Self.encoder.encode(self)
        // Snapshot paths can be private. New exports are owner-readable only and
        // O_EXCL makes the no-overwrite promise atomic, including symlink targets.
        if overwrite {
            // Only the GUI calls this after NSSavePanel's explicit replacement confirmation.
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            let fd = url.withUnsafeFileSystemRepresentation {
                open($0!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            }
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
        }
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func load(from url: URL) throws -> Snapshot {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 2 * 1024 * 1024 * 1024 else {
            throw AtlasError.message("Нужен обычный файл снимка размером до 2 ГБ.")
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= 2 * 1024 * 1024 * 1024 else {
            throw AtlasError.message("Нужен обычный файл снимка размером до 2 ГБ.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.version == 1, !snapshot.entries.isEmpty, snapshot.entries[0].parent == nil,
            snapshot.entries[0].isDirectory, snapshot.entries[0].path == snapshot.root
        else { throw AtlasError.message("Неподдерживаемый или повреждённый снимок.") }
        try snapshot.validateEntries()
        snapshot.refreshFileKinds()
        return snapshot
    }
}

public enum AtlasError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return L10n.text(text)
        }
    }
}

public func byteString(_ value: Int64) -> String {
    guard value >= 1000 else { return "\(value) B" }
    let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
    var amount = Double(value)
    var unit = 0
    while amount >= 1000 && unit < units.count - 1 {
        amount /= 1000
        unit += 1
    }
    let decimals = amount >= 100 ? 0 : amount >= 10 ? 1 : 2
    let number = String(format: "%.*f", decimals, amount)
    return "\(L10n.language == "ru" ? number.replacingOccurrences(of: ".", with: ",") : number) \(units[unit])"
}
