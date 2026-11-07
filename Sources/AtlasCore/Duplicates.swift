import Darwin
import Foundation

public struct DuplicateOptions: Codable, Sendable, Equatable {
    public var minimumBytes: Int64 = 0
    public var maximumBytes: Int64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    public var kinds: Set<FileKind> = []
    public init() {}
    public func matchesDate(_ date: Date) -> Bool {
        (modifiedAfter == nil || date >= modifiedAfter!) && (modifiedBefore == nil || date <= modifiedBefore!)
    }
}

public struct DuplicateFile: Codable, Sendable, Identifiable {
    public var path: String
    public var bytes: Int64
    public var modified: Date
    public var created: Date
    public var device: Int32
    public var inode: UInt64
    public var modifiedSeconds: Int64
    public var modifiedNanos: Int64
    public var changedSeconds: Int64
    public var changedNanos: Int64
    public var id: String { path }
    private enum CodingKeys: String, CodingKey {
        case path, bytes, modified, created, device, inode, modifiedSeconds, modifiedNanos, changedSeconds, changedNanos
    }
    public func encode(to encoder: Encoder) throws {
        try Task.checkCancellation()
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(path, forKey: .path)
        try value.encode(bytes, forKey: .bytes)
        try value.encode(modified, forKey: .modified)
        try value.encode(created, forKey: .created)
        try value.encode(device, forKey: .device)
        try value.encode(inode, forKey: .inode)
        try value.encode(modifiedSeconds, forKey: .modifiedSeconds)
        try value.encode(modifiedNanos, forKey: .modifiedNanos)
        try value.encode(changedSeconds, forKey: .changedSeconds)
        try value.encode(changedNanos, forKey: .changedNanos)
    }
    fileprivate init(path: String, info: stat) {
        self.path = path
        bytes = info.st_size
        modified = Date(
            timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec))
        device = info.st_dev
        inode = info.st_ino
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanos = Int64(info.st_ctimespec.tv_nsec)
    }
    fileprivate func matches(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_flags & UInt32(SF_DATALESS) == 0 && device == info.st_dev
            && inode == info.st_ino && bytes == info.st_size && modifiedSeconds == Int64(info.st_mtimespec.tv_sec)
            && modifiedNanos == info.st_mtimespec.tv_nsec && changedSeconds == info.st_ctimespec.tv_sec
            && changedNanos == info.st_ctimespec.tv_nsec
    }
}

public struct DuplicateGroup: Codable, Sendable, Identifiable {
    public var id: String
    public var files: [DuplicateFile]
    public var preferredPath: String? = nil
    public var displayName: String? = nil
    public var locations: [String]? = nil
    public var fileBytes: Int64 { files.first?.bytes ?? 0 }
    public var repeatedBytes: Int64 { fileBytes * Int64(max(0, files.count - 1)) }
}

public struct DuplicateReport: Codable, Sendable {
    public var version = 1
    public var roots: [String]
    public var snapshotCreated: Date
    public var checkedAt: Date
    public var options: DuplicateOptions
    public var groups: [DuplicateGroup]
    public var skipped: Int
    public var hardLinks: Int
    public var issues: [ScanIssue]
    public var readBytes: Int64
    public var elapsed: Double
    public var cancelled: Bool
    public var inputPartial: Bool? = nil
    public var repeatedBytes: Int64 { groups.reduce(0) { $0 + $1.repeatedBytes } }
}

public struct DuplicatePlan: Sendable {
    public var roots: [String]
    public var snapshotCreated: Date
    public var options: DuplicateOptions
    public var buckets: [[DuplicateFile]]
    public var inputPartial: Bool
    public var skipped: Int
    public var hardLinks: Int
    public var issues: [ScanIssue]
    public var candidateCount: Int
    public var contentBytes: Int64
    public var estimatedReadBytes: Int64
}

