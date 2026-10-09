import AppKit
import ApplicationServices
import Foundation
import os

/// Fixed reason strings only: never field values, window titles, app names or transcripts.
private let insertionLog = Logger(subsystem: "com.primocammino.DictationBar", category: "insertion")

@MainActor
final class NativeTextInsertionEnvironment: TextInsertionEnvironment {
    private let reader = AXTargetReader()
    private var latestTarget: FocusedTextTarget?
    var ownProcessID: Int32 { ProcessInfo.processInfo.processIdentifier }
    var clipboardRevision: Int { NSPasteboard.general.changeCount }
    var isPermitted: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }
    var permissionSummary: String {
        "Bedienungshilfen: \(AXIsProcessTrusted() ? "erlaubt" : "fehlen") · Tastaturereignisse: \(CGPreflightPostEventAccess() ? "erlaubt" : "fehlen")"
    }

    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        _ = CGRequestPostEventAccess()
    }

    func focusedTarget(deadline: TimeInterval) async -> FocusedTextTarget? {
        latestTarget = await reader.read(deadline: deadline)
        return latestTarget
    }

    func setClipboard(_ text: String) -> Int? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            insertionLog.notice("Zwischenablage konnte nicht geschrieben werden")
            return nil
        }
        return pasteboard.changeCount
    }

    func postPaste() -> Bool {
        guard isPermitted, let latestTarget,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == latestTarget.processID else {
            insertionLog.notice("Einfügen abgebrochen: Zielapp nicht mehr vorne oder Freigabe fehlt")
            return false
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// Transient AX values are used for readback only, never persisted or logged.
final class AXTargetReader: @unchecked Sendable {
    private let focusedElement: (AXUIElement) -> CFTypeRef?
    private let readAttribute: ((AXUIElement, String) -> CFTypeRef?)?
    private let valueSettable: (AXUIElement) -> Bool

    init(focusedElement: @escaping (AXUIElement) -> CFTypeRef? = { system in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success else { return nil }
        return value
    }, readAttribute: ((AXUIElement, String) -> CFTypeRef?)? = nil,
       valueSettable: @escaping (AXUIElement) -> Bool = { element in
           var result = DarwinBoolean(false)
           return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &result) == .success && result.boolValue
       }) {
        self.focusedElement = focusedElement
        self.readAttribute = readAttribute
        self.valueSettable = valueSettable
    }
    private let queue = DispatchQueue(label: "DictationBar.accessibility")
    private var lastElement: AXUIElement?
    private var lastID = UUID()

    func read(deadline: TimeInterval) async -> FocusedTextTarget? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: snapshot(deadline: deadline)) }
        }
    }

    private func snapshot(deadline: TimeInterval) -> FocusedTextTarget? {
        func expired() -> Bool { ProcessInfo.processInfo.systemUptime >= deadline }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard !expired() else { return nil }
            _ = AXUIElementSetMessagingTimeout(element, 0.25)
            if let readAttribute { return readAttribute(element, name) }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func reject(_ reason: String) -> FocusedTextTarget? {
            insertionLog.notice("Einfügeziel abgelehnt: \(reason, privacy: .public)")
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.25)
        guard !expired(), let focused = focusedElement(system),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return reject("kein fokussiertes Element") }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(element, 0.25)
        var pid: pid_t = 0
        guard !expired(), AXUIElementGetPid(element, &pid) == .success else { return reject("PID nicht lesbar") }
        guard pid != getpid() else { return reject("Fokus liegt in DictationBar") }
        let role = attribute(element, kAXRoleAttribute) as? String
        guard let role, [kAXTextFieldRole, kAXTextAreaRole].contains(role) else {
            return reject("Rolle \(role ?? "unbekannt")")
        }
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        guard subrole != kAXSecureTextFieldSubrole else { return reject("Passwortfeld") }
        // Text views such as TextEdit's omit AXEnabled; only an explicit false means disabled.
        let enabled = attribute(element, kAXEnabledAttribute) as? Bool
        if enabled == nil { insertionLog.notice("AXEnabled fehlt, Feld gilt als aktiv") }
        guard enabled != false, !expired() else { return reject("Feld deaktiviert") }
        guard valueSettable(element) else { return reject("AXValue nicht setzbar") }
        guard let value = attribute(element, kAXValueAttribute) as? String else { return reject("AXValue nicht lesbar") }
        guard let selected = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(selected) == AXValueGetTypeID(), !expired() else { return reject("Auswahl nicht lesbar") }
        let selectedValue = unsafeBitCast(selected, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(selectedValue, .cfRange, &range), !expired() else { return reject("Auswahl ungültig") }
        // Attribute reads can span several IPC calls. Reject a snapshot whose
        // element lost focus while those attributes were being collected.
        guard let current = focusedElement(system),
              CFGetTypeID(current) == AXUIElementGetTypeID(),
              CFEqual(current, element), !expired() else { return reject("Fokus während der Prüfung gewechselt") }
        if let lastElement, !CFEqual(lastElement, element) { lastID = UUID() }
        self.lastElement = element
        return FocusedTextTarget(id: lastID, processID: pid, role: role, secure: false,
                                 enabled: true, writable: true, value: value,
                                 selection: NSRange(location: range.location, length: range.length))
    }
}
