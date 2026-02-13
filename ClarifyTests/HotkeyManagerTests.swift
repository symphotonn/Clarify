import XCTest
import AppKit
@testable import Clarify

final class HotkeyManagerTests: XCTestCase {
    func testExactHotkeyMatch() {
        let hotkey = HotkeyBinding(
            key: .k,
            useOption: true,
            useCommand: false,
            useControl: true,
            useShift: false
        )

        let matches = HotkeyManager.isHotkeyMatch(
            keyCode: hotkey.key.keyCode,
            flags: [.maskAlternate, .maskControl],
            hotkey: hotkey
        )

        XCTAssertTrue(matches)
    }

    func testHotkeyRejectsMissingModifier() {
        let hotkey = HotkeyBinding(
            key: .space,
            useOption: true,
            useCommand: false,
            useControl: false,
            useShift: false
        )

        let matches = HotkeyManager.isHotkeyMatch(
            keyCode: hotkey.key.keyCode,
            flags: [],
            hotkey: hotkey
        )

        XCTAssertFalse(matches)
    }

    func testHotkeyRejectsExtraModifier() {
        let hotkey = HotkeyBinding(
            key: .space,
            useOption: true,
            useCommand: false,
            useControl: false,
            useShift: false
        )

        let matches = HotkeyManager.isHotkeyMatch(
            keyCode: hotkey.key.keyCode,
            flags: [.maskAlternate, .maskCommand],
            hotkey: hotkey
        )

        XCTAssertFalse(matches)
    }

    func testHotkeyRejectsDifferentKeyCode() {
        let hotkey = HotkeyBinding(
            key: .space,
            useOption: true,
            useCommand: false,
            useControl: false,
            useShift: false
        )

        let matches = HotkeyManager.isHotkeyMatch(
            keyCode: HotkeyKey.a.keyCode,
            flags: [.maskAlternate],
            hotkey: hotkey
        )

        XCTAssertFalse(matches)
    }

    func testHotkeyKeyRoundTripByKeyCode() {
        XCTAssertEqual(HotkeyKey(keyCode: HotkeyKey.space.keyCode), .space)
        XCTAssertEqual(HotkeyKey(keyCode: HotkeyKey.k.keyCode), .k)
        XCTAssertEqual(HotkeyKey(keyCode: HotkeyKey.nine.keyCode), .nine)
        XCTAssertNil(HotkeyKey(keyCode: UInt16.max))
    }

    func testHasAnyModifier() {
        let noModifier = HotkeyBinding(
            key: .a,
            useOption: false,
            useCommand: false,
            useControl: false,
            useShift: false
        )
        XCTAssertFalse(noModifier.hasAnyModifier)

        let withModifier = HotkeyBinding(
            key: .a,
            useOption: false,
            useCommand: true,
            useControl: false,
            useShift: false
        )
        XCTAssertTrue(withModifier.hasAnyModifier)
    }
}
