import AtlasCore
import SwiftUI

/// One in-memory draft survives closing and reopening the feedback window.
@MainActor final class FeedbackModel: ObservableObject {
    @Published var message = ""
    @Published var email = ""
    @Published var kind = "bug"
    @Published private(set) var attachment: FeedbackAttachment?
    @Published private(set) var loadingAttachment = false
    @Published private(set) var sending = false
    @Published private(set) var sent = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var attachmentTask: Task<Void, Never>?
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
    func attach(_ url: URL) {
        guard !sending, !loadingAttachment else { return }
        loadingAttachment = true
        error = nil
        attachmentTask = Task {
            let worker = Task.detached(priority: .userInitiated) { try FeedbackAttachment.load(url) }
            do {
                let image = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                attachment = image
            } catch { if !Task.isCancelled { self.error = AttachmentError.invalid.localizedDescription } }
            guard !Task.isCancelled else { return }
            loadingAttachment = false
            attachmentTask = nil
        }
    }
    func attachmentFailed() { error = AttachmentError.invalid.localizedDescription }
    func removeAttachment() { attachment = nil }
    func send(diagnostics: ReportDiagnostics) {
        guard !sending, !loadingAttachment else { return }
        if let validation {
            error = validation
            return
        }
        sending = true
        error = nil
        let message = message
        let email = email
        let kind = kind
        let attachment = attachment
        task = Task {
            do {
                let body = try FeedbackSender.envelope(
                    message: message, email: email, kind: kind, diagnostics: diagnostics, attachment: attachment)
                try Task.checkCancellation()
                try await FeedbackSender.upload(body)
                guard !Task.isCancelled else { return }
                sent = true
                self.message = ""
                self.email = ""
                self.attachment = nil
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
        if loadingAttachment {
            attachmentTask?.cancel()
            attachmentTask = nil
            loadingAttachment = false
            return
        }
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
