import Foundation

struct FocusedTextTarget: Equatable {
    let id: UUID
    let processID: Int32
    let role: String
    let secure: Bool
    let enabled: Bool
    let writable: Bool
    let value: String
    let selection: NSRange

    func expectedValue(inserting text: String, ownProcessID: Int32) -> String? {
        let length = (value as NSString).length
        guard processID != ownProcessID, ["AXTextField", "AXTextArea"].contains(role),
              !secure, enabled, writable, selection.location >= 0, selection.length >= 0,
              selection.location <= length, selection.length <= length - selection.location else { return nil }
        return (value as NSString).replacingCharacters(in: selection, with: text)
    }
}

@MainActor
protocol TextInsertionEnvironment {
    var isPermitted: Bool { get }
    var permissionSummary: String { get }
    var ownProcessID: Int32 { get }
    var clipboardRevision: Int { get }
    func focusedTarget(deadline: TimeInterval) async -> FocusedTextTarget?
    func setClipboard(_ text: String) -> Int?
    func postPaste() -> Bool
    func requestPermission()
}

extension TextInsertionEnvironment {
    var permissionSummary: String { isPermitted ? "Einfügen freigegeben" : "Einfügefreigabe fehlt" }
}

@MainActor
protocol TextInsertionProviding {
    var isPermitted: Bool { get }
    var permissionSummary: String { get }
    func requestPermission()
    func insert(_ text: String, isCurrent: @escaping @MainActor () -> Bool) async -> InsertionStatus
}

extension TextInsertionProviding {
    var permissionSummary: String { isPermitted ? "Einfügen freigegeben" : "Einfügefreigabe fehlt" }
}

@MainActor
final class TextInsertionService: TextInsertionProviding {
    private let environment: any TextInsertionEnvironment
    private let now: () -> TimeInterval
    private let readbackDelay: UInt64
    var isPermitted: Bool { environment.isPermitted }
    var permissionSummary: String { environment.permissionSummary }

    init(environment: any TextInsertionEnvironment,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         readbackDelay: UInt64 = 100_000_000) {
        self.environment = environment
        self.now = now
        self.readbackDelay = readbackDelay
    }

    func requestPermission() { environment.requestPermission() }

    func insert(_ text: String, isCurrent: @escaping @MainActor () -> Bool) async -> InsertionStatus {
        let deadline = now() + 2
        guard !text.isEmpty, isCurrent(), environment.isPermitted,
              let target = await environment.focusedTarget(deadline: deadline),
              let expected = target.expectedValue(inserting: text, ownProcessID: environment.ownProcessID),
              now() < deadline, isCurrent(), environment.isPermitted else { return .unavailable }
        guard let revision = environment.setClipboard(text) else { return .unavailable }
        guard let current = await environment.focusedTarget(deadline: deadline), current == target,
              environment.clipboardRevision == revision, now() < deadline,
              isCurrent(), environment.isPermitted else { return .unconfirmed }
        guard environment.postPaste() else { return .unconfirmed }
        // Readback never sends a second paste, even when acknowledgement is slow.
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: readbackDelay)
            guard now() < deadline, isCurrent(),
                  let result = await environment.focusedTarget(deadline: deadline),
                  result.id == target.id, result.processID == target.processID else { return .unconfirmed }
            if result.value == expected,
               result.selection == NSRange(location: target.selection.location + text.utf16.count, length: 0) {
                return .confirmed
            }
        }
        return .unconfirmed
    }
}
