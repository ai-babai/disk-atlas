import Foundation

/// Name-based hints only: never opens files or asks the filesystem to resolve a type.
public enum FileFormat {
    public static func extensionKey(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }
    public static func extensionTitle(_ key: String) -> String { key.isEmpty ? L10n.text("Без расширения") : "." + key }
    static func kind(_ url: URL) -> FileKind {
        if let kind = namedKind(url.lastPathComponent.lowercased()) { return kind }
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "mpg", "mpeg", "mts", "m2ts", "flv": return .video
        case "mp3", "wav", "flac", "aac", "m4a", "aiff", "aif", "ogg", "opus", "wma": return .audio
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "psd", "svg", "bmp", "dng", "cr2",
            "cr3", "nef", "arw":
            return .image
        case "pdf", "doc", "docx", "txt", "md", "markdown", "pages", "ppt", "pptx", "xls", "xlsx", "numbers", "key",
            "epub", "rtf", "odt", "ods", "odp", "log":
            return .document
        case "zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "xz", "bz2", "zst", "zstd", "tgz", "tbz2", "img",
            "qcow2", "vmdk", "vdi", "vhd", "vhdx", "sparseimage":
            return .archive
        case "swift", "rs", "js", "jsx", "mjs", "cjs", "tsx", "py", "json", "csv", "db", "sqlite", "sqlite3", "bin",
            "gguf", "safetensors", "onnx", "pt", "pth", "ckpt", "parquet", "arrow", "npy", "npz", "h5", "hdf5", "c",
            "h", "cpp", "o", "a", "dylib", "html", "css", "yaml", "yml", "toml", "xml", "go", "java", "kt", "sql":
            return .code
        default: return .other
        }
    }
    private static func namedKind(_ name: String) -> FileKind? {
        switch name {
        case "docker.raw": return .archive
        case "dockerfile", "makefile", "cmakelists.txt": return .code
        default: return nil
        }
    }
    /// A functional hint separate from folder/link identity and content totals.
    public static func detail(_ path: String, directory: Bool = false) -> String? {
        if !directory && (path as NSString).lastPathComponent.lowercased() == "docker.raw" {
            return L10n.text("Образ диска")
        }
        let key = extensionKey(path)
        let title = directory ? packageTitle(key) : fileTitle(key)
        return title.map(L10n.text)
    }
    private static func packageTitle(_ key: String) -> String? {
        switch key {
        case "app": return "Приложение"
        case "framework", "bundle": return "Пакет"
        case "photoslibrary", "photolibrary": return "Медиатека"
        case "pvm", "vmwarevm": return "Виртуальная машина"
        case "sparsebundle": return "Образ диска"
        default: return nil
        }
    }
    private static func fileTitle(_ key: String) -> String? {
        switch key {
        case "dmg", "iso", "img", "sparseimage": return "Образ диска"
        case "qcow2", "vmdk", "vdi", "vhd", "vhdx": return "Диск виртуальной машины"
        case "gguf", "safetensors", "onnx", "pt", "pth", "ckpt": return "Модель ИИ"
        case "db", "sqlite", "sqlite3": return "База данных"
        case "csv", "parquet", "arrow", "npy", "npz", "h5", "hdf5": return "Набор данных"
        case "raw": return "RAW: фото или образ диска"
        case "ts": return "TS: TypeScript или видео"
        default: return nil
        }
    }
}
