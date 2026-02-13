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

    init(model: String, instructions: String, input: String, stream: Bool = true, maxTokens: Int? = nil) {
        self.model = model
        self.messages = [
            ChatMessage(role: "system", content: instructions),
            ChatMessage(role: "user", content: input)
        ]
        self.stream = stream
        self.maxTokens = maxTokens
        self.temperature = 0
        self.store = false
    }
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
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

enum StreamEvent: Equatable, Sendable {
    case delta(String)
    case done
    case error(String)
}

protocol StreamingClient: Sendable {
    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - Streaming Explanation

struct StreamingExplanation {
    let fullText: String
    let mode: ExplanationMode
    let depth: Int
    let context: ContextInfo
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
