import ArgumentParser
import AtlasCore
import Foundation

struct AtlasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disk-atlas", abstract: "Explore disk metadata and verified duplicates. No source-file writes.",
        discussion: """
            Start: disk-atlas history list --json
            New scan: disk-atlas scan ~/Downloads --output scan.atlas
            Explore: disk-atlas inspect scan.atlas --files --limit 20
            Agent reference: disk-atlas schema inspect
            Content reads require duplicates --read-contents. Commands never prompt.
            """, version: cliVersion,
        subcommands: [
            ScanCommand.self, InspectCommand.self, HistoryCommand.self, DuplicatesCommand.self, ReportCommand.self,
            ShowCommand.self, DoctorCommand.self, InstallCommand.self, SchemaCommand.self, MCPCommand.self,
        ])
}

struct PageOptions: ParsableArguments {
    @Option(help: "Maximum returned records, 1...500.") var limit = 20
    @Option(help: "Skip this many ordered matches, 0...10000. Narrow the query for deeper results.") var offset = 0
    mutating func validate() throws {
        guard (1...500).contains(limit), (0...10000).contains(offset) else {
            throw ValidationError("--limit must be 1...500; --offset must be 0...10000.")
        }
    }
    func slice<T>(_ items: [T]) -> ArraySlice<T> { items.dropFirst(offset).prefix(limit) }
    func metadata(total: Int, returned: Int) -> [String: Any] {
        let next = offset + returned
        return [
            "totalResults": total, "returned": returned, "offset": offset, "limit": limit,
            "nextOffset": next < total && next <= 10000 ? next as Any : NSNull(), "truncated": next < total,
        ]
    }
}

struct WorkOptions: ParsableArguments {
    @Flag(help: "Emit throttled NDJSON progress on stderr. Terminal progress is enabled automatically.") var progress =
        false
    @Flag(help: "Suppress progress, including in a terminal.") var quiet = false
    mutating func validate() throws {
        if progress && quiet { throw ValidationError("Choose either --progress or --quiet.") }
    }
}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan", abstract: "Scan directory metadata; optionally save a new .atlas file.")
    @Argument(help: "Directories. Overlapping roots and hard links are counted once.") var paths: [String]
    @Option(help: "Create a private snapshot; existing files are never overwritten.") var output: String?
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let destination = try newOutput(output)
        let paths = paths
        let result = try await CLIWork.perform(work) { context in
            let snapshot = try context.scan(paths)
            var value = summary(snapshot)
            if let destination {
                try saveSnapshot(snapshot, to: destination)
                value["snapshot"] = destination.path
            }
            return value
        }
        try format.emit(result, command: "scan")
    }
}

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect", abstract: "Query a saved snapshot without rescanning or reading source contents.")
    @Argument(help: "Exported .atlas snapshot.") var snapshot: String
    @OptionGroup var query: QueryOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let snapshot = snapshot
        let query = query
        let result = try await CLIWork.perform(work) { context in
            context.update("loading")
            let loaded = try Snapshot.load(from: URL(fileURLWithPath: snapshot))
            return try query.result(loaded, context: context)
        }
        try format.emit(result, command: "inspect")
    }
}

struct DuplicatesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicates", abstract: "Estimate by metadata; explicitly opt in to expensive content comparison.",
        discussion: "Without --read-contents this only estimates work. Estimates are rough, not a time guarantee.")
    @Argument(help: "Directories to examine.") var paths: [String]
    @Flag(help: "Authorize content reads: size buckets → edge samples → XXH3-128 → byte comparison.") var readContents =
        false
    @Option(help: "Minimum logical bytes, inclusive.") var minBytes: Int64 = 0
    @Option(help: "Maximum logical bytes, inclusive.") var maxBytes: Int64?
    @Option(help: "Comma-separated file types; see schema.") var types: String?
    @Option(help: "ISO 8601 date; retain groups with at least one newer copy.") var modifiedAfter: String?
    @Option(help: "ISO 8601 date; retain groups with at least one older copy.") var modifiedBefore: String?
    @Option(help: "Save full private JSON report to a new file. Requires --read-contents.") var output: String?
    @OptionGroup var page: PageOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func validate() throws {
        guard minBytes >= 0, maxBytes.map({ $0 >= minBytes }) ?? true else {
            throw ValidationError("Expected 0 <= --min-bytes <= --max-bytes.")
        }
        if !readContents && output != nil { throw ValidationError("--output requires --read-contents.") }
        _ = try options()
    }
    private func options() throws -> DuplicateOptions {
        var args: [String: Any] = ["minimumBytes": minBytes]
        if let maxBytes { args["maximumBytes"] = maxBytes }
        if let types { args["kinds"] = types.split(separator: ",").map(String.init) }
        if let modifiedAfter { args["modifiedAfter"] = modifiedAfter }
        if let modifiedBefore { args["modifiedBefore"] = modifiedBefore }
        do { return try duplicateOptions(args) } catch { throw ValidationError(error.localizedDescription) }
    }
    func run() async throws {
        let destination = try newOutput(output)
        let options = try options()
        let paths = paths
        let read = readContents
        let page = page
        let result = try await CLIWork.perform(work) { context in
            let snapshot = try context.scan(paths)
            try context.check()
            context.update("preparing")
            let plan = try DuplicateFinder().prepare(snapshot, options: options, control: context.duplicates) {
                context.duplicateProgress($0)
            }
            if !read {
                return duplicatePlanSummary(plan).merging(["status": snapshotStatus(snapshot)]) { _, new in new }
            }
            let report = try DuplicateFinder().run(plan, control: context.duplicates) { context.duplicateProgress($0) }
            var value = try reportResult(report, page: page, group: nil)
            if let destination {
                try saveReport(report, to: destination)
                value["report"] = destination.path
            }
            return value
        }
        try format.emit(result, command: "duplicates")
    }
}

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report", abstract: "Read a saved duplicate report; page groups or the files in one group.")
    @Argument(help: "JSON report created by duplicates --output.") var report: String
    @Option(help: "Return the files in this group ID, without rereading contents.") var group: String?
    @OptionGroup var page: PageOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let report = report
        let group = group
        let page = page
        let result = try await CLIWork.perform(work) { context in
            context.update("loading")
            let loaded = try loadReport(URL(fileURLWithPath: report))
            try context.check()
            return try reportResult(loaded, page: page, group: group)
        }
        try format.emit(result, command: "report")
    }
}

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Open an exported snapshot in the installed macOS app.")
    @Argument var snapshot: String
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let snapshot = snapshot
        let result = try await CLIWork.perform(work) { context in
            context.update("opening_snapshot")
            try show(snapshot, context: context)
            return ["opened": true]
        }
        try format.emit(result, command: "show")
    }
}

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: "Serve the existing MCP stdio protocol (optional integration).")
    func run() { serveMCP() }
}
