import Foundation

@MainActor
@Observable
final class ChatSession {
    private(set) var messages: [ConversationMessage]
    var currentInput: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var streamingMessageID: UUID?

    init(context: ContextInfo, explanation: String) {
        var seedMessages: [ConversationMessage] = [
            ConversationMessage(
                role: .system,
                content: PromptBuilder.buildChatSystemMessage(context: context)
            )
        ]

        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExplanation.isEmpty {
            seedMessages.append(
                ConversationMessage(role: .assistant, content: trimmedExplanation)
            )
        }

        messages = seedMessages
    }

    var visibleMessages: [ConversationMessage] {
        messages.filter { $0.role != .system }
    }

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    @discardableResult
    func appendUserMessageFromInput() -> ConversationMessage? {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        currentInput = ""

        let message = ConversationMessage(role: .user, content: trimmed)
        messages.append(message)
        return message
    }

    @discardableResult
    func appendAssistantPlaceholder() -> UUID {
        let message = ConversationMessage(role: .assistant, content: "")
        messages.append(message)
        streamingMessageID = message.id
        isStreaming = true
        return message.id
    }

    func appendAssistantMessage(_ content: String) {
        messages.append(ConversationMessage(role: .assistant, content: content))
    }

    func appendDelta(_ delta: String) {
        guard !delta.isEmpty, let streamingMessageID else { return }
        guard let index = messages.firstIndex(where: { $0.id == streamingMessageID }) else { return }
        messages[index].content += delta
    }

    func finishStreaming() {
        isStreaming = false
        streamingMessageID = nil
    }

    func cancelStreaming() {
        isStreaming = false
        streamingMessageID = nil
    }

    func removeEmptyTrailingAssistantMessage() {
        guard let last = messages.last, last.role == .assistant else { return }
        if last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.removeLast()
        }
    }

    func buildAPIMessages() -> [ChatMessage] {
        messages.map { message in
            ChatMessage(role: message.role.rawValue, content: message.content)
        }
    }
}
