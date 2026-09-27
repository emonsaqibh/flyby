import Foundation
import FlybyCore

enum GeminiError: LocalizedError {
    case missingKey
    case invalidKey
    case permissionDenied(String?)
    case modelNotFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable(Int)
    /// Gemini finished without an answer, or stopped one early, for a reason
    /// other than running out of things to say: `SAFETY`, `RECITATION`, …
    case blocked(String)
    case http(Int, String?)
    case malformedRequest

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add a Gemini API key in Settings (⌘,) to get inline answers."
        case .invalidKey:
            return "Gemini didn't accept the API key. Check it in Settings (⌘,) — a fresh one is free at aistudio.google.com/apikey."
        case .permissionDenied(let message):
            return "Gemini refused this API key." + Self.suffix(message)
        case .modelNotFound(let model):
            return "Gemini has no model called “\(model)” — it may have been retired. Pick another in Settings (⌘,)."
        case .rateLimited(let retryAfter):
            let wait = retryAfter.map { "Try again in \(Int($0.rounded(.up))) seconds." } ?? "Wait a moment and try again."
            return "Gemini's rate limit was hit — the free tier allows only so many requests a minute and a day. \(wait)"
        case .unavailable(let status):
            return "Gemini is overloaded or down right now (\(status)). Try again in a moment."
        case .blocked(let reason):
            return Self.explanation(forStop: reason)
        case .http(let status, let message):
            return "Gemini returned \(status)." + Self.suffix(message)
        case .malformedRequest:
            return "The Gemini model name in Settings isn't valid."
        }
    }

    private static func suffix(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "" }
        return "\n" + String(message.prefix(300))
    }

    /// The finish reasons that mean "stopped on purpose", worded for someone
    /// who just asked a question.
    static func explanation(forStop reason: String) -> String {
        switch reason {
        case "SAFETY", "IMAGE_SAFETY":
            return "Gemini withheld this answer on safety grounds."
        case "RECITATION":
            return "Gemini stopped because the answer would have quoted a source too closely."
        case "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
            return "Gemini won't answer this query."
        case "MAX_TOKENS":
            return "Gemini stopped at its length limit."
        default:
            return "Gemini stopped without finishing (\(reason))."
        }
    }
}

/// Streams an answer from the Gemini API with Google Search grounding turned on,
/// so results reflect the live web rather than training data.
enum GeminiProvider {
    enum Event: Sendable {
        case text(String)
        case sources([WebSource])
    }

    static func stream(query: String) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(query: query) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Finish reasons that mean the model stopped on purpose, not because it
    /// was done.
    private static let abnormalStops: Set<String> = [
        "SAFETY", "IMAGE_SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII",
        "MAX_TOKENS", "OTHER", "MALFORMED_FUNCTION_CALL", "LANGUAGE",
    ]

    /// A 429 or 503 before anything streamed is usually a momentary spike, so
    /// one quiet retry saves the user a click. Not when the server asks for a
    /// long wait — then the message saying so is more useful than a spinner.
    private static let maxRetryDelay: TimeInterval = 5
    private static let defaultRetryDelay: TimeInterval = 1.5

    private static func run(query: String, emit: @escaping (Event) -> Void) async throws {
        let settings = await MainActor.run {
            (key: AppSettings.shared.geminiKey, model: AppSettings.shared.geminiModel)
        }
        let key = settings.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeminiError.missingKey }
        let model = normalizedModel(settings.model)

        let request = try makeRequest(query: query, model: model, key: key)

        for attempt in 0..<2 {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                try await consume(bytes, emit: emit)
                return
            }

            let body = try await collect(bytes, limit: 64 * 1024)
            let detail = APIError(body)
            let error = mapError(status: status, detail: detail, model: model)

