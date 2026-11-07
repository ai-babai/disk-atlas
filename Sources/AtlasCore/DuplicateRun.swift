import Foundation

/// One cooperative worker owns progress and candidates; no shared mutable hashing state.
final class DuplicateRun {
    struct Sample {
        let file: DuplicateFile
        let key: String
        let complete: String?
    }
    let plan: DuplicatePlan
    let finder: DuplicateFinder
    let control: DuplicateControl
    let progress: @Sendable (DuplicateProgress) -> Void
    let found: @Sendable ([DuplicateGroup]) -> Void
    let start = Date()
    var value = DuplicateProgress()
    var last = Date.distantPast
    var skipped: Int
    var issues: [ScanIssue]
    private(set) var groups: [DuplicateGroup] = []
    var pending: [DuplicateGroup] = []

    init(
        plan: DuplicatePlan, finder: DuplicateFinder, control: DuplicateControl,
        progress: @escaping @Sendable (DuplicateProgress) -> Void, found: @escaping @Sendable ([DuplicateGroup]) -> Void
    ) {
        self.plan = plan
        self.finder = finder
        self.control = control
        self.progress = progress
        self.found = found
        skipped = plan.skipped
        issues = plan.issues
    }
    func run() throws -> DuplicateReport {
        var stopped = false
        do {
            let survivors = try sampleFiles()
            let hashed = try hashFiles(survivors)
            try verify(hashed)
        } catch is CancellationError { stopped = true }
        value.phase = .finished
        emit(force: true)
        return DuplicateReport(
            roots: plan.roots, snapshotCreated: plan.snapshotCreated, checkedAt: Date(), options: plan.options,
            groups: groups.sorted { $0.repeatedBytes > $1.repeatedBytes }, skipped: skipped, hardLinks: plan.hardLinks,
            issues: issues, readBytes: value.readBytes, elapsed: control.elapsed(since: start), cancelled: stopped,
            inputPartial: plan.inputPartial)
    }
    private func emit(force: Bool = false) {
        guard force || Date().timeIntervalSince(last) >= 0.15 else { return }
        if !pending.isEmpty {
            found(pending)
            pending.removeAll(keepingCapacity: true)
        }
        value.activeSeconds = control.elapsed(since: start)
        value.groups = groups.count
        progress(value)
        last = Date()
    }
    private func advanced(_ count: Int) {
        value.phaseBytes += Int64(count)
        value.readBytes += Int64(count)
        emit()
    }
    private func failed(_ file: DuplicateFile, _ error: Error) {
        skipped += 1
        if issues.count < 20 { issues.append(ScanIssue(path: file.path, message: error.localizedDescription)) }
    }
    private func sampleFiles() throws -> [[Sample]] {
        value.phase = .sampling
        value.phaseTotal = plan.buckets.reduce(0) {
            $0 + $1.reduce(0) { $0 + DuplicateFinder.sampleReadBytes($1.bytes) }
        }
        value.futureReadBytes = plan.estimatedReadBytes
        emit(force: true)
        var sampled: [String: [Sample]] = [:]
        for file in plan.buckets.joined() {
            try control.checkpoint()
            do {
                let complete = file.bytes <= 1_048_576
                let hash =
                    try complete
                    ? finder.digest(file, control: control, advanced: advanced)
                    : finder.sample(file, control: control, advanced: advanced)
                let key = String(file.bytes) + ":" + hash
                sampled[key, default: []].append(Sample(file: file, key: key, complete: complete ? hash : nil))
            } catch is CancellationError { throw CancellationError() } catch { failed(file, error) }
            value.examined += 1
            emit()
        }
        return sampled.values.filter { $0.count > 1 && $0.contains { plan.options.matchesDate($0.file.modified) } }
            .sorted { $0[0].file.bytes > $1[0].file.bytes }
    }
    private func isDirectPair(_ bucket: [Sample]) -> Bool { bucket.count == 2 && bucket[0].complete == nil }
    private func hashBytes(_ bucket: [Sample]) -> Int64 {
        isDirectPair(bucket) ? 0 : bucket.reduce(0) { $0 + ($1.complete == nil ? $1.file.bytes : 0) }
    }
    private func hashFiles(_ survivors: [[Sample]]) throws -> [String: [DuplicateFile]] {
        value.phase = .hashing
        value.phaseBytes = 0
        value.phaseTotal = survivors.reduce(0) { $0 + hashBytes($1) }
        value.futureReadBytes = survivors.reduce(0) { $0 + Int64($1.count - 1) * $1[0].file.bytes * 2 }
        emit(force: true)
        var hashed: [String: [DuplicateFile]] = [:]
        for bucket in survivors {
            try control.checkpoint()
            if isDirectPair(bucket) {
                hashed["pair:" + bucket[0].key] = bucket.map(\.file)
            } else {
                try hashBucket(bucket, into: &hashed)
            }
        }
        return hashed
    }
    private func hashBucket(_ bucket: [Sample], into hashed: inout [String: [DuplicateFile]]) throws {
        for candidate in bucket {
            try control.checkpoint()
            do {
                let file = candidate.file
                let hash = try candidate.complete ?? finder.digest(file, control: control, advanced: advanced)
                hashed[String(file.bytes) + ":" + hash, default: []].append(file)
            } catch is CancellationError { throw CancellationError() } catch { failed(candidate.file, error) }
        }
    }
    private func verify(_ hashed: [String: [DuplicateFile]]) throws {
        let matches = hashed.filter {
            $0.value.count > 1 && $0.value.contains { plan.options.matchesDate($0.modified) }
        }.sorted { $0.value[0].bytes > $1.value[0].bytes }
        value.phase = .verifying
        value.phaseBytes = 0
        value.futureReadBytes = 0
        value.phaseTotal = matches.reduce(0) { $0 + Int64($1.value.count - 1) * $1.value[0].bytes * 2 }
        emit(force: true)
        for (digest, files) in matches { try confirm(files, fingerprint: digest) }
    }
    /// Fingerprint collisions are partitioned by actual bytes, preserving every distinct duplicate group.
    func confirm(_ files: [DuplicateFile], fingerprint: String) throws {
        var partitions: [[DuplicateFile]] = []
        for file in files {
            try control.checkpoint()
            do { try insert(file, into: &partitions) } catch is CancellationError { throw CancellationError() } catch {
                failed(file, error)
            }
        }
        for (offset, partition) in partitions.enumerated() {
            let confirmed = try validFiles(partition)
            if confirmed.count > 1 && confirmed.contains(where: { plan.options.matchesDate($0.modified) }) {
                publish(confirmed, id: fingerprint + ":" + String(offset))
            }
        }
    }
    private func insert(_ file: DuplicateFile, into partitions: inout [[DuplicateFile]]) throws {
        for index in partitions.indices {
            if try finder.equal(partitions[index][0], file, control: control, advanced: advanced) {
                partitions[index].append(file)
                return
            }
        }
        try finder.validate(file)
        partitions.append([file])
    }
    private func validFiles(_ files: [DuplicateFile]) throws -> [DuplicateFile] {
        var result: [DuplicateFile] = []
        for file in files {
            try control.checkpoint()
            do {
                try finder.validate(file)
                result.append(file)
            } catch { failed(file, error) }
        }
        return result
    }
    private func publish(_ confirmed: [DuplicateFile], id: String) {
        var group = DuplicateGroup(id: id, files: confirmed)
        let sample = Array(confirmed.prefix(200))
        group.displayName = sample.map { URL(fileURLWithPath: $0.path).lastPathComponent }.min { $0.count < $1.count }
        group.locations = Array(
            Set(sample.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().lastPathComponent })
        ).sorted().prefix(3).map { $0 }
        value.metadataBytes += group.files.reduce(160) { $0 + Int64($1.path.utf8.count + 240) }
        groups.append(group)
        pending.append(group)
        emit()
    }
}
