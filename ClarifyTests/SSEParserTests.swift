import XCTest
@testable import Clarify

final class SSEParserTests: XCTestCase {
    func testParseDelta() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        if case .delta(let text) = events.first {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected delta event")
        }
    }

    func testParseDone() {
        let parser = SSEParser()
        let chunk = "data: [DONE]\n\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        if case .done(let reason) = events.first {
            XCTAssertEqual(reason, .doneMarker)
        } else {
            XCTFail("Expected done event")
        }
    }

    func testParseErrorResponse() {
        let parser = SSEParser()
        let chunk = "data: {\"error\":{\"message\":\"Invalid API key\"}}\n\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        if case .error(let message) = events.first {
            XCTAssertEqual(message, "Invalid API key")
        } else {
            XCTFail("Expected error event")
        }
    }

    func testParseMultipleEvents() {
        let parser = SSEParser()
        let chunk = """
        data: {"choices":[{"delta":{"content":"Hello "},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"world"},"finish_reason":null}]}

        data: [DONE]

        """

        var events = parser.parse(chunk)
        events += parser.finish()

        XCTAssertEqual(events.count, 3)
        if case .delta(let text) = events[0] {
            XCTAssertEqual(text, "Hello ")
        }
        if case .delta(let text) = events[1] {
            XCTAssertEqual(text, "world")
        }
        if case .done(let reason) = events[2] {
            XCTAssertEqual(reason, .doneMarker)
        }
    }

    func testParsePartialChunks() {
        let parser = SSEParser()

        // First chunk: incomplete
        let events1 = parser.parse("data: {\"choices\":[{\"delta\":{\"content\":")
        XCTAssertEqual(events1.count, 0)

        // Second chunk: completes the event
        let events2 = parser.parse("\"Hello\"},\"finish_reason\":null}]}\n\n")
        XCTAssertEqual(events2.count, 1)
        if case .delta(let text) = events2.first {
            XCTAssertEqual(text, "Hello")
        }
    }

    func testEmptyDeltaStillEmitsStopReason() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .done(.stop))
    }

    func testReset() {
        let parser = SSEParser()
        _ = parser.parse("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}")
        parser.reset()
        let events = parser.parse("data: {\"choices\":[{\"delta\":{\"content\":\"fresh\"},\"finish_reason\":null}]}\n\n")
        XCTAssertEqual(events.count, 1)
    }

    func testFinishParsesTrailingBlockWithoutBlankLine() {
        let parser = SSEParser()

        let events = parser.parse("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n")
        XCTAssertTrue(events.isEmpty)

        let flushed = parser.finish()
        XCTAssertEqual(flushed.count, 1)
        if case .delta(let text) = flushed[0] {
            XCTAssertEqual(text, "partial")
        } else {
            XCTFail("Expected delta event after finish()")
        }
    }

    func testParsesCRLFSSEFrames() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\r\n\r\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        if case .delta(let text) = events[0] {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected delta event")
        }
    }

    func testDeltaWithRoleOnlyIsSkipped() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n"

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 0, "Role-only delta should be skipped")
    }

    func testFinishReasonLengthEmitsLengthStopReason() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .done(.length))
    }

    func testFinishReasonStopEmitsStopReason() {
        let parser = SSEParser()
        let chunk = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"

        let events = parser.parse(chunk)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .done(.stop))
    }
}
