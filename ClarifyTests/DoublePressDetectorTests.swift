import XCTest
@testable import Clarify

final class DoublePressDetectorTests: XCTestCase {
    func testSinglePress() {
        let detector = DoublePressDetector(threshold: 0.4)
        let result = detector.recordPress()
        XCTAssertFalse(result, "First press should not be a double press")
    }

    func testDoublePress() {
        let detector = DoublePressDetector(threshold: 0.4)
        _ = detector.recordPress()
        Thread.sleep(forTimeInterval: 0.06) // clear debounce floor (> 0.05s)
        let result = detector.recordPress()
        XCTAssertTrue(result, "Second press within threshold should be a double press")
    }

    func testSlowDoublePress() {
        let detector = DoublePressDetector(threshold: 0.1)
        _ = detector.recordPress()
        Thread.sleep(forTimeInterval: 0.15)
        let result = detector.recordPress()
        XCTAssertFalse(result, "Press after threshold should not be a double press")
    }

    func testReset() {
        let detector = DoublePressDetector(threshold: 0.4)
        _ = detector.recordPress()
        detector.reset()
        let result = detector.recordPress()
        XCTAssertFalse(result, "After reset, should not detect double press")
    }

    func testTriplePress() {
        let detector = DoublePressDetector(threshold: 0.4)
        _ = detector.recordPress()
        Thread.sleep(forTimeInterval: 0.06)
        let second = detector.recordPress()
        Thread.sleep(forTimeInterval: 0.06)
        let third = detector.recordPress()
        XCTAssertTrue(second)
        XCTAssertTrue(third, "Third rapid press should also register as double")
    }
}