public enum DuplicatePhase: String, Sendable { case preparing, sampling, hashing, verifying, finished }
public struct DuplicateProgress: Sendable {
    public var phase: DuplicatePhase = .preparing
    public var examined = 0
    public var phaseBytes: Int64 = 0
    public var phaseTotal: Int64 = 0
    public var readBytes: Int64 = 0
    public var activeSeconds: Double = 0
    public var groups = 0
    public var metadataBytes: Int64 = 0
    public var futureReadBytes: Int64 = 0
    public init() {}
}

/// A bounded read loop waits here, never on the main actor. No source writes.
public final class DuplicateControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var userPaused = false
    private var foregroundPaused = false
    private var pausedSince: Date?
    private var pausedSeconds: Double = 0
    public init() {}
    public func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }
    public func pause(_ value: Bool, foreground: Bool = false) {
        condition.lock()
        let wasPaused = userPaused || foregroundPaused
        if foreground { foregroundPaused = value } else { userPaused = value }
        let isPaused = userPaused || foregroundPaused
        if !wasPaused && isPaused { pausedSince = Date() }
        if wasPaused && !isPaused, let start = pausedSince {
            pausedSeconds += Date().timeIntervalSince(start)
            pausedSince = nil
        }
        condition.broadcast()
        condition.unlock()
    }
    public func checkpoint() throws {
        condition.lock()
        defer { condition.unlock() }
        while !cancelled && (userPaused || foregroundPaused) { condition.wait() }
        if cancelled || Task<Never, Never>.isCancelled { throw CancellationError() }
    }
    func elapsed(since start: Date) -> Double {
        condition.lock()
        defer { condition.unlock() }
        return max(
            0, Date().timeIntervalSince(start) - pausedSeconds - (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
        )
    }
}

