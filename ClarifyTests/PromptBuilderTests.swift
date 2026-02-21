import XCTest
@testable import Clarify

final class PromptBuilderTests: XCTestCase {
    func testIncludesWordLimit() {
        let context = ContextInfo(
            selectedText: "gradient descent",
            appName: "Safari",
            windowTitle: "Machine Learning Guide",
            surroundingLines: "some surrounding text",
            selectionBounds: nil
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.instructions.contains("\(Constants.wordLimit)"))
        XCTAssertTrue(parts.input.contains("gradient descent"))
        XCTAssertTrue(parts.input.contains("Source: Safari"))
        XCTAssertTrue(parts.input.contains("title: Machine Learning Guide"))
        XCTAssertEqual(parts.maxOutputTokens, 160)
    }

    func testModeClassificationInstructions() {
        let context = ContextInfo(
            selectedText: "test",
            appName: nil,
            windowTitle: nil,
            surroundingLines: nil,
            selectionBounds: nil
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.instructions.contains("[MODE: Learn]"))
        XCTAssertTrue(parts.instructions.contains("[MODE: Simplify]"))
        XCTAssertTrue(parts.instructions.contains("[MODE: Diagnose]"))
    }

    func testInstructionsEmphasizeSimpleContextAwareDisambiguation() {
        let context = ContextInfo(
            selectedText: "bat",
            appName: "Google Chrome",
            windowTitle: "Example",
            surroundingLines: "He hit the ball with a bat.",
            selectionBounds: nil
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.instructions.contains("concise explanation assistant"))
        XCTAssertTrue(parts.instructions.contains("1-2 sentences"))
        XCTAssertTrue(parts.instructions.contains("First sentence must answer directly"))
        XCTAssertTrue(parts.instructions.contains("Be as simple and concise as possible."))
        XCTAssertTrue(parts.instructions.contains("Output at most two short sentences."))
        XCTAssertTrue(parts.instructions.contains("Never stop mid-sentence."))
        XCTAssertTrue(parts.instructions.contains("Use provided context"))
        XCTAssertTrue(parts.instructions.contains("never refuse"))
    }

    func testInputIncludesContextQualityAndShortSelectionHint() {
        let context = ContextInfo(
            selectedText: "bat",
            appName: "Google Chrome",
            windowTitle: nil,
            surroundingLines: "A bat flew out of the cave at night.",
            selectionBounds: nil,
            selectedOccurrenceContext: "A bat flew out of the cave at night."
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.input.contains("Context quality: selected occurrence available"))
        XCTAssertTrue(parts.input.contains("Selected occurrence context:\nA bat flew out of the cave at night."))
        XCTAssertTrue(parts.input.contains("Constraint: explain in 1-2 sentences."))
        XCTAssertTrue(parts.input.contains("minimum useful explanation"))
        XCTAssertTrue(parts.input.contains("complete sentence, not a fragment"))
        XCTAssertTrue(parts.input.contains("most likely meaning first"))
    }

    func testIdentifierIntentForCodeLikeSelection() {
        let context = ContextInfo(
            selectedText: "overlayPhase",
            appName: "Google Chrome",
            windowTitle: "Clarify UX Plan",
            surroundingLines: "Use a unified overlayPhase container for loading and streaming.",
            selectionBounds: nil
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.input.contains("Intent: Identifier lookup"))
        XCTAssertTrue(parts.instructions.contains("Treat as identifier"))
    }

    func testConversationContextIsMarkedLowTrust() {
        let context = ContextInfo(
            selectedText: "overlayPhase",
            appName: "Google Chrome",
            windowTitle: "ChatGPT",
            surroundingLines: nil,
            selectionBounds: nil,
            selectedOccurrenceContext: nil,
            sourceURL: "https://chatgpt.com/c/abc",
            sourceHint: "ChatGPT",
            isConversationContext: true
        )

        let parts = PromptBuilder.build(context: context)

        XCTAssertTrue(parts.instructions.contains("Conversation context may be noisy"))
        XCTAssertTrue(parts.input.contains("Context quality: conversation context excluded by default"))
    }

    func testSurroundingLinesIncludesSelectedLine() {
        let text = """
        title
        He hit the ball with a bat.
        A bat flew out of the cave at night.
        footer
        """

        guard let range = text.range(of: "bat.") else {
            XCTFail("Failed to find selected range")
            return
        }

        let surrounding = text.surroundingLines(around: range, count: 1)
        XCTAssertTrue(surrounding.contains("He hit the ball with a bat."))
    }

    func testInferExpertiseForCodeEditor() {
        let context = ContextInfo(
            selectedText: "foo",
            appName: "Xcode",
            windowTitle: "Editor",
            surroundingLines: nil,
            selectionBounds: nil
        )
        XCTAssertEqual(PromptBuilder.inferExpertise(from: context), .expert)
        XCTAssertEqual(PromptBuilder.inferTone(from: context), .technical)
    }

    func testInferExpertiseForDocsURL() {
        let context = ContextInfo(
            selectedText: "foo",
            appName: "Safari",
            windowTitle: "Docs",
            surroundingLines: nil,
            selectionBounds: nil,
            sourceURL: "https://developer.apple.com/docs/swift"
        )
        XCTAssertEqual(PromptBuilder.inferExpertise(from: context), .intermediate)
        XCTAssertEqual(PromptBuilder.inferTone(from: context), .neutral)
    }

    func testInferExpertiseForGeneralApp() {
        let context = ContextInfo(
            selectedText: "foo",
            appName: "Notes",
            windowTitle: "My Note",
            surroundingLines: nil,
            selectionBounds: nil
        )
        XCTAssertEqual(PromptBuilder.inferExpertise(from: context), .beginner)
        XCTAssertEqual(PromptBuilder.inferTone(from: context), .friendly)
    }

    func testBuildChatSystemMessageIncludesSourceAndAmbiguityRule() {
        let context = ContextInfo(
            selectedText: "overlayPhase",
            appName: "Xcode",
            windowTitle: "Editor",
            surroundingLines: "if session.phase == .result { ... }",
            selectionBounds: nil,
            selectedOccurrenceContext: "if session.phase == .result { ... }"
        )

        let prompt = PromptBuilder.buildChatSystemMessage(context: context)

        XCTAssertTrue(prompt.contains("first sentence"))
        XCTAssertTrue(prompt.contains("best guess"))
        XCTAssertTrue(prompt.contains("Source context: Xcode"))
        XCTAssertTrue(prompt.contains("Selected text:\noverlayPhase"))
    }
}
