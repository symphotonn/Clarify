import XCTest
@testable import Clarify

final class PanelPositionerTests: XCTestCase {
    func testBasicPositioning() {
        // Test that frame has expected width
        let frame = PanelPositioner.frame(
            anchorPoint: CGPoint(x: 500, y: 500),
            contentHeight: 200
        )

        XCTAssertEqual(frame.width, Constants.panelWidth)
        XCTAssertLessThanOrEqual(frame.height, Constants.panelMaxHeight)
    }

    func testMaxHeightClamping() {
        let frame = PanelPositioner.frame(
            anchorPoint: CGPoint(x: 500, y: 500),
            contentHeight: 1000
        )

        XCTAssertEqual(frame.height, Constants.panelMaxHeight)
    }

    func testContentHeightRespected() {
        let frame = PanelPositioner.frame(
            anchorPoint: CGPoint(x: 500, y: 500),
            contentHeight: 150
        )

        XCTAssertEqual(frame.height, 150)
    }
}
