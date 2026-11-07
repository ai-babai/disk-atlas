import AtlasCore
import Darwin
import Foundation

func loadReport(_ url: URL) throws -> DuplicateReport {
    let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard size.isRegularFile == true, (size.fileSize ?? Int.max) <= 256 * 1024 * 1024 else {
        throw CLIError(
            code: "invalid_report", message: "Expected a regular JSON report up to 256 MiB.",
            hint: "Use duplicates --output.")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let report = try decoder.decode(DuplicateReport.self, from: Data(contentsOf: url))
    guard report.version == 1 else {
        throw CLIError(code: "unsupported_version", message: "Unsupported report version.", hint: "Update Disk Atlas.")
    }
    return report
}

private func validateReport(_ report: DuplicateReport) throws {
    var ids = Set<String>()
    var total: Int64 = 0
    for (index, group) in report.groups.enumerated() {
        if index % 1024 == 0 { try Task.checkCancellation() }
        guard report.version == 1, ids.insert(group.id).inserted else { throw invalidReport() }
        let bytes = try validatedRepeatedBytes(group)
        let sum = total.addingReportingOverflow(bytes)
        guard !sum.overflow else { throw invalidReport() }
        total = sum.partialValue
    }
}

private func validatedRepeatedBytes(_ group: DuplicateGroup) throws -> Int64 {
    guard group.files.count >= 2, group.fileBytes >= 0, group.files.allSatisfy({ $0.bytes == group.fileBytes }),
        Set(group.files.map(\.path)).count == group.files.count
    else { throw invalidReport() }
    let size = group.fileBytes.multipliedReportingOverflow(by: Int64(group.files.count - 1))
    guard !size.overflow else { throw invalidReport() }
    return size.partialValue
}

private func invalidReport() -> CLIError {
    CLIError(
        code: "invalid_report", message: "Invalid duplicate group structure or size totals.",
        hint: "Create a fresh report with duplicates --output.")
}

func saveReport(_ report: DuplicateReport, to output: URL) throws {
    let data = try Snapshot.encoder.encode(report)
    guard data.count <= 256 * 1024 * 1024 else {
        throw CLIError(
            code: "report_too_large", message: "Report exceeds 256 MiB.", hint: "Narrow the duplicate search.")
    }
    try savePrivate(data, to: output)
}

func saveSnapshot(_ snapshot: Snapshot, to output: URL) throws {
    try savePrivate(Snapshot.encoder.encode(snapshot), to: output)
}

/// Publish a complete private file exclusively. A failed write cannot leave a partial export.
private func savePrivate(_ data: Data, to output: URL) throws {
    let temporary = output.deletingLastPathComponent().appendingPathComponent(".disk-atlas-export-" + UUID().uuidString)
    let fd = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { _ = temporary.path.withCString { unlink($0) } }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: data)
    try handle.close()
    let result = temporary.path.withCString { source in output.path.withCString { link(source, $0) } }
    guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

func reportResult(_ report: DuplicateReport, page: PageOptions, group: String?) throws -> [String: Any] {
    try validateReport(report)
    var result: [String: Any] = [
        "roots": report.roots, "groupCount": report.groups.count, "readBytes": report.readBytes,
        "elapsed": report.elapsed, "cancelled": report.cancelled, "skipped": report.skipped,
        "hardLinks": report.hardLinks, "checkedAt": ISO8601DateFormatter().string(from: report.checkedAt),
        "repeatedLogicalBytes": report.repeatedBytes, "guaranteedReclaimableBytes": NSNull(),
        "issues": try object(report.issues), "readContents": true,
        "status": report.cancelled
            ? "cancelled" : report.inputPartial == true || !report.issues.isEmpty ? "partial" : "complete",
    ]
    if let group {
        guard let selected = report.groups.first(where: { $0.id == group }) else {
            throw CLIError.missing("Group is not in this report: \(group)")
        }
        let files = page.slice(selected.files).map { file in
            ["path": file.path, "bytes": file.bytes, "modified": ISO8601DateFormatter().string(from: file.modified)]
                as [String: Any]
        }
        result["group"] = group
        result["files"] = files
        result.merge(page.metadata(total: selected.files.count, returned: files.count)) { _, new in new }
    } else {
        let ordered = try DuplicateSort.repeatedBytes.ordered(report.groups, descending: true)
        let groups = page.slice(ordered).map { item in
            [
                "id": item.id, "copies": item.files.count, "fileBytes": item.fileBytes,
                "repeatedLogicalBytes": item.repeatedBytes, "previewPaths": item.files.prefix(3).map(\.path),
                "pathsTruncated": item.files.count > 3,
            ] as [String: Any]
        }
        result["groups"] = groups
        result.merge(page.metadata(total: ordered.count, returned: groups.count)) { _, new in new }
    }
    return result
}
