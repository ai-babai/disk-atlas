import AtlasCore
import CoreFoundation
import Darwin
import Foundation

let duplicateProperties: [String: Any] = [
    "paths": [
        "type": "array", "items": ["type": "string"], "minItems": 1, "description": "Absolute selected directory paths",
    ], "minimumBytes": ["type": "integer", "minimum": 0], "maximumBytes": ["type": "integer", "minimum": 0],
    "modifiedAfter": ["type": "string", "description": "ISO 8601 date; at least one copy in each group must match"],
    "modifiedBefore": ["type": "string", "description": "ISO 8601 date; other-age peers are still compared"],
    "kinds": [
        "type": "array",
        "items": ["type": "string", "enum": FileKind.allCases.filter { $0 != .folder && $0 != .link }.map(\.rawValue)],
    ],
]

func duplicateOptions(_ args: [String: Any]) throws -> DuplicateOptions {
    var value = DuplicateOptions()
    value.minimumBytes = try duplicateBytes(args["minimumBytes"], key: "minimumBytes") ?? 0
    value.maximumBytes = try duplicateBytes(args["maximumBytes"], key: "maximumBytes")
    value.kinds = try duplicateKinds(args["kinds"])
    value.modifiedAfter = try duplicateDate(args["modifiedAfter"], key: "modifiedAfter")
    value.modifiedBefore = try duplicateDate(args["modifiedBefore"], key: "modifiedBefore")
    try validateDuplicateRange(value)
    return value
}

private func validateDuplicateRange(_ options: DuplicateOptions) throws {
    if let maximum = options.maximumBytes, maximum < options.minimumBytes {
        throw AtlasError.message("maximumBytes must be at least minimumBytes.")
    }
    if let after = options.modifiedAfter, let before = options.modifiedBefore, after > before {
        throw AtlasError.message("modifiedAfter must not be later than modifiedBefore.")
    }
}

private func duplicateBytes(_ input: Any?, key: String) throws -> Int64? {
    guard let input else { return nil }
    guard let n = input as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
        n.doubleValue >= 0, n.doubleValue < Double(Int64.max), n.doubleValue.rounded() == n.doubleValue
    else { throw AtlasError.message("\(key): expected a non-negative integer.") }
    return n.int64Value
}

private func duplicateKinds(_ input: Any?) throws -> Set<FileKind> {
    guard let input else { return [] }
    guard let names = input as? [String] else { throw AtlasError.message("kinds: expected an array of file types.") }
    return try Set(
        names.map { name in
            guard let kind = FileKind(rawValue: name), kind != .folder && kind != .link else {
                throw AtlasError.message("Unknown file type: \(name)")
            }
            return kind
        })
}

private func duplicateDate(_ input: Any?, key: String) throws -> Date? {
    guard let input else { return nil }
    guard let text = input as? String, let date = ISO8601DateFormatter().date(from: text) else {
        throw AtlasError.message("\(key): expected an ISO 8601 date.")
    }
    return date
}

func duplicatePlanSummary(_ plan: DuplicatePlan) -> [String: Any] {
    [
        "roots": plan.roots, "candidateCount": plan.candidateCount, "contentBytes": plan.contentBytes,
        "estimatedReadBytesUpperBound": plan.estimatedReadBytes,
        "estimateSeconds": [
            "low": Double(plan.estimatedReadBytes) / 250_000_000 + Double(plan.candidateCount) * 0.0005,
            "high": Double(plan.estimatedReadBytes) / 25_000_000 + Double(plan.candidateCount) * 0.03,
        ], "estimateIsRough": true, "readContents": false, "skipped": plan.skipped, "hardLinks": plan.hardLinks,
        "options": (try? object(plan.options)) ?? [:],
    ]
}

func runDuplicateTool(_ args: [String: Any], read: Bool) throws -> [String: Any] {
    let paths = try duplicateToolPaths(args, read: read)
    let options = try duplicateOptions(args)
    let output = try duplicateToolOutput(args["output"])
    let snapshot = try DiskScanner().scan(paths: paths)
    let plan = try DuplicateFinder().prepare(snapshot, options: options)
    if !read { return duplicatePlanSummary(plan) }
    let report = try DuplicateFinder().run(plan)
    if let output { try saveReport(report, to: output) }
    var page = PageOptions()
    page.limit = 50
    var result = try reportResult(report, page: page, group: nil)
    result["groups"] = try report.groups.prefix(50).map { group in
        [
            "id": group.id, "copies": group.files.count, "fileBytes": group.fileBytes,
            "repeatedLogicalBytes": group.repeatedBytes, "files": try object(Array(group.files.prefix(20))),
        ] as [String: Any]
    }
    result["bounded"] = true
    if let output { result["report"] = output.path }
    return result
}

private func duplicateToolPaths(_ args: [String: Any], read: Bool) throws -> [String] {
    guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) else {
        throw AtlasError.message("paths: supply absolute selected directory paths.")
    }
    if read {
        guard let flag = args["readContents"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(), flag.boolValue
        else { throw AtlasError.message("Explicit readContents: true is required to read file contents.") }
    }
    return paths
}

private func duplicateToolOutput(_ input: Any?) throws -> URL? {
    guard let input else { return nil }
    guard let path = input as? String, path.hasPrefix("/") else {
        throw AtlasError.message("output: expected a new absolute JSON report path.")
    }
    return try newOutput(path)
}
