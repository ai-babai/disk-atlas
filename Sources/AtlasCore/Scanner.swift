import Darwin
import Foundation

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

public struct DiskScanner: Sendable {
    public init() {}

    public func scan(
        path: String, cancellation: ScanCancellation = ScanCancellation(),
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> Snapshot { try scan(paths: [path], cancellation: cancellation, progress: progress) }

    public static func canonicalPath(_ path: String) throws -> String {
        let input = (path as NSString).expandingTildeInPath
        // Foundation can shorten /private/var to /var while its enumerator returns
        // /private/var children. POSIX realpath keeps parent keys consistent.
        guard let resolved = realpath(input, nil) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let result = String(cString: resolved)
        free(resolved)
        return result
    }

    public static func normalizedRoots(_ paths: [String]) throws -> [String] {
        func identity(_ path: String) throws -> (device: dev_t, inode: ino_t) {
            var info = stat()
            guard path.withCString({ lstat($0, &info) }) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return (info.st_dev, info.st_ino)
        }
        // APFS firmlinks expose the same directories under /Users and
        // /System/Volumes/Data/Users. realpath alone does not merge those aliases.
        let canonical = try Set(paths.map(canonicalPath))
        var candidates: [(path: String, comparison: String, device: dev_t, inode: ino_t)] = []
        for path in canonical {
            let key = try identity(path)
            var comparison = path
            let dataAlias = "/System/Volumes/Data" + path
            if !path.hasPrefix("/System/Volumes/Data"), let alias = try? identity(dataAlias),
                key.device == alias.device, key.inode == alias.inode
            {
                comparison = dataAlias
            }
            candidates.append((path, comparison, key.device, key.inode))
        }
        candidates.sort {
            $0.comparison == $1.comparison ? $0.path.count < $1.path.count : $0.comparison < $1.comparison
        }
        var accepted: [(path: String, comparison: String, device: dev_t, inode: ino_t)] = []
        for candidate in candidates {
            let covered = accepted.contains { parent in
                parent.device == candidate.device
                    && (parent.inode == candidate.inode
                        || (parent.comparison == "/" || candidate.comparison.hasPrefix(parent.comparison + "/")))
            }
            if !covered { accepted.append(candidate) }
        }
        return accepted.map(\.path)
    }

    public func scan(
        paths: [String], cancellation: ScanCancellation = ScanCancellation(),
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> Snapshot {
        try MetadataIO.withoutCloudDownloads {
            try scanMetadata(paths: paths, cancellation: cancellation, progress: progress)
        }
    }

    private func scanMetadata(
        paths: [String], cancellation: ScanCancellation, progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> Snapshot {
        let roots = try Self.normalizedRoots(paths)
        guard !roots.isEmpty else { throw AtlasError.message("Выбери хотя бы одну папку.") }
        var seenLinks = Set<String>()
        if roots.count == 1 {
            return try scanOne(path: roots[0], seenLinks: &seenLinks, cancellation: cancellation, progress: progress)
        }
        let start = Date()
        let virtual = Entry(
            id: 0, parent: nil, name: "Выбранные папки", path: "/", kind: .folder, bytes: 0, logicalBytes: 0,
            fileCount: 0, modified: start, sharedLink: false, children: [], cloudOnly: false)
        var combined = Snapshot(
            root: "/", roots: roots, created: start, elapsed: 0, volumeTotal: 0, volumeFree: 0, entries: [virtual],
            issues: [], issueCount: 0, cancelled: false)
        for path in roots {
            if cancellation.isCancelled { break }
            let baseCount = combined.entries.count
            let baseBytes = combined.rootEntry.bytes
            let baseMetadata = combined.entries.reduce(Int64(512)) { $0 + $1.estimatedMetadataBytes }
            do {
                let part = try scanOne(path: path, seenLinks: &seenLinks, cancellation: cancellation) { update in
                    progress(
                        ScanProgress(
                            entries: baseCount + update.entries, bytes: baseBytes + update.bytes,
                            currentPath: update.currentPath, metadataBytes: baseMetadata + update.metadataBytes))
                }
                combined.entries[0].children.append(baseCount)
                for var node in part.entries {
                    node.id += baseCount
                    node.parent = node.parent.map { $0 + baseCount } ?? 0
                    node.children = node.children.map { $0 + baseCount }
                    combined.entries.append(node)
                }
                combined.entries[0].bytes += part.rootEntry.bytes
                combined.entries[0].logicalBytes += part.rootEntry.logicalBytes
                combined.entries[0].fileCount += part.rootEntry.fileCount
                combined.issueCount += part.issueCount
                combined.issues.append(contentsOf: part.issues.prefix(max(0, 200 - combined.issues.count)))
            } catch {
                combined.issueCount += 1
                if combined.issues.count < 200 {
                    combined.issues.append(ScanIssue(path: path, message: error.localizedDescription))
                }
            }
        }
        combined.elapsed = Date().timeIntervalSince(start)
        combined.cancelled = cancellation.isCancelled
        return combined
    }

    private func scanOne(
        path: String, seenLinks: inout Set<String>, cancellation: ScanCancellation,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> Snapshot {
        let start = Date()
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let rootStat = try metadata(root)
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            throw AtlasError.message("Выбери папку для сканирования: \(root.path)")
        }
        let manager = FileManager.default
        // Check root access explicitly: a denied root must never look like an empty disk.
        guard manager.isReadableFile(atPath: root.path) else {
            throw AtlasError.message("Нет доступа к папке: \(root.path)")
        }
        var nodes: [Entry] = [entry(root, stat: rootStat, id: 0, parent: nil)]
        var directories = [root.path: 0]
        var seenDirectories: Set<String> = ["\(rootStat.st_dev):\(rootStat.st_ino)"]
        var issues: [ScanIssue] = []
        var issueCount = 0
        var scannedBytes: Int64 = 0
        var metadataBytes = Int64(512) + nodes[0].estimatedMetadataBytes
        var lastProgress = start
        func issue(_ path: String, _ message: String) {
            issueCount += 1
            if issues.count < 200 { issues.append(ScanIssue(path: path, message: message)) }
        }
        guard
            let walker = manager.enumerator(
                at: root, includingPropertiesForKeys: [], options: [],
                errorHandler: { url, error in
                    issue(url.path, error.localizedDescription)
                    return true
                })
        else { throw AtlasError.message("Не удалось прочитать папку.") }

        while let url = walker.nextObject() as? URL {
            if cancellation.isCancelled { break }
            autoreleasepool {
                do {
                    let info = try metadata(url)
                    guard info.st_dev == rootStat.st_dev else {
                        walker.skipDescendants()
                        issue(url.path, "Другой том: сканируется отдельно.")
                        return
                    }
                    guard let parent = directories[url.deletingLastPathComponent().path] else {
                        walker.skipDescendants()
                        issue(url.path, "Родительская папка недоступна.")
                        return
                    }
                    let id = nodes.count
                    var node = entry(url, stat: info, id: id, parent: parent)
                    if node.isDirectory {
                        let key = "\(info.st_dev):\(info.st_ino)"
                        guard seenDirectories.insert(key).inserted else {
                            walker.skipDescendants()
                            return
                        }
                        directories[url.path] = id
                    } else if (info.st_mode & S_IFMT) == S_IFREG && info.st_nlink > 1 {
                        let key = "\(info.st_dev):\(info.st_ino)"
                        if !seenLinks.insert(key).inserted {
                            node.sharedLink = true
                            node.bytes = 0
                            node.logicalBytes = 0
                        }
                    }
                    nodes.append(node)
                    nodes[parent].children.append(id)
                    scannedBytes += node.bytes
                    metadataBytes += node.estimatedMetadataBytes
                } catch {
                    walker.skipDescendants()
                    issue(url.path, error.localizedDescription)
                }
            }
            if Date().timeIntervalSince(lastProgress) > 0.15 {
                progress(
                    ScanProgress(
                        entries: nodes.count, bytes: scannedBytes, currentPath: url.path, metadataBytes: metadataBytes))
                lastProgress = Date()
            }
        }
        // Aggregate once, bottom-up. Directory metadata is intentionally excluded.
        if nodes.count > 1 {
            for id in stride(from: nodes.count - 1, through: 1, by: -1) {
                if let parent = nodes[id].parent {
                    nodes[parent].bytes += nodes[id].bytes
                    nodes[parent].logicalBytes += nodes[id].logicalBytes
                    nodes[parent].fileCount += nodes[id].fileCount
                }
            }
        }
        let volume = try? manager.attributesOfFileSystem(forPath: root.path)
        progress(
            ScanProgress(
                entries: nodes.count, bytes: scannedBytes, currentPath: root.path, metadataBytes: metadataBytes))
        return Snapshot(
            root: root.path, created: start, elapsed: Date().timeIntervalSince(start),
            volumeTotal: (volume?[.systemSize] as? NSNumber)?.int64Value ?? 0,
            volumeFree: (volume?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0, entries: nodes, issues: issues,
            issueCount: issueCount, cancelled: cancellation.isCancelled)
    }

    private func metadata(_ url: URL) throws -> stat {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return lstat(pointer, &info)
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return info
    }

    private func entry(_ url: URL, stat info: stat, id: Int, parent: Int?) -> Entry {
        let mode = info.st_mode & S_IFMT
        let directory = mode == S_IFDIR
        let kind: FileKind = directory ? .folder : mode == S_IFLNK ? .link : FileKind.classify(url)
        return Entry(
            id: id, parent: parent, name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, path: url.path,
            kind: kind, bytes: directory ? 0 : max(0, Int64(info.st_blocks) * 512),
            logicalBytes: directory ? 0 : max(0, Int64(info.st_size)), fileCount: directory ? 0 : 1,
            modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)),
            created: info.st_birthtimespec.tv_sec > 0
                ? Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec)) : nil, sharedLink: false,
            children: [], cloudOnly: info.st_flags & UInt32(SF_DATALESS) != 0)
    }
}
