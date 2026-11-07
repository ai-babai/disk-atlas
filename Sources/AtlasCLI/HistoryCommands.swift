import ArgumentParser
import AtlasCore
import Foundation

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history", abstract: "Reuse the app's local scans without rescanning source folders.",
        subcommands: [HistoryList.self, HistoryInspect.self, HistoryDuplicates.self, HistoryExport.self],
        defaultSubcommand: HistoryList.self)
}

struct HistoryList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List recent scans, newest first, with their metadata storage sizes.")
    @OptionGroup var page: PageOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let page = page
        let result = try await CLIWork.perform(work) { context in
            context.update("loading_history")
            let records = try await ScanHistory().list()
            try context.check()
            let rows = try page.slice(records).map { record -> [String: Any] in
                var value = try object(record) as? [String: Any] ?? [:]
                value["storedBytes"] = record.storedBytes.map { $0 as Any } ?? NSNull()
                return value
            }
            return page.metadata(total: records.count, returned: rows.count).merging(["records": rows]) { _, new in new
            }
        }
        try format.emit(result, command: "history list")
    }
}

struct HistoryInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect", abstract: "Query a history UUID or latest, using the same options as inspect.")
    @Argument(help: "Full UUID from history list, or latest.") var id = "latest"
    @OptionGroup var query: QueryOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let id = id
        let query = query
        let result = try await CLIWork.perform(work) { context in
            context.update("loading_history")
            let history = ScanHistory()
            let record = try await historyRecord(id, history: history)
            let snapshot = try await history.load(record)
            return try query.result(snapshot, context: context).merging(["historyID": record.id.uuidString]) { _, new in
                new
            }
        }
        try format.emit(result, command: "history inspect")
    }
}

struct HistoryDuplicates: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicates", abstract: "Read a stored duplicate report; never start a new check.")
    @Argument(help: "Full UUID from history list, or latest.") var id = "latest"
    @Option(help: "Return files in this group ID.") var group: String?
    @OptionGroup var page: PageOptions
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let id = id
        let page = page
        let group = group
        let result = try await CLIWork.perform(work) { context in
            context.update("loading_report")
            let history = ScanHistory()
            let record = try await historyRecord(id, history: history)
            guard let (report, bytes) = try await history.loadDuplicates(id: record.id) else {
                throw CLIError.missing("This scan has no saved duplicate report.")
            }
            try context.check()
            return try reportResult(report, page: page, group: group).merging([
                "historyID": record.id.uuidString, "reportBytes": bytes,
            ]) { _, new in new }
        }
        try format.emit(result, command: "history duplicates")
    }
}

struct HistoryExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Export a stored scan to a new private .atlas file.")
    @Argument(help: "Full history UUID, or latest.") var id: String
    @Argument(help: "New .atlas file; existing files are rejected.") var output: String
    @OptionGroup var format: OutputOptions
    @OptionGroup var work: WorkOptions
    func run() async throws {
        let destination = try newOutput(output)!
        let id = id
        let result = try await CLIWork.perform(work) { context in
            context.update("exporting_history")
            let history = ScanHistory()
            let record = try await historyRecord(id, history: history)
            let snapshot = try await history.load(record)
            try context.check()
            try saveSnapshot(snapshot, to: destination)
            return [
                "historyID": record.id.uuidString, "snapshot": destination.path, "status": snapshotStatus(snapshot),
            ]
        }
        try format.emit(result, command: "history export")
    }
}

private func historyRecord(_ id: String, history: ScanHistory) async throws -> ScanHistoryRecord {
    guard id == "latest" || UUID(uuidString: id) != nil else {
        throw ValidationError("Expected a full history UUID or latest.")
    }
    let records = try await history.list()
    guard let record = id == "latest" ? records.first : records.first(where: { $0.id == UUID(uuidString: id) }) else {
        throw CLIError.missing("No saved scan matches \(id).")
    }
    return record
}
