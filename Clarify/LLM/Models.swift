import Foundation

// MARK: - Request

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let maxTokens: Int?
    let temperature: Double
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case maxTokens = "max_tokens"
        case temperature
        case store
    }

    init(
        model: String,
        messages: [ChatMessage],
        stream: Bool = true,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.maxTokens = maxTokens
        self.temperature = 0
        self.store = false
    }

    init(model: String, instructions: String, input: String, stream: Bool = true, maxTokens: Int? = nil) {
        self.init(
            model: model,
            messages: [
                ChatMessage(role: "system", content: instructions),
                ChatMessage(role: "user", content: input)
            ],
            stream: stream,
            maxTokens: maxTokens
        )
    }
}

struct ChatMessage: Encodable, Equatable, Sendable {
    let role: String
    let content: String
}

enum ConversationRole: String, Sendable {
    case system
    case assistant
    case user
}

struct ConversationMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: ConversationRole
    var content: String

    init(id: UUID = UUID(), role: ConversationRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Explanation Mode

enum ExplanationMode: String, CaseIterable {
    case learn = "Learn"
    case simplify = "Simplify"
    case diagnose = "Diagnose"

    static func parse(from line: String) -> ExplanationMode? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("[MODE: Learn]") || trimmed.contains("[MODE: LEARN]") { return .learn }
        if trimmed.contains("[MODE: Simplify]") || trimmed.contains("[MODE: SIMPLIFY]") { return .simplify }
        if trimmed.contains("[MODE: Diagnose]") || trimmed.contains("[MODE: DIAGNOSE]") { return .diagnose }
        return nil
    }
}

// MARK: - Stream Events

enum CompletionStopReason: Equatable, Sendable {
    case stop
    case length
    case doneMarker
    case fallback
    case unknown
}

enum StreamEvent: Equatable, Sendable {
    case delta(String)
    case done(CompletionStopReason)
    case error(String)
}

protocol StreamingClient: Sendable {
    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>

    func streamChat(
        messages: [ChatMessage],
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

extension StreamingClient {
    func streamChat(
        messages: [ChatMessage],
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemInstructions = messages.first(where: { $0.role == "system" })?.content ?? ""
        let transcript = messages
            .filter { $0.role != "system" }
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        return try await stream(
            instructions: systemInstructions,
            input: transcript,
            maxOutputTokens: maxOutputTokens
        )
    }
}

// MARK: - Prompt Parts

struct PromptParts {
    let instructions: String
    let input: String
    let maxOutputTokens: Int
}

// MARK: - Expertise & Tone

enum ExpertiseLevel: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case expert = "Expert"

    var description: String {
        switch self {
        case .beginner: "Assume no prior knowledge. Use simple language and analogies."
        case .intermediate: "Assume working knowledge. Be concise but explain non-obvious details."
        case .expert: "Assume deep knowledge. Focus on nuance, edge cases, and precision."
        }
    }
}

enum Tone: String, CaseIterable {
    case friendly = "Friendly"
    case neutral = "Neutral"
    case technical = "Technical"

    var description: String {
        switch self {
        case .friendly: "Warm and approachable, using everyday language."
        case .neutral: "Clear and balanced."
        case .technical: "Precise and information-dense."
        }
    }
}
