import AtlasCore
import Foundation

/// Manual feedback only. No SDK, background collection, disk queue, cookies or redirects.
struct FeedbackSender {
    // Public ingestion key, not an account token. It grants no read or administration access.
    static let dsn = "https://226db62cd9903a19fef1ddb0f8f9afa4@o4512408671813632.ingest.us.sentry.io/4512408708055040"
    private static let endpoint = URL(
        string: "https://o4512408671813632.ingest.us.sentry.io/api/4512408708055040/envelope/")!

    static func envelope(message: String, email: String, kind: String, diagnostics: String?) throws -> Data {
        var feedback = ["message": message]
        if !email.isEmpty { feedback["contact_email"] = email }
        let context = try JSONSerialization.data(withJSONObject: feedback)
        guard context.count <= 8192 else { throw FeedbackError.tooLarge }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var event: [String: Any] = [
            "event_id": id, "timestamp": Date().timeIntervalSince1970, "platform": "cocoa",
            "contexts": ["feedback": feedback], "tags": ["feedback_type": kind],
        ]
        if let diagnostics { event["extra"] = ["app_and_system": diagnostics] }
        let payload = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        let header = try JSONSerialization.data(withJSONObject: ["event_id": id, "dsn": dsn])
        let item = try JSONSerialization.data(withJSONObject: ["type": "feedback", "length": payload.count])
        return header + Data([10]) + item + Data([10]) + payload + Data([10])
    }

    static func send(message: String, email: String, kind: String, diagnostics: String?) async throws {
        let body = try envelope(message: message, email: email, kind: kind, diagnostics: diagnostics)
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