public struct DuplicateFinder: Sendable {
    public init() {}
    static func sampleReadBytes(_ bytes: Int64) -> Int64 { bytes <= 1_048_576 ? bytes : 131072 }
    /// Only current metadata is read. Age selects groups with at least one eligible copy;
    /// same-size peers of other ages remain eligible for comparison.
    public func prepare(
        _ snapshot: Snapshot, options: DuplicateOptions, control: DuplicateControl = DuplicateControl(),
        progress: @escaping @Sendable (DuplicateProgress) -> Void = { _ in }
    ) throws -> DuplicatePlan {
        guard options.minimumBytes >= 0, options.maximumBytes.map({ $0 >= options.minimumBytes }) ?? true,
            !(options.modifiedAfter != nil && options.modifiedBefore != nil
                && options.modifiedAfter! > options.modifiedBefore!)
        else { throw AtlasError.message("Некорректный диапазон поиска.") }
        var sizes: [Int64: [DuplicateFile]] = [:]
        var identities = Set<String>()
        var skipped = 0
        var hardLinks = 0
        var issues: [ScanIssue] = []
        var last = Date()
        var examined = 0
        for entry in snapshot.entries where !entry.isDirectory && entry.kind != .link {
            try control.checkpoint()
            examined += 1
            if Date().timeIntervalSince(last) >= 0.15 {
                var value = DuplicateProgress()
                value.examined = examined
                progress(value)
                last = Date()
            }
            if !options.kinds.isEmpty && !options.kinds.contains(entry.kind) { continue }
            var info = stat()
            let inScope = snapshot.scanRoots.contains { $0 == "/" || entry.path.hasPrefix($0 + "/") }
            guard inScope, entry.path.withCString({ lstat($0, &info) }) == 0, info.st_mode & S_IFMT == S_IFREG,
                info.st_flags & UInt32(SF_DATALESS) == 0
            else {
                skipped += 1
                if issues.count < 20 {
                    issues.append(ScanIssue(path: entry.path, message: "Недоступен, ссылка или файл только в облаке"))
                }
                continue
            }
            if info.st_size < options.minimumBytes || options.maximumBytes.map({ info.st_size > $0 }) == true {
                continue
            }
            guard identities.insert("\(info.st_dev):\(info.st_ino)").inserted else {
                hardLinks += 1
                continue
            }
            sizes[info.st_size, default: []].append(DuplicateFile(path: entry.path, info: info))
            if Date().timeIntervalSince(last) >= 0.15 {
                var value = DuplicateProgress()
                value.examined = examined
                progress(value)
                last = Date()
            }
        }
        let buckets = sizes.values.filter { $0.count > 1 && $0.contains { options.matchesDate($0.modified) } }.map {
            $0.sorted { $0.path < $1.path }
        }.sorted { $0[0].bytes > $1[0].bytes }
        let count = buckets.reduce(0) { $0 + $1.count }
        let bytes = buckets.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + $1.bytes } }
        let sampleBytes = buckets.reduce(Int64(0)) { $0 + $1.reduce(0) { $0 + Self.sampleReadBytes($1.bytes) } }
        return DuplicatePlan(
            roots: snapshot.scanRoots, snapshotCreated: snapshot.created, options: options, buckets: buckets,
            inputPartial: snapshot.cancelled, skipped: skipped, hardLinks: hardLinks, issues: issues,
            candidateCount: count, contentBytes: bytes, estimatedReadBytes: bytes * 3 + sampleBytes)
    }

    public func run(
        _ plan: DuplicatePlan, control: DuplicateControl = DuplicateControl(),
        progress: @escaping @Sendable (DuplicateProgress) -> Void = { _ in },
        found: @escaping @Sendable ([DuplicateGroup]) -> Void = { _ in }
    ) throws -> DuplicateReport {
        try DuplicateRun(plan: plan, finder: self, control: control, progress: progress, found: found).run()
    }

    /// Open each path component without following symlinks. O_NONBLOCK avoids FIFO hangs.
    private func openFile(_ file: DuplicateFile) throws -> Int32 {
        var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw posix() }
        defer { close(directory) }
        let components = file.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains("..") else {
            throw AtlasError.message("Некорректный путь файла.")
        }
        for component in components.dropLast() {
            let next = component.withCString { openat(directory, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw posix() }
            close(directory)
            directory = next
        }
        let fd = components.last!.withCString { openat(directory, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw posix() }
        var info = stat()
        guard fstat(fd, &info) == 0, file.matches(info) else {
            close(fd)
            throw AtlasError.message("Файл изменился или недоступен.")
        }
        _ = fcntl(fd, F_NOCACHE, 1)
        return fd
    }
    public func validate(_ file: DuplicateFile) throws {
        let fd = try openFile(file)
        close(fd)
    }
    func sample(_ file: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void) throws -> String {
        let fd = try openFile(file)
        defer { close(fd) }
        let hasher = try ContentFingerprint()
        var buffer = [UInt8](repeating: 0, count: 65536)
        for offset in [Int64(0), file.bytes - 65536] {
            var filled = 0
            while filled < buffer.count {
                try control.checkpoint()
                let remaining = 65536 - filled
                let count = buffer.withUnsafeMutableBytes {
                    pread(fd, $0.baseAddress!.advanced(by: filled), remaining, offset + Int64(filled))
                }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AtlasError.message("Не удалось прочитать файл полностью.") }
                filled += count
                advanced(count)
            }
            buffer.withUnsafeBytes { hasher.update($0) }
        }
        var info = stat()
        guard fstat(fd, &info) == 0, file.matches(info) else {
            throw AtlasError.message("Файл изменился во время проверки.")
        }
        try validate(file)
        return hasher.finalize()
    }

    func digest(_ file: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void) throws -> String {
        let fd = try openFile(file)
        defer { close(fd) }
        let hasher = try ContentFingerprint()
        var buffer = [UInt8](repeating: 0, count: max(1, min(1024 * 1024, Int(file.bytes))))
        var remaining = file.bytes
        while remaining > 0 {
            try control.checkpoint()
            let count = Darwin.read(fd, &buffer, min(buffer.count, Int(remaining)))
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw AtlasError.message("Не удалось прочитать файл полностью.") }
            buffer.withUnsafeBytes { hasher.update(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            remaining -= Int64(count)
            advanced(count)
        }
        var info = stat()
        guard fstat(fd, &info) == 0, file.matches(info) else {
            throw AtlasError.message("Файл изменился во время проверки.")
        }
        try validate(file)
        return hasher.finalize()
    }
    func equal(_ a: DuplicateFile, _ b: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void) throws
        -> Bool
    {
        let left = try openFile(a)
        defer { close(left) }
        let right = try openFile(b)
        defer { close(right) }
        var x = [UInt8](repeating: 0, count: max(1, min(1024 * 1024, Int(a.bytes))))
        var y = x
        var remaining = a.bytes
        while remaining > 0 {
            try control.checkpoint()
            let length = min(x.count, Int(remaining))
            func fill(_ fd: Int32, _ buffer: inout [UInt8]) throws {
                var offset = 0
                while offset < length {
                    try control.checkpoint()
                    let n = buffer.withUnsafeMutableBytes {
                        Darwin.read(fd, $0.baseAddress!.advanced(by: offset), length - offset)
                    }
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw AtlasError.message("Не удалось прочитать файл полностью.") }
                    offset += n
                    advanced(n)
                }
            }
            try fill(left, &x)
            try fill(right, &y)
            guard x[..<length].elementsEqual(y[..<length]) else { return false }
            remaining -= Int64(length)
        }
        var ia = stat()
        var ib = stat()
        guard fstat(left, &ia) == 0, fstat(right, &ib) == 0, a.matches(ia), b.matches(ib) else {
            throw AtlasError.message("Файл изменился во время проверки.")
        }
        return true
    }
    /// Reconfirm a reviewed pair in bounded chunks before a GUI Trash operation.
    public func confirm(
        _ file: DuplicateFile, matches keeper: DuplicateFile, control: DuplicateControl,
        advanced: (Int) -> Void = { _ in }
    ) throws -> Bool {
        guard file.bytes == keeper.bytes else { return false }
        try control.checkpoint()
        return try equal(file, keeper, control: control, advanced: advanced)
    }
    private func posix() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

