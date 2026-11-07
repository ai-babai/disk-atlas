import ArgumentParser
import AtlasCore
import Darwin
import Foundation

func json(_ value: Any, pretty: Bool = true) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: value, options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: Snapshot.encoder.encode(value))
}

struct CLIError: LocalizedError {
    var code: String
    var message: String
    var hint: String
    var status: Int32 = 1
    var errorDescription: String? { message }
    static func missing(_ message: String) -> Self {
        Self(code: "not_found", message: message, hint: "Check the path or use history list.", status: 3)
    }
}

struct OutputOptions: ParsableArguments {
    @Flag(help: "Emit a versioned JSON object (default when stdout is not a terminal).") var json = false
    @Flag(help: "Emit readable text, including when piped.") var text = false
    mutating func validate() throws { if json && text { throw ValidationError("Choose either --json or --text.") } }
    func emit(_ result: [String: Any], command: String) throws {
        var value = result
        value["schemaVersion"] = 1
        value["command"] = command
        if value["status"] == nil { value["status"] = "complete" }
        let encoded = try json || (!text && isatty(STDOUT_FILENO) == 0) ? cliJSON(value) : CLIOutput.readable(value)
        do { try FileHandle.standardOutput.write(contentsOf: Data((encoded + "\n").utf8)) } catch {
            if !CLIOutput.isBrokenPipe(error) { throw error }
        }
        switch value["status"] as? String {
        case "cancelled": throw ExitCode(130)
        case "partial": throw ExitCode(4)
        default: break
        }
    }
}

// Avoid shadowing OutputOptions.json, the command-line switch.
private func cliJSON(_ value: [String: Any]) throws -> String { try json(value) }

enum CLIOutput {
    static func isBrokenPipe(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSPOSIXErrorDomain && value.code == Int(EPIPE) { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return isBrokenPipe(underlying) }
        return false
    }
    static func exitStatus(_ error: Error, parserCode: Int32) -> Int32 {
        if let failure = error as? CLIError { return failure.status }
        if error is CancellationError { return 130 }
        if error is ExitCode { return parserCode }
        if error is ValidationError || parserCode == ExitCode.validationFailure.rawValue { return 2 }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return 3 }
        return parserCode
    }
    static func failure(_ error: Error, parserCode: Int32) {
        if error is ExitCode { return }
        let failure = error as? CLIError
        let status = exitStatus(error, parserCode: parserCode)
        let code = failure?.code ?? (status == 2 ? "usage" : status == 3 ? "not_found" : "operation_failed")
        let message = status == 2 ? AtlasCommand.message(for: error) : error.localizedDescription
        let hint = failure?.hint ?? "Use disk-atlas help <command> for usage."
        let value: [String: Any] = ["schemaVersion": 1, "error": ["code": code, "message": message, "hint": hint]]
        let arguments = CommandLine.arguments
        let machine = arguments.contains("--json") || (isatty(STDOUT_FILENO) == 0 && !arguments.contains("--text"))
        let output =
            machine
            ? (try? json(value, pretty: false)) ?? code : "Error: \(terminalSafe(message))\n\(terminalSafe(hint))"
        try? FileHandle.standardError.write(contentsOf: Data((output + "\n").utf8))
    }
    static func readable(_ value: [String: Any]) -> String {
        var lines = ["Disk Atlas · \(value["command"] ?? "") · \(value["status"] ?? "complete")"]
        for key in [
            "roots", "path", "bytes", "logicalBytes", "fileCount", "candidateCount", "groupCount",
            "estimatedReadBytesUpperBound", "estimateSeconds", "repeatedLogicalBytes", "snapshot", "report",
            "totalResults", "nextOffset", "issueCount",
        ] { if let item = value[key] { lines.append("\(key): \(item)") } }
        for key in ["largest", "entries", "records", "groups", "files"] {
            guard let rows = value[key] as? [[String: Any]] else { continue }
            lines.append(contentsOf: rows.map(row))
        }
        if lines.count == 1, let detail = try? json(value) { lines.append(detail) }
        return lines.map(terminalSafe).joined(separator: "\n")
    }
    private static func row(_ item: [String: Any]) -> String {
        if let id = item["id"] as? String, let roots = item["roots"] as? [String] {
            let stored = (item["storedBytes"] as? Int64).map(byteString) ?? "unavailable"
            return "\(id)  \(item["created"] ?? "")  snapshot \(stored)  \(roots.joined(separator: " · "))"
        }
        let size = (item["bytes"] ?? item["repeatedLogicalBytes"]) as? Int64 ?? 0
        let name = item["path"] ?? item["name"] ?? item["id"] ?? ""
        return "\(byteString(size))  \(name)"
    }
}
