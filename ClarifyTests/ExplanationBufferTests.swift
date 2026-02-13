import XCTest
@testable import Clarify

final class ExplanationBufferTests: XCTestCase {
    private func makeExplanation(text: String) -> StreamingExplanation {
        StreamingExplanation(
            fullText: text,
            mode: .learn,
            depth: 1,
            context: ContextInfo(
                selectedText: "test",
                appName: nil,
                windowTitle: nil,
                surroundingLines: nil,
                selectionBounds: nil
            )
        )
    }

    func testPushAndLast() {
        let buffer = ExplanationBuffer(capacity: 5)
        let explanation = makeExplanation(text: "Hello world")
        buffer.push(explanation)

        XCTAssertEqual(buffer.last()?.fullText, "Hello world")
        XCTAssertEqual(buffer.count, 1)
    }

    func testCapacityLimit() {
        let buffer = ExplanationBuffer(capacity: 3)

        for i in 0..<5 {
            buffer.push(makeExplanation(text: "item \(i)"))
        }

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.last()?.fullText, "item 4")
    }

    func testClear() {
        let buffer = ExplanationBuffer(capacity: 5)
        buffer.push(makeExplanation(text: "test"))
        buffer.clear()

        XCTAssertNil(buffer.last())
        XCTAssertEqual(buffer.count, 0)
    }

    func testEmptyBuffer() {
        let buffer = ExplanationBuffer(capacity: 5)
        XCTAssertNil(buffer.last())
        XCTAssertEqual(buffer.count, 0)
    }
}
