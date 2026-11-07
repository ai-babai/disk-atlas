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
    for key in ["minimumBytes", "maximumBytes"] {
        if let input = args[key] {
            guard let n = input as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                n.doubleValue >= 0, n.doubleValue < Double(Int64.max), n.doubleValue.rounded() == n.doubleValue
            else { throw AtlasError.message("\(key): expected a non-negative integer.") }
            if key == "minimumBytes" { value.minimumBytes = n.int64Value } else { value.maximumBytes = n.int64Value }
        }
    }
    if let input = args["kinds"] {
        guard let kinds = input as? [String] else {
            throw AtlasError.message("kinds: expected an array of file types.")
        }
        for name in kinds {
            guard let kind = FileKind(rawValue: name), kind != .folder && kind != .link else {
                throw AtlasError.message("Unknown file type: \(name)")
            }
            value.kinds.insert(kind)
        }
    }
    let formatter = ISO8601DateFormatter()
    for key in ["modifiedAfter", "modifiedBefore"] where args[key] != nil {
        guard let text = args[key] as? String, let date = formatter.date(from: text) else {
            throw AtlasError.message("\(key): expected an ISO 8601 date.")
        }
        if key == "modifiedAfter" { value.modifiedAfter = date } else { value.modifiedBefore = date }
    }
    return value
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
    guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) else {
        throw AtlasError.message("paths: supply absolute selected directory paths.")
    }
    if read {
        guard let flag = args["readContents"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(), flag.boolValue
        else { throw AtlasError.message("Explicit readContents: true is required to read file contents.") }
    }
    let options = try duplicateOptions(args)
    if args["output"] != nil && args["output"] as? String == nil {
        throw AtlasError.message("output: expected a new absolute JSON report path.")
    }
    let output = args["output"] as? String
    if let output {
        guard output.hasPrefix("/"), !FileManager.default.fileExists(atPath: output) else {
            throw AtlasError.message("Output must be a new absolute file path.")
        }
    }
    let snapshot = try DiskScanner().scan(paths: paths)
    let plan = try DuplicateFinder().prepare(snapshot, options: options)
    if !read { return duplicatePlanSummary(plan) }
    let report = try DuplicateFinder().run(plan)
    if let output {
        let data = try Snapshot.encoder.encode(report)
        let fd = output.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
    }
    let groups: [[String: Any]] = try report.groups.prefix(50).map { group in
        [
            "id": group.id, "copies": group.files.count, "fileBytes": group.fileBytes,
            "repeatedLogicalBytes": group.repeatedBytes, "files": try object(Array(group.files.prefix(20))),
        ]
    }
    var result: [String: Any] = [
        "roots": report.roots, "groupCount": report.groups.count, "groups": groups,
        "repeatedLogicalBytes": report.repeatedBytes, "guaranteedReclaimableBytes": NSNull(),
        "readBytes": report.readBytes, "elapsed": report.elapsed, "cancelled": report.cancelled,
        "skipped": report.skipped, "hardLinks": report.hardLinks, "issues": try object(report.issues), "bounded": true,
        "readContents": true,
    ]
    if let output { result["report"] = output }
    return result
}

func duplicateCLI(_ args: [String]) throws {
    let paths = Array(args.prefix { !$0.hasPrefix("--") })
    var value: [String: Any] = ["paths": paths]
    var position = paths.count
    var seen = Set<String>()
    let keys = [
        "--min-bytes": "minimumBytes", "--max-bytes": "maximumBytes", "--modified-after": "modifiedAfter",
        "--modified-before": "modifiedBefore", "--types": "kinds", "--output": "output",
    ]
    var read = false
    while position < args.count {
        let key = args[position]
        guard seen.insert(key).inserted else { throw AtlasError.message("Repeated option: \(key)") }
        if key == "--read-contents" {
            read = true
            value["readContents"] = true
            position += 1
            continue
        }
        guard let name = keys[key], position + 1 < args.count else {
            throw AtlasError.message("Unknown option or missing value: \(key)")
        }
        let raw = args[position + 1]
        if name == "minimumBytes" || name == "maximumBytes" {
            guard let number = Int64(raw), number >= 0 else { throw AtlasError.message("Invalid byte size: \(raw)") }
            value[name] = number
        } else if name == "kinds" {
            value[name] = raw.split(separator: ",").map(String.init)
        } else {
            value[name] = raw
        }
        position += 2
    }
    if !read && value["output"] != nil {
        throw AtlasError.message("--output requires --read-contents; a metadata estimate does not produce a report.")
    }
    print(try json(runDuplicateTool(value, read: read)))
}
