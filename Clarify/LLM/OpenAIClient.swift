import Foundation

final class OpenAIClient: StreamingClient, Sendable {
    private let apiKey: String
    private let model: String
    private let urlSession: URLSession

    /// Shared persistent session with keep-alive for connection reuse across requests.
    private static let persistentSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    init(apiKey: String, model: String, urlSession: URLSession? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = urlSession ?? Self.persistentSession
    }

    /// Pre-warm the TLS connection to the API endpoint. Call once at app launch.
    static func prewarmConnection() {
        guard let url = URL(string: Constants.apiEndpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        persistentSession.dataTask(with: request) { _, _, _ in }.resume()
    }

    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let messages = [
            ChatMessage(role: "system", content: instructions),
            ChatMessage(role: "user", content: input)
        ]
        return try await streamChat(messages: messages, maxOutputTokens: maxOutputTokens)
    }

    func streamChat(
        messages: [ChatMessage],
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: true,
            maxTokens: maxOutputTokens
        )
        return try await performStream(
            request: request,
            messages: messages,
            maxOutputTokens: maxOutputTokens
        )
    }

    private func performStream(
        request: ChatCompletionRequest,
        messages: [ChatMessage],
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let body = try JSONEncoder().encode(request)
        let urlRequest = makeURLRequest(body: body, timeout: Constants.requestTimeout)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await urlSession.bytes(for: urlRequest)
        } catch {
            if Self.isTimeoutError(error),
               let fallback = try await fetchNonStreamingFallbackText(
                    messages: messages,
                    maxOutputTokens: maxOutputTokens
               ) {
                return Self.oneShotStream(text: fallback)
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClarifyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw ClarifyError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return AsyncThrowingStream { continuation in
            let parseTask = Task {
                let parser = SSEParser()
                var terminalStopReason: CompletionStopReason?
                var didEmitDone = false
                var didEmitText = false
                var didEmitError = false

                func mergedStopReason(
                    current: CompletionStopReason?,
                    incoming: CompletionStopReason
                ) -> CompletionStopReason {
                    let rank: (CompletionStopReason) -> Int = { reason in
                        switch reason {
                        case .stop, .length, .unknown:
                            return 3
                        case .fallback:
                            return 2
                        case .doneMarker:
                            return 1
                        }
                    }

                    guard let current else { return incoming }
                    return rank(incoming) >= rank(current) ? incoming : current
                }

                func finalStopReason(from raw: CompletionStopReason?) -> CompletionStopReason {
                    switch raw {
                    case .doneMarker:
                        return .unknown
                    case .some(let reason):
                        return reason
                    case .none:
                        return .unknown
                    }
                }

                func yield(_ event: StreamEvent) {
                    switch event {
                    case .delta(let text):
                        guard !text.isEmpty else { return }
                        didEmitText = true
                        continuation.yield(.delta(text))
                    case .error(let message):
                        didEmitError = true
                        continuation.yield(.error(message))
                    case .done(let reason):
                        terminalStopReason = mergedStopReason(current: terminalStopReason, incoming: reason)
                    }
                }

                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let chunk = line + "\n"
                        let events = parser.parse(chunk)
                        for event in events {
                            yield(event)
                        }
                    }

                    for event in parser.finish() {
                        yield(event)
                    }

                    if !Task.isCancelled && !didEmitText && !didEmitError {
                        if let fallback = try await self.fetchNonStreamingFallbackText(
                            messages: messages,
                            maxOutputTokens: maxOutputTokens
                        ) {
                            didEmitText = true
                            terminalStopReason = mergedStopReason(current: terminalStopReason, incoming: .fallback)
                            continuation.yield(.delta(fallback))
                        }
                    }

                    if !didEmitDone && !didEmitError && (terminalStopReason != nil || didEmitText) {
                        didEmitDone = true
                        continuation.yield(.done(finalStopReason(from: terminalStopReason)))
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        if Self.isTimeoutError(error), didEmitText {
                            if !didEmitDone && !didEmitError {
                                continuation.yield(.done(finalStopReason(from: terminalStopReason)))
                            }
                            continuation.finish()
                            return
                        }
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                parseTask.cancel()
            }
        }
    }

    private func fetchNonStreamingFallbackText(
        messages: [ChatMessage],
        maxOutputTokens: Int? = nil,
        timeout: TimeInterval = Constants.fallbackRequestTimeout
    ) async throws -> String? {
        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: false,
            maxTokens: maxOutputTokens
        )
        let body = try JSONEncoder().encode(request)
        let urlRequest = makeURLRequest(body: body, timeout: timeout)

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClarifyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let snippet = String(data: Data(data.prefix(500)), encoding: .utf8) ?? ""
            throw ClarifyError.apiError(statusCode: httpResponse.statusCode, message: snippet)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extracted = extractTextFromResponsePayload(json),
              !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return extracted
    }

    private static func oneShotStream(text: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.delta(text))
            continuation.yield(.done(.fallback))
            continuation.finish()
        }
    }

    private static func isTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    private func makeURLRequest(body: Data, timeout: TimeInterval) -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: Constants.apiEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = timeout
        return urlRequest
    }

    /// Extracts text from a non-streaming Chat Completions response.
    /// Format: { "choices": [{ "message": { "content": "..." } }] }
    private func extractTextFromResponsePayload(_ payload: [String: Any]) -> String? {
        guard let choices = payload["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }
}

enum ClarifyError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code, let message):
            if code == 401 {
                return "Invalid API key"
            }
            return "API error (\(code)): \(message)"
        }
    }
}