public final class DuplicateLookup: Sendable {
    public let id = UUID()
    public let byPath: [String: String]
    public let groups: [String: DuplicateGroup]
    public let checkedAt: Date
    public let folderCounts: [String: Int]
    public let results: DuplicateResultIndex
    public init(_ report: DuplicateReport) throws {
        var parents: [String: Int] = [:]
        var paths: [String: String] = [:]
        var groups: [String: DuplicateGroup] = [:]
        for group in report.groups {
            try Task.checkCancellation()
            groups[group.id] = group
            for file in group.files {
                try Task.checkCancellation()
                paths[file.path] = group.id
                let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
                parents[folder, default: 0] += 1
            }
        }
        folderCounts = try Self.ancestorCounts(parents)
        results = DuplicateResultIndex(report.groups)
        byPath = paths
        self.groups = groups
        checkedAt = report.checkedAt
    }
    private static func ancestorCounts(_ parents: [String: Int]) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for (parent, count) in parents {
            try Task.checkCancellation()
            var folder = URL(fileURLWithPath: parent)
            while true {
                counts[folder.path, default: 0] += count
                if folder.path == "/" { break }
                folder.deleteLastPathComponent()
            }
        }
        return counts
    }
    public func count(in path: String, directory: Bool) -> Int {
        directory ? folderCounts[path] ?? 0 : byPath[path] == nil ? 0 : 1
    }
    public func groups(in path: String) -> [DuplicateGroup] {
        let prefix = path == "/" ? "/" : path + "/"
        return groups.values.filter { group in
            !Task.isCancelled && group.files.contains { $0.path == path || $0.path.hasPrefix(prefix) }
        }
    }
}
