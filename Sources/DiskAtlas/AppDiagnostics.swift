import AtlasCore
import SwiftUI

/// Values are deliberately typed: never accept raw errors, file names or paths here.
struct DiagnosticOperation: Codable, Sendable {
    enum Kind: String, Codable { case scan, duplicates }
    enum Status: String, Codable { case completed, cancelled }
    let kind: Kind
    let milliseconds: Int
    let objects: Int
    let status: Status
}

struct ReportDiagnostics: Codable, Sendable {
    enum Screen: String, Codable { case home, contents, largest, duplicates, duplicateOverview }
    let appVersion: String
    let appBuild: String
    let macOS: String
    var screen: Screen = .home
    var lastOperation: DiagnosticOperation?
    var errorCode: AppDiagnostics.Failure?
    static var system: Self {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: info["CFBundleVersion"] as? String ?? "unknown",
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
    var summary: String { "Disk Atlas \(appVersion) (\(appBuild)) · macOS \(macOS)" }
    var description: String {
        let titles: [Screen: String] = [
            .home: "Главная", .contents: "Содержимое", .largest: "Крупные файлы", .duplicates: "Дубликаты",
            .duplicateOverview: "Все дубликаты",
        ]
        var lines = [L10n.text("Экран") + ": " + L10n.text(titles[screen] ?? "Главная")]
        if let lastOperation {
            let title = lastOperation.kind == .scan ? "Анализ" : "Проверка дубликатов"
            lines.append(L10n.text(title) + ": " + String(lastOperation.milliseconds) + " ms")
            lines.append(L10n.text("Объектов") + ": " + String(lastOperation.objects))
            lines.append(L10n.text(lastOperation.status == .cancelled ? "Остановлено" : "Завершено"))
        }
        if let errorCode { lines.append(L10n.text("Код ошибки") + ": " + errorCode.rawValue) }
        return lines.joined(separator: "\n")
    }
    var json: Data { get throws { try JSONEncoder().encode(self) } }
}

@MainActor final class AppDiagnostics: ObservableObject {
    enum Failure: String, Codable, Sendable { case scanFailed, duplicatePreparationFailed, duplicateCheckFailed }
    static let shared = AppDiagnostics()
    @Published var enabled = UserDefaults.standard.bool(forKey: "atlas.diagnostics.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "atlas.diagnostics.enabled")
            if !enabled { stop() }
        }
    }
    @Published private(set) var lastOperation: DiagnosticOperation?
    @Published private(set) var errorCode: Failure?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var remaining = 20
    private var retryAfter = Date.distantPast

    func report(screen: ReportDiagnostics.Screen) -> ReportDiagnostics {
        var result = ReportDiagnostics.system
        result.screen = screen
        result.lastOperation = lastOperation
        result.errorCode = errorCode
        return result
    }
    func completed(_ kind: DiagnosticOperation.Kind, seconds: Double, objects: Int, cancelled: Bool) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let operation = DiagnosticOperation(
            kind: kind, milliseconds: Int(min(seconds, 31_536_000) * 1000), objects: max(0, objects),
            status: cancelled ? .cancelled : .completed)
        lastOperation = operation
        submit(operation: operation, failure: nil)
    }
    func failed(_ failure: Failure) {
        errorCode = failure
        submit(operation: nil, failure: failure)
    }
    private func submit(operation: DiagnosticOperation?, failure: Failure?) {
        guard enabled, task == nil, remaining > 0, Date() >= retryAfter else { return }
        remaining -= 1
        generation = UUID()
        let key = generation
        task = Task {
            defer { if generation == key { task = nil } }
            do {
                let body = try FeedbackSender.telemetryEnvelope(operation: operation, failure: failure)
                try Task.checkCancellation()
                try await FeedbackSender.upload(body)
            } catch {
                // Never loop/retry or report transport errors recursively.
                if generation == key { retryAfter = Date().addingTimeInterval(3600) }
            }
        }
    }
    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
