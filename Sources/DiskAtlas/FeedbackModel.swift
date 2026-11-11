import AtlasCore
import SwiftUI

/// One in-memory draft survives closing and reopening the feedback window.
@MainActor final class FeedbackModel: ObservableObject {
    @Published var message = ""
    @Published var email = ""
    @Published var kind = "bug"
    @Published var includeDiagnostics = false
    @Published private(set) var sending = false
    @Published private(set) var sent = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    var length: Int { message.unicodeScalars.count }
    var validation: String? {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.text("Напиши, что произошло или что можно улучшить.")
        }
        if length > 4096 { return L10n.text("Сократи сообщение до 4096 символов.") }
        if !email.isEmpty && email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            return L10n.text("Проверь почту или оставь поле пустым.")
        }
        return nil
    }
    var diagnostics: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Disk Atlas \(version) (\(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    func send() {
        guard !sending else { return }
        if let validation {
            error = validation
            return
        }
        sending = true
        error = nil
        let message = message
        let email = email
        let kind = kind
        let details = includeDiagnostics ? diagnostics : nil
        task = Task {
            do {
                try await FeedbackSender.send(message: message, email: email, kind: kind, diagnostics: details)
                guard !Task.isCancelled else { return }
                sent = true
                self.message = ""
                self.email = ""
                includeDiagnostics = false
            } catch {
                if !Task.isCancelled {
                    self.error =
                        (error as? FeedbackError)?.localizedDescription
                        ?? L10n.text("Нет связи с сервисом. Проверь интернет и повтори отправку — текст сохранён.")
                }
            }
            guard !Task.isCancelled else { return }
            sending = false
            task = nil
        }
    }
    func cancel() {
        task?.cancel()
        task = nil
        sending = false
        error = L10n.text("Отправка остановлена. Текст сохранён; сообщение могло уже попасть в сервис.")
    }
    func writeAnother() {
        sent = false
        error = nil
    }
}
