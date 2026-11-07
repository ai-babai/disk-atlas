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

    public static func classify(_ url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return .video
        case "mp3", "wav", "flac", "aac", "m4a", "aiff", "ogg": return .audio
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "psd", "raw", "svg": return .image
        case "pdf", "doc", "docx", "txt", "md", "pages", "pptx", "xlsx", "epub", "rtf": return .document
        case "zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "xz": return .archive
        case "swift", "rs", "js", "ts", "tsx", "py", "json", "csv", "db", "sqlite", "bin", "gguf", "safetensors", "c",
            "h", "cpp", "o", "a", "dylib", "html", "css", "yaml", "toml":
            return .code
        default: return .other
        }
    }
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
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.version == 1, !snapshot.entries.isEmpty, snapshot.entries[0].parent == nil,
            snapshot.entries[0].isDirectory, snapshot.entries[0].path == snapshot.root
        else { throw AtlasError.message("Неподдерживаемый или повреждённый снимок.") }
        // The parent-before-child invariant makes cycles impossible and keeps UI navigation safe.
        var linked = Set<Int>()
        for (index, entry) in snapshot.entries.enumerated() {
            guard entry.id == index, entry.bytes >= 0, entry.logicalBytes >= 0, entry.fileCount >= 0,
                entry.path.hasPrefix("/"),
                index == 0 || (entry.parent != nil && entry.parent! >= 0 && entry.parent! < index),
                entry.isDirectory || entry.children.isEmpty
            else { throw AtlasError.message("Нарушена структура снимка.") }
            for child in entry.children {
                guard child > index, child < snapshot.entries.count, snapshot.entries[child].parent == index,
                    linked.insert(child).inserted
                else { throw AtlasError.message("Нарушены связи снимка.") }
            }
        }
        guard linked.count == snapshot.entries.count - 1, !snapshot.scanRoots.isEmpty,
            snapshot.scanRoots.allSatisfy({ $0.hasPrefix("/") })
        else { throw AtlasError.message("В снимке есть несвязанные объекты.") }
        for entry in snapshot.entries where entry.isDirectory {
            var bytes: Int64 = 0
            var logical: Int64 = 0
            var files = 0
            for child in entry.children {
                let next = snapshot.entries[child]
                let b = bytes.addingReportingOverflow(next.bytes)
                let l = logical.addingReportingOverflow(next.logicalBytes)
                let f = files.addingReportingOverflow(next.fileCount)
                guard !b.overflow, !l.overflow, !f.overflow else {
                    throw AtlasError.message("Повреждены размеры снимка.")
                }
                bytes = b.partialValue
                logical = l.partialValue
                files = f.partialValue
            }
            guard bytes == entry.bytes, logical == entry.logicalBytes, files == entry.fileCount else {
                throw AtlasError.message("Итоги снимка не совпадают с содержимым.")
            }
        }
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
