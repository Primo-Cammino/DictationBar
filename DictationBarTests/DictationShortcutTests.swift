import AppKit
import Carbon
import XCTest
@testable import DictationBar

final class DictationShortcutTests: XCTestCase {
    func testDefaultPreservesExistingShortcutAndOptionRIsSupported() throws {
        XCTAssertEqual(DictationShortcut.default.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(DictationShortcut.default.modifiers, UInt32(controlKey | optionKey))
        let shortcut = try XCTUnwrap(DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)))
        XCTAssertEqual(shortcut.displayName, "⌥R")
        XCTAssertEqual(DictationShortcut.default.displayName, "⌃⌥Leertaste")
    }

    func testBareKeyShiftOnlyModifierKeysAndUnknownCarbonFlagsAreRejected() {
        XCTAssertNil(DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: 0))
        XCTAssertNil(DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(shiftKey)))
        XCTAssertNil(DictationShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0))
        XCTAssertNil(DictationShortcut(keyCode: UInt32(kVK_Option), modifiers: UInt32(optionKey)))
        XCTAssertNil(DictationShortcut(keyCode: 128, modifiers: UInt32(optionKey)))
        XCTAssertNil(DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey) | (1 << 31)))
    }

    func testValidShortcutRoundTripsThroughConfigurationStorage() throws {
        let shortcut = try XCTUnwrap(DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey)))
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(DictationShortcut.self, from: data), shortcut)
        XCTAssertThrowsError(try JSONDecoder().decode(DictationShortcut.self, from: Data("{\"keyCode\":15,\"modifiers\":0}".utf8)))
    }

    func testEventCaptureUsesHardwareKeyAndSupportedModifiers() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                  modifierFlags: [.option, .capsLock], timestamp: 0,
                                                  windowNumber: 0, context: nil, characters: "®",
                                                  charactersIgnoringModifiers: "r", isARepeat: false,
                                                  keyCode: UInt16(kVK_ANSI_R)))
        let shortcut = try XCTUnwrap(DictationShortcut.capture(event))
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_R))
        XCTAssertEqual(shortcut.modifiers, UInt32(optionKey))
    }
}
