import ArgumentParser
import AtlasCore
import Darwin
import Foundation

struct QueryOptions: ParsableArguments {
    @Option(help: "Exact directory path recorded in the snapshot (not a live filesystem lookup).") var path: String?
    @Flag(help: "Search all descendant files instead of immediate children.") var files = false
    @Option(help: "Case-insensitive name substring. Searches descendants.") var query = ""
    @Option(help: "Comma-separated kinds. Searches descendants.") var types: String?
    @Option(help: "Size metric: allocated or logical.") var metric = "allocated"
    @Option(help: "Order by size, name, created, modified or share.") var sort = "size"
    @Option(help: "Sort direction: asc or desc.") var order = "desc"
    @OptionGroup var page: PageOptions
    mutating func validate() throws {
        guard ["allocated", "logical"].contains(metric), ["asc", "desc"].contains(order),
            EntrySort(rawValue: sort) != nil
        else { throw ValidationError("Invalid --metric, --sort or --order. See inspect --help.") }
        _ = try kinds()
    }
    private func kinds() throws -> Set<FileKind> {
        try Set(
            (types ?? "").split(separator: ",").map { name in
                guard let kind = FileKind(rawValue: String(name)) else {
                    throw ValidationError("Unknown type: \(name)")
                }
                return kind
            })
    }
    func result(_ snapshot: Snapshot, context: CLIWork) throws -> [String: Any] {
        try context.check()
        let selected: Entry
        if let path {
            guard let entry = snapshot.entries.first(where: { $0.path == path }) else {
                throw CLIError.missing("Directory is not in this snapshot: \(path)")
            }
            guard entry.isDirectory else { throw ValidationError("--path must identify a directory in the snapshot.") }
            selected = entry
        } else {
            selected = snapshot.rootEntry
        }
        context.update("indexing")
        let index = PresentationIndex(snapshot)
        try context.check()
        context.update("querying")
        let rows = index.rows(
            folder: selected.id, logical: metric == "logical", query: query, kinds: try kinds(), filesOnly: files,
            limit: page.offset + page.limit, sort: EntrySort(rawValue: sort)!, descending: order == "desc")
        try context.check()
        let entries = page.slice(rows.entries).map(entryObject)
        return page.metadata(total: rows.count, returned: entries.count).merging([
            "root": snapshot.root, "roots": snapshot.scanRoots, "selected": entryObject(selected), "entries": entries,
            "metric": metric, "sort": sort, "order": order, "status": snapshotStatus(snapshot),
            "issueCount": snapshot.issueCount, "cancelled": snapshot.cancelled,
        ]) { _, new in new }
    }
}

func entryObject(_ entry: Entry) -> [String: Any] {
    [
        "id": entry.id, "name": entry.name, "path": entry.path, "kind": entry.kind.rawValue, "bytes": entry.bytes,
        "logicalBytes": entry.logicalBytes, "fileCount": entry.fileCount,
        "modified": ISO8601DateFormatter().string(from: entry.modified),
        "created": entry.created.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
        "sharedLink": entry.sharedLink,
    ]
}

func snapshotStatus(_ snapshot: Snapshot) -> String {
    snapshot.cancelled ? "cancelled" : snapshot.issueCount > 0 ? "partial" : "complete"
}

func summary(_ snapshot: Snapshot) -> [String: Any] {
    [
        "root": snapshot.root, "roots": snapshot.scanRoots, "bytes": snapshot.rootEntry.bytes,
        "logicalBytes": snapshot.rootEntry.logicalBytes, "fileCount": snapshot.rootEntry.fileCount,
        "entryCount": snapshot.entries.count, "elapsed": snapshot.elapsed, "cancelled": snapshot.cancelled,
        "status": snapshotStatus(snapshot), "issueCount": snapshot.issueCount,
        "issues": (try? object(snapshot.issues)) ?? [], "largest": snapshot.children(of: 0).prefix(20).map(entryObject),
    ]
}

// Retain the original MCP entry point with the same bounded fields as the CLI.
func inspect(_ path: String, folder: String?, limit: Int, files: Bool) throws -> [String: Any] {
    var query = QueryOptions()
    query.path = folder
    query.page.limit = limit
    query.files = files
    return try query.result(Snapshot.load(from: URL(fileURLWithPath: path)), context: CLIWork(WorkOptions()))
}

func newOutput(_ path: String?) throws -> URL? {
    guard let path else { return nil }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    // lstat also rejects dangling symlinks; creation still uses O_EXCL to handle races.
    var info = stat()
    if url.path.withCString({ lstat($0, &info) }) == 0 {
        throw CLIError(
            code: "output_exists", message: "Output already exists: \(url.path)", hint: "Choose a new output name.")
    }
    return url
}

func show(_ path: String, context: CLIWork? = nil) throws {
    _ = try Snapshot.load(from: URL(fileURLWithPath: path))
    try context?.check()
    let app = installedApp()
    guard FileManager.default.fileExists(atPath: app.path) else {
        throw CLIError.missing("Install Disk Atlas.app first.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", app.path, URL(fileURLWithPath: path).path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw CLIError(code: "open_failed", message: "Could not open the app.", hint: "Check doctor.")
    }
}
