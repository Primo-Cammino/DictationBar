import ApplicationServices
import XCTest
@testable import DictationBar

final class NativeFocusTests: XCTestCase {
    func testFocusChangeDuringAttributeCollectionRejectsSnapshot() async {
        let original = AXUIElementCreateApplication(getppid())
        let changed = AXUIElementCreateApplication(getppid() + 1)
        var current = original
        var focusReads = 0
        var range = CFRange(location: 0, length: 0)
        let selection = AXValueCreate(.cfRange, &range)!
        let reader = AXTargetReader(focusedElement: { _ in
            focusReads += 1
            return current
        }, readAttribute: { _, name in
            switch name {
            case kAXRoleAttribute: return kAXTextAreaRole as CFString
            case kAXEnabledAttribute: return kCFBooleanTrue
            case kAXValueAttribute: return "Neutral text" as CFString
            case kAXSelectedTextRangeAttribute:
                current = changed
                return selection
            default: return nil
            }
        }, valueSettable: { _ in true })
        let result = await reader.read(deadline: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertNil(result)
        XCTAssertEqual(focusReads, 2)
    }

    func testStableNativeSnapshotRemainsEligible() async {
        let element = AXUIElementCreateApplication(getppid())
        var range = CFRange(location: 0, length: 0)
        let selection = AXValueCreate(.cfRange, &range)!
        let reader = AXTargetReader(focusedElement: { _ in element }, readAttribute: { _, name in
            switch name {
            case kAXRoleAttribute: return kAXTextAreaRole as CFString
            case kAXEnabledAttribute: return kCFBooleanTrue
            case kAXValueAttribute: return "Neutral text" as CFString
            case kAXSelectedTextRangeAttribute: return selection
            default: return nil
            }
        }, valueSettable: { _ in true })
        let result = await reader.read(deadline: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(result?.value, "Neutral text")
        XCTAssertEqual(result?.processID, getppid())
    }

    func testMissingEnabledAttributeIsEligibleButExplicitlyDisabledIsNot() async {
        let element = AXUIElementCreateApplication(getppid())
        var range = CFRange(location: 0, length: 0)
        let selection = AXValueCreate(.cfRange, &range)!
        func reader(enabled: CFTypeRef?) -> AXTargetReader {
            AXTargetReader(focusedElement: { _ in element }, readAttribute: { _, name in
                switch name {
                case kAXRoleAttribute: return kAXTextAreaRole as CFString
                case kAXEnabledAttribute: return enabled
                case kAXValueAttribute: return "Neutral text" as CFString
                case kAXSelectedTextRangeAttribute: return selection
                default: return nil
                }
            }, valueSettable: { _ in true })
        }
        let missing = await reader(enabled: nil).read(deadline: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(missing?.value, "Neutral text")
        let disabled = await reader(enabled: kCFBooleanFalse).read(deadline: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertNil(disabled)
    }
}
