import AtlasCore
import Darwin
import Foundation

/// One foreground process, cooperative cancellation; no daemon or persistent jobs.
final class CLIWork: @unchecked Sendable {
    let scanCancellation = ScanCancellation()
    let duplicates = DuplicateControl()
    private let lock = NSLock()
    private var state: [String: Any] = ["phase": "starting"]
    private var stopped = false
    private let options: WorkOptions
    private let terminal: Bool
    private var frame = 0
    init(_ options: WorkOptions) {
        self.options = options
        terminal = isatty(STDERR_FILENO) != 0
    }
    func check() throws {
        try Task.checkCancellation()
        if scanCancellation.isCancelled { throw CancellationError() }
    }
    func cancel() {
        scanCancellation.cancel()
        duplicates.cancel()
        update("stopping")
    }
    func update(_ phase: String) {
        lock.lock()
        state = ["phase": phase]
        lock.unlock()
    }
    func duplicateProgress(_ progress: DuplicateProgress) {
        lock.lock()
        state = [
            "phase": progress.phase.rawValue, "examined": progress.examined, "readBytes": progress.readBytes,
            "phaseBytes": progress.phaseBytes, "phaseTotal": progress.phaseTotal, "groups": progress.groups,
            "metadataBytes": progress.metadataBytes,
        ]
        lock.unlock()
    }
    func scan(_ paths: [String]) throws -> Snapshot {
        update("scanning")
        return try DiskScanner().scan(paths: paths, cancellation: scanCancellation) { progress in
            self.lock.lock()
            self.state = [
                "phase": "scanning", "entries": progress.entries, "bytes": progress.bytes,
                "metadataBytes": progress.metadataBytes,
            ]
            self.lock.unlock()
        }
    }
    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, !options.quiet, terminal || options.progress else { return }
        var value = state
        value["event"] = "progress"
        value["schemaVersion"] = 1
        frame += 1
        let text: String
        if options.progress {
            text = ((try? json(value, pretty: false)) ?? "{}") + "\n"
        } else {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            text = "\r\u{1B}[2K\(frames[frame % frames.count]) \(value["phase"] ?? "working") · Ctrl-C to stop"
        }
        try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
    }
    private func finish() {
        lock.lock()
        stopped = true
        if terminal && !options.quiet && !options.progress {
            try? FileHandle.standardError.write(contentsOf: Data("\r\u{1B}[2K".utf8))
        }
        lock.unlock()
    }
    static func perform(_ options: WorkOptions, operation: @escaping @Sendable (CLIWork) async throws -> [String: Any])
        async throws -> [String: Any]
    {
        let context = CLIWork(options)
        let task = Task.detached { try await operation(context) }
        let sources = context.signals { task.cancel() }
        context.tick()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
        timer.setEventHandler { context.tick() }
        timer.resume()
        defer {
            timer.cancel()
            for source in sources { source.cancel() }
            context.finish()
        }
        do {
            var result = try await task.value
            if context.scanCancellation.isCancelled { result["status"] = "cancelled" }
            return result
        } catch is CancellationError {
            throw CLIError(
                code: "cancelled", message: "Operation stopped.", hint: "No source files were changed.", status: 130)
        }
    }
    private func signals(_ cancelTask: @escaping @Sendable () -> Void) -> [DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                self.cancel()
                cancelTask()
            }
            source.resume()
            return source
        }
    }
}