            if attempt == 0, status == 429 || status == 503 {
                let header = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
                let delay = detail?.retryDelay ?? header ?? defaultRetryDelay
                if delay <= maxRetryDelay {
                    try await Task.sleep(nanoseconds: UInt64(max(delay, 0.2) * 1_000_000_000))
                    continue
                }
            }
            throw error
        }
    }

    /// "models/gemini-x" pasted from the docs works too; an empty field means
    /// the default rather than a request for no model at all.
    private static func normalizedModel(_ raw: String) -> String {
        var model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.hasPrefix("models/") { model.removeFirst("models/".count) }
        return model.isEmpty ? AppSettings.defaultGeminiModel : model
    }

    private static func makeRequest(query: String, model: String, key: String) throws -> URLRequest {
        guard let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):streamGenerateContent?alt=sse")
        else { throw GeminiError.malformedRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60

        // Gemini 3 wants its default temperature — Google warns that lowering
        // it can make the model loop — and thinks by default; a search answer
        // wants the first words fast, so thinking is kept low. Older models
        // get the settings they were tuned with here.
        let generationConfig: [String: Any] = model.hasPrefix("gemini-3")
            ? ["thinkingConfig": ["thinkingLevel": "LOW"]]
            : ["temperature": 0.3]

        let body: [String: Any] = [
            "contents": [["parts": [["text": query]]]],
            "tools": [["google_search": [String: Any]()]],
            "generationConfig": generationConfig,
            "systemInstruction": [
                "parts": [["text": """
                Answer the user's query directly and concisely, the way a good search \
                result would. Lead with the answer itself. Use short paragraphs or a \
                few bullets. Skip preamble and skip offers of further help.
                """]]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func consume(_ bytes: URLSession.AsyncBytes, emit: @escaping (Event) -> Void) async throws {
        // An array, not a dictionary: dictionary order is unstable, which made
        // the source chips shuffle on every streamed update.
        var sources: [WebSource] = []
        var emittedText = false
        var finishReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Errors can arrive mid-stream as an event of their own.
            if json["error"] != nil, let detail = APIError(json) {
                throw mapError(status: detail.code ?? 500, detail: detail, model: "")
            }

            guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
                // No candidate at all means the prompt itself was refused.
                if let feedback = json["promptFeedback"] as? [String: Any],
                   let reason = feedback["blockReason"] as? String {
                    throw GeminiError.blocked(reason)
                }
                continue
            }

            if let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
                // Thought summaries are only sent when asked for, but if they
                // ever are, they aren't the answer.
                let text = parts
                    .filter { ($0["thought"] as? Bool) != true }
                    .compactMap { $0["text"] as? String }
                    .joined()
                if !text.isEmpty {
                    emittedText = true
                    emit(.text(text))
                }
            }

            if let grounding = candidate["groundingMetadata"] as? [String: Any],
               let chunks = grounding["groundingChunks"] as? [[String: Any]] {
                let before = sources.count
                sources.merge(chunks.compactMap { chunk in
                    guard let web = chunk["web"] as? [String: Any],
                          let uri = web["uri"] as? String,
                          let url = URL(string: uri) else { return nil }
                    let title = web["title"] as? String ?? url.host ?? uri
                    return WebSource(title: title, url: url, siteName: title)
                })
                if sources.count != before { emit(.sources(sources)) }
            }

            if let reason = candidate["finishReason"] as? String {
                finishReason = reason
            }
        }

        guard let reason = finishReason, abnormalStops.contains(reason) else { return }
        if emittedText {
            // Keep what arrived and say why it ends there, rather than
            // replacing a mostly-complete answer with an error.
            emit(.text("\n\n*" + GeminiError.explanation(forStop: reason) + "*"))
        } else {
            throw GeminiError.blocked(reason)
        }
    }

    /// Reads an error response's body, capped: it's for a message, and a
    /// misbehaving proxy shouldn't get to stream megabytes into it.
    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    private static func mapError(status: Int, detail: APIError?, model: String) -> GeminiError {
        let message = detail?.message
        if detail?.reasons.contains("API_KEY_INVALID") == true
            || (status == 400 && message?.localizedCaseInsensitiveContains("API key not valid") == true) {
            return .invalidKey
        }
        switch status {
        case 401, 403:
            return .permissionDenied(message)
        case 404:
            return model.isEmpty ? .http(status, message) : .modelNotFound(model)
        case 429:
            return .rateLimited(retryAfter: detail?.retryDelay)
        case 500...599:
            return .unavailable(status)
        default:
            return .http(status, message ?? detail?.status)
        }
    }

    /// Google's error envelope: `{"error": {"code", "message", "status",
    /// "details": [{"reason": …}, {"retryDelay": "12s"}]}}` — sometimes
    /// wrapped in a one-element array.
    private struct APIError {
        var code: Int?
        var message: String?
        var status: String?
        var reasons: [String]
        var retryDelay: TimeInterval?

        init?(_ data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            let root = (object as? [String: Any]) ?? (object as? [[String: Any]])?.first
            guard let root else { return nil }
            self.init(root)
        }

        init?(_ root: [String: Any]) {
            guard let error = root["error"] as? [String: Any] else { return nil }
            code = error["code"] as? Int
            message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            status = error["status"] as? String
            let details = error["details"] as? [[String: Any]] ?? []
            reasons = details.compactMap { $0["reason"] as? String }
            retryDelay = details
                .compactMap { $0["retryDelay"] as? String }
                .first
                .flatMap { TimeInterval($0.replacingOccurrences(of: "s", with: "")) }
        }
    }
}
