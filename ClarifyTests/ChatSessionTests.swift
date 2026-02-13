import XCTest
@testable import Clarify

final class ChatSessionTests: XCTestCase {
    @MainActor
    func testInitSeedsSystemAndAssistantMessages() {
        let session = ChatSession(
            context: Self.makeContext(),
            explanation: "Initial explanation"
        )

        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages[0].role, .system)
        XCTAssertEqual(session.messages[1].role, .assistant)
        XCTAssertEqual(session.messages[1].content, "Initial explanation")
    }

    @MainActor
    func testAppendUserMessageFromInputTrimsAndClearsInput() {
        let session = ChatSession(context: Self.makeContext(), explanation: "Initial")
        session.currentInput = "   Why does this happen?   "

        let message = session.appendUserMessageFromInput()

        XCTAssertEqual(message?.role, .user)
        XCTAssertEqual(message?.content, "Why does this happen?")
        XCTAssertEqual(session.currentInput, "")
        XCTAssertEqual(session.messages.last?.role, .user)
    }

    @MainActor
    func testAppendAssistantPlaceholderAndDelta() {
        let session = ChatSession(context: Self.makeContext(), explanation: "Initial")

        _ = session.appendAssistantPlaceholder()
        session.appendDelta("Hello")
        session.appendDelta(" world")
        session.finishStreaming()

        XCTAssertEqual(session.messages.last?.role, .assistant)
        XCTAssertEqual(session.messages.last?.content, "Hello world")
        XCTAssertFalse(session.isStreaming)
    }

    @MainActor
    func testBuildAPIMessagesMapsConversationRoles() {
        let session = ChatSession(context: Self.makeContext(), explanation: "Initial")
        session.currentInput = "Follow up"
        _ = session.appendUserMessageFromInput()

        let apiMessages = session.buildAPIMessages()

        XCTAssertEqual(apiMessages.count, 3)
        XCTAssertEqual(apiMessages[0].role, "system")
        XCTAssertEqual(apiMessages[1].role, "assistant")
        XCTAssertEqual(apiMessages[2].role, "user")
        XCTAssertEqual(apiMessages[2].content, "Follow up")
    }

    private static func makeContext() -> ContextInfo {
        ContextInfo(
            selectedText: "overlay phase",
            appName: "Xcode",
            windowTitle: "Editor",
            surroundingLines: "if phase == .result { ... }",
            selectionBounds: nil,
            selectedOccurrenceContext: "if phase == .result { ... }"
        )
    }
}
