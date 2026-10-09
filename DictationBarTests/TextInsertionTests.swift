import XCTest
@testable import DictationBar

final class TextInsertionTests: XCTestCase {
    @MainActor
    func testCurrentTargetSelectionWithUnicodeGetsOneConfirmedPasteAndRetainsClipboard() async {
        let environment = InsertionFake()
        environment.target = environment.makeTarget(value: "vor 🌱 nach", selection: NSRange(location: 4, length: 2))
        let service = TextInsertionService(environment: environment, readbackDelay: 0)
        let status = await service.insert("Grüße", isCurrent: { true })
        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(environment.target?.value, "vor Grüße nach")
        XCTAssertEqual(environment.pastes, 1)
        XCTAssertEqual(environment.clipboard, "Grüße")
    }

    @MainActor
    func testAbsentSecureReadOnlyDisabledAndOwnFieldsLeaveClipboardUntouched() async {
        let environment = InsertionFake()
        let candidates: [FocusedTextTarget?] = [nil,
            environment.makeTarget(secure: true), environment.makeTarget(enabled: false),
            environment.makeTarget(writable: false), environment.makeTarget(processID: 42),
            environment.makeTarget(role: "AXButton")]
        for target in candidates {
            environment.target = target
            let result = await TextInsertionService(environment: environment, readbackDelay: 0).insert("Text", isCurrent: { true })
            XCTAssertEqual(result, .unavailable)
            XCTAssertEqual(environment.clipboard, "previous")
            XCTAssertEqual(environment.pastes, 0)
        }
        environment.target = environment.makeTarget()
        environment.isPermitted = false
        let result = await TextInsertionService(environment: environment).insert("Text", isCurrent: { true })
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(environment.clipboard, "previous")
    }

    @MainActor
    func testFocusAndClipboardChangesBeforePostPreventPaste() async {
        let environment = InsertionFake()
        environment.onRead = { count in
            if count == 2 { environment.target = environment.makeTarget() }
        }
        let result = await TextInsertionService(environment: environment, readbackDelay: 0).insert("Text", isCurrent: { true })
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(environment.pastes, 0)
        let changedClipboard = InsertionFake()
        changedClipboard.onRead = { count in
            if count == 2 { changedClipboard.clipboard = "foreign change"; changedClipboard.clipboardRevision += 1 }
        }
        let changed = await TextInsertionService(environment: changedClipboard, readbackDelay: 0).insert("Text", isCurrent: { true })
        XCTAssertEqual(changed, .unconfirmed)
        XCTAssertEqual(changedClipboard.pastes, 0)
        XCTAssertEqual(changedClipboard.clipboard, "foreign change")
    }

    @MainActor
    func testQuitOrExpiredAXWorkDoesNotSendLatePaste() async {
        let environment = InsertionFake()
        var valid = true
        environment.onRead = { _ in valid = false }
        let result = await TextInsertionService(environment: environment).insert("Text", isCurrent: { valid })
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(environment.pastes, 0)
        XCTAssertEqual(environment.clipboard, "previous")
        let expired = InsertionFake()
        var clock: TimeInterval = 0
        expired.onRead = { _ in clock = 3 }
        let timeout = await TextInsertionService(environment: expired, now: { clock }).insert("Text", isCurrent: { true })
        XCTAssertEqual(timeout, .unavailable)
        XCTAssertEqual(expired.pastes, 0)
    }

    @MainActor
    func testReadbackMismatchNeverRepeatsPasteOrClaimsSuccess() async {
        let environment = InsertionFake()
        environment.confirms = false
        let result = await TextInsertionService(environment: environment, readbackDelay: 0).insert("Text", isCurrent: { true })
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(environment.pastes, 1)
        XCTAssertEqual(environment.clipboard, "Text")
    }
}

@MainActor
private final class InsertionFake: TextInsertionEnvironment {
    var isPermitted = true
    var ownProcessID: Int32 = 42
    var clipboardRevision = 0
    var clipboard = "previous"
    var target: FocusedTextTarget?
    var reads = 0
    var pastes = 0
    var confirms = true
    var onRead: ((Int) -> Void)?
    init() { target = makeTarget() }

    func makeTarget(value: String = "Existing", selection: NSRange = NSRange(location: 8, length: 0),
                    secure: Bool = false, enabled: Bool = true, writable: Bool = true,
                    processID: Int32 = 7, role: String = "AXTextArea", id: UUID = UUID()) -> FocusedTextTarget {
        FocusedTextTarget(id: id, processID: processID, role: role, secure: secure, enabled: enabled,
                          writable: writable, value: value, selection: selection)
    }
    func focusedTarget(deadline: TimeInterval) async -> FocusedTextTarget? {
        reads += 1; onRead?(reads); return target
    }
    func setClipboard(_ text: String) -> Int? { clipboard = text; clipboardRevision += 1; return clipboardRevision }
    func postPaste() -> Bool {
        pastes += 1
        if confirms, let target, let expected = target.expectedValue(inserting: clipboard, ownProcessID: ownProcessID) {
            self.target = makeTarget(value: expected, selection: NSRange(location: target.selection.location + clipboard.utf16.count, length: 0), id: target.id)
        }
        return true
    }
    func requestPermission() { }
}
