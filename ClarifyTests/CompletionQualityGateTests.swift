import XCTest
@testable import Clarify

final class CompletionQualityGateTests: XCTestCase {
    func testCompleteSentencePasses() {
        let text = "A fragment is an incomplete piece of text."
        XCTAssertTrue(CompletionQualityGate.isComplete(text))
    }

    func testDanglingSuffixFails() {
        let text = "In this context, fragment refers to a"
        let reasons = CompletionQualityGate.reasons(for: text)
        XCTAssertTrue(reasons.contains(.danglingSuffix))
    }

    func testMissingTerminalPunctuationFails() {
        let text = "A fragment is an incomplete piece of text"
        let reasons = CompletionQualityGate.reasons(for: text)
        XCTAssertTrue(reasons.contains(.missingTerminalPunctuation))
    }

    func testUnmatchedDelimiterOutsideCodeFenceFails() {
        let text = "This fails because the compiler call( returns early."
        let reasons = CompletionQualityGate.reasons(for: text)
        XCTAssertTrue(reasons.contains(.unmatchedDelimiter))
    }

    func testUnmatchedDelimiterInsideCodeFenceIsIgnored() {
        let text = """
        Use this expression:
        ```swift
        let broken = call(
        ```
        It indicates an unfinished invocation.
        """

        XCTAssertTrue(CompletionQualityGate.isComplete(text))
    }
}
