import CryptoKit
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
    fileprivate func elapsed(since start: Date) -> Double {
        condition.lock()
        defer { condition.unlock() }
        return max(
            0, Date().timeIntervalSince(start) - pausedSeconds - (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
        )
    }
}

public struct DuplicateFinder: Sendable {
    public init() {}
    private static func sampleReadBytes(_ bytes: Int64) -> Int64 { bytes <= 1_048_576 ? bytes : 131072 }
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
        let start = Date()
        var value = DuplicateProgress()
        value.phase = .sampling
        value.phaseTotal = plan.buckets.reduce(0) { $0 + $1.reduce(0) { $0 + Self.sampleReadBytes($1.bytes) } }
        value.futureReadBytes = plan.estimatedReadBytes
        var last = Date.distantPast
        var skipped = plan.skipped
        var issues = plan.issues
        var groups: [DuplicateGroup] = []
        var pending: [DuplicateGroup] = []
        func emit(force: Bool = false) {
            if force || Date().timeIntervalSince(last) >= 0.15 {
                if !pending.isEmpty {
                    found(pending)
                    pending.removeAll(keepingCapacity: true)
                }
                value.activeSeconds = control.elapsed(since: start)
                value.groups = groups.count
                progress(value)
                last = Date()
            }
        }
        func advanced(_ count: Int) {
            value.phaseBytes += Int64(count)
            value.readBytes += Int64(count)
            emit()
        }
        func failed(_ file: DuplicateFile, _ error: Error) {
            skipped += 1
            if issues.count < 20 { issues.append(ScanIssue(path: file.path, message: error.localizedDescription)) }
        }
        var hashed: [String: [DuplicateFile]] = [:]
        var stopped = false
        do {
            emit(force: true)
            // Same-size buckets are sampled first. Unique beginnings/endings never
            // incur a full-file hash. For <=1 MiB one complete read avoids an extra pass.
            var sampled: [String: [(DuplicateFile, String?)]] = [:]
            for bucket in plan.buckets {
                for file in bucket {
                    try control.checkpoint()
                    do {
                        let complete = file.bytes <= 1_048_576
                        let sample =
                            complete
                            ? try digest(file, control: control, advanced: advanced)
                            : try sample(file, control: control, advanced: advanced)
                        sampled[String(file.bytes) + ":" + sample, default: []].append((file, complete ? sample : nil))
                    } catch is CancellationError { throw CancellationError() } catch { failed(file, error) }
                    value.examined += 1
                    emit()
                }
            }
            let survivors = sampled.values.filter {
                $0.count > 1 && $0.contains { plan.options.matchesDate($0.0.modified) }
            }.sorted { $0[0].0.bytes > $1[0].0.bytes }
            value.phase = .hashing
            value.phaseBytes = 0
            value.phaseTotal = survivors.reduce(0) { $0 + $1.reduce(0) { $0 + ($1.1 == nil ? $1.0.bytes : 0) } }
            value.futureReadBytes = survivors.reduce(0) { $0 + Int64($1.count - 1) * $1[0].0.bytes * 2 }
            emit(force: true)
            for bucket in survivors {
                for (file, cached) in bucket {
                    try control.checkpoint()
                    do {
                        let hash = try cached ?? digest(file, control: control, advanced: advanced)
                        hashed[String(file.bytes) + ":" + hash, default: []].append(file)
                    } catch is CancellationError { throw CancellationError() } catch { failed(file, error) }
                }
            }
            let matches = hashed.filter {
                $0.value.count > 1 && $0.value.contains { plan.options.matchesDate($0.modified) }
            }.sorted { $0.value[0].bytes > $1.value[0].bytes }
            value.phase = .verifying
            value.phaseBytes = 0
            value.futureReadBytes = 0
            value.phaseTotal = matches.reduce(0) { $0 + Int64($1.value.count - 1) * $1.value[0].bytes * 2 }
            emit(force: true)
            for (digest, files) in matches {
                try control.checkpoint()
                var confirmed: [DuplicateFile] = []
                for file in files {
                    do {
                        if confirmed.isEmpty {
                            try validate(file)
                            confirmed.append(file)
                        } else if try equal(confirmed[0], file, control: control, advanced: advanced) {
                            confirmed.append(file)
                        }
                    } catch is CancellationError { throw CancellationError() } catch { failed(file, error) }
                }
                // Revalidate every path after all reads; changed/unlinked files cannot be published.
                confirmed = confirmed.filter { file in
                    do {
                        try validate(file)
                        return true
                    } catch {
                        failed(file, error)
                        return false
                    }
                }
                if confirmed.count > 1 && confirmed.contains(where: { plan.options.matchesDate($0.modified) }) {
                    var group = DuplicateGroup(id: digest, files: confirmed)
                    let sample = Array(confirmed.prefix(200))
                    group.displayName = sample.map { URL(fileURLWithPath: $0.path).lastPathComponent }.min {
                        $0.count < $1.count
                    }
                    group.locations = Array(
                        Set(sample.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().lastPathComponent })
                    ).sorted().prefix(3).map { $0 }
                    value.metadataBytes += group.files.reduce(160) { $0 + Int64($1.path.utf8.count + 240) }
                    groups.append(group)
                    pending.append(group)
                    emit()
                }
            }
        } catch is CancellationError { stopped = true }
        value.phase = .finished
        emit(force: true)
        return DuplicateReport(
            roots: plan.roots, snapshotCreated: plan.snapshotCreated, checkedAt: Date(), options: plan.options,
            groups: groups.sorted { $0.repeatedBytes > $1.repeatedBytes }, skipped: skipped, hardLinks: plan.hardLinks,
            issues: issues, readBytes: value.readBytes, elapsed: control.elapsed(since: start), cancelled: stopped,
            inputPartial: plan.inputPartial)
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
    private func validate(_ file: DuplicateFile) throws {
        let fd = try openFile(file)
        close(fd)
    }
    private func sample(_ file: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void) throws -> String {
        let fd = try openFile(file)
        defer { close(fd) }
        var hasher = SHA256()
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
            buffer.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        var info = stat()
        guard fstat(fd, &info) == 0, file.matches(info) else {
            throw AtlasError.message("Файл изменился во время проверки.")
        }
        try validate(file)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func digest(_ file: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void) throws -> String {
        let fd = try openFile(file)
        defer { close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: max(1, min(1024 * 1024, Int(file.bytes))))
        var remaining = file.bytes
        while remaining > 0 {
            try control.checkpoint()
            let count = Darwin.read(fd, &buffer, min(buffer.count, Int(remaining)))
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw AtlasError.message("Не удалось прочитать файл полностью.") }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            remaining -= Int64(count)
            advanced(count)
        }
        var info = stat()
        guard fstat(fd, &info) == 0, file.matches(info) else {
            throw AtlasError.message("Файл изменился во время проверки.")
        }
        try validate(file)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func equal(_ a: DuplicateFile, _ b: DuplicateFile, control: DuplicateControl, advanced: (Int) -> Void)
        throws -> Bool
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
    private func posix() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

public final class DuplicateLookup: Sendable {
    public let id = UUID()
    public let byPath: [String: String]
    public let groups: [String: DuplicateGroup]
    public let checkedAt: Date
    public init(_ report: DuplicateReport) {
        var paths: [String: String] = [:]
        var groups: [String: DuplicateGroup] = [:]
        for group in report.groups {
            groups[group.id] = group
            for file in group.files { paths[file.path] = group.id }
        }
        byPath = paths
        self.groups = groups
        checkedAt = report.checkedAt
    }
}
