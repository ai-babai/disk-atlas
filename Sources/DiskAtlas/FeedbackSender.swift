import AtlasCore
import Foundation

/// Shared allowlisted Sentry transport. No SDK, disk queue, cookies or redirects.
struct FeedbackSender {
    // Public ingestion key, not an account token. It grants no read or administration access.
    static let dsn = "https://226db62cd9903a19fef1ddb0f8f9afa4@o4512408671813632.ingest.us.sentry.io/4512408708055040"
    private static let endpoint = URL(
        string: "https://o4512408671813632.ingest.us.sentry.io/api/4512408708055040/envelope/")!

    static func envelope(
        message: String, email: String, kind: String, diagnostics: ReportDiagnostics,
        attachment: FeedbackAttachment? = nil
    ) throws -> Data {
        var feedback = ["message": message]
        if !email.isEmpty { feedback["contact_email"] = email }
        let context = try JSONSerialization.data(withJSONObject: feedback)
        guard context.count <= 8192 else { throw FeedbackError.tooLarge }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var event: [String: Any] = [
            "event_id": id, "timestamp": Date().timeIntervalSince1970, "platform": "cocoa",
            "contexts": ["feedback": feedback], "tags": ["feedback_type": kind],
        ]
        event["contexts"] = [
            "feedback": feedback, "app_diagnostics": try JSONSerialization.jsonObject(with: diagnostics.json),
            "os": ["name": "macOS", "version": diagnostics.macOS],
        ]
        event["release"] = "disk-atlas@" + diagnostics.appVersion
        event["dist"] = diagnostics.appBuild
        return try pack(event: event, type: "feedback", id: id, attachment: attachment)
    }

    static func telemetryEnvelope(operation: DiagnosticOperation?, failure: AppDiagnostics.Failure?) throws -> Data {
        let system = ReportDiagnostics.system
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let now = Date().timeIntervalSince1970
        var event: [String: Any] = [
            "event_id": id, "timestamp": now, "platform": "cocoa", "release": "disk-atlas@" + system.appVersion,
            "dist": system.appBuild, "contexts": ["os": ["name": "macOS", "version": system.macOS]],
        ]
        if let failure {
            event["message"] = "Disk Atlas: " + failure.rawValue
            event["level"] = "error"
            event["fingerprint"] = ["disk-atlas", failure.rawValue]
        }
        if let operation {
            event["type"] = "transaction"
            event["transaction"] = "disk-atlas." + operation.kind.rawValue
            event["start_timestamp"] = now - Double(operation.milliseconds) / 1000
            event["spans"] = [] as [String]
            event["contexts"] = [
                "os": ["name": "macOS", "version": system.macOS],
                "trace": [
                    "trace_id": id, "span_id": String(id.prefix(16)), "op": "app." + operation.kind.rawValue,
                    "status": operation.status == .cancelled ? "cancelled" : "ok",
                ],
            ]
            event["extra"] = ["objects": operation.objects, "duration_ms": operation.milliseconds]
        }
        return try pack(event: event, type: operation == nil ? "event" : "transaction", id: id)
    }

    private static func pack(event: [String: Any], type: String, id: String, attachment: FeedbackAttachment? = nil)
        throws -> Data
    {
        let payload = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        let header = try JSONSerialization.data(withJSONObject: ["event_id": id, "dsn": dsn])
        let item = try JSONSerialization.data(withJSONObject: ["type": type, "length": payload.count])
        var body = header + Data([10]) + item + Data([10]) + payload + Data([10])
        if let attachment {
            guard attachment.data.count <= 2_000_000 else { throw AttachmentError.invalid }
            let item = try JSONSerialization.data(withJSONObject: [
                "type": "attachment", "length": attachment.data.count, "filename": "screenshot.jpg",
                "content_type": "image/jpeg", "attachment_type": "event.attachment",
            ])
            body += item + Data([10]) + attachment.data + Data([10])
        }
        return body
    }

    static func upload(_ body: Data) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: FeedbackRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        request.setValue("DiskAtlas-Feedback", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw FeedbackError.unavailable }
        if http.statusCode == 429 { throw FeedbackError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw FeedbackError.unavailable }
    }
}

private final class FeedbackRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

enum FeedbackError: LocalizedError {
    case tooLarge, rateLimited, unavailable
    var errorDescription: String? {
        switch self {
        case .tooLarge: return L10n.text("Сообщение слишком большое. Сократи текст и попробуй ещё раз.")
        case .rateLimited: return L10n.text("Сервис временно ограничил отправку. Попробуй позже — текст сохранён.")
        case .unavailable: return L10n.text("Не удалось отправить сообщение. Попробуй позже — текст сохранён.")
        }
    }
}
