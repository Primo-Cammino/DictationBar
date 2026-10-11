import Carbon
import Foundation

@MainActor
final class NativeGlobalShortcutService: GlobalShortcutProviding {
    private static let signature: OSType = 0x44426172
    private let router = ShortcutEventRouter()
    private var handler: EventHandlerRef?
    private var toggle: EventHotKeyRef?
    private var meeting: EventHotKeyRef?
    private var escape: EventHotKeyRef?
    private var shortcut = DictationShortcut.default
    private var meetingShortcut = DictationShortcut.meetingDefault

    var onToggle: (() -> Void)? {
        get { router.onToggle }
        set { router.onToggle = newValue }
    }
    var onEscape: (() -> Void)? {
        get { router.onEscape }
        set { router.onEscape = newValue }
    }
    var onMeeting: (() -> Void)? {
        get { router.onMeeting }
        set { router.onMeeting = newValue }
    }

    func configure(_ shortcut: DictationShortcut) throws {
        try replace(&toggle, current: &self.shortcut, with: shortcut, id: 1)
    }

    func configureMeeting(_ shortcut: DictationShortcut) throws {
        try replace(&meeting, current: &meetingShortcut, with: shortcut, id: 3)
    }

    func register() throws {
        try installHandler()
        try registerHotKey(&toggle, shortcut, id: 1)
    }

    func registerMeeting() throws {
        try installHandler()
        try registerHotKey(&meeting, meetingShortcut, id: 3)
    }

    /// A registered key is swapped by registering the new one before removing the old,
    /// so a failure keeps the previous shortcut working.
    private func replace(_ ref: inout EventHotKeyRef?, current: inout DictationShortcut,
                         with shortcut: DictationShortcut, id: UInt32) throws {
        guard current != shortcut else { return }
        guard let old = ref else { current = shortcut; return }
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                  GetApplicationEventTarget(), 0, &replacement) == noErr,
              let replacement else { throw ShortcutFailure.registration }
        UnregisterEventHotKey(old)
        ref = replacement
        current = shortcut
        // The old key's release will no longer arrive after unregistering it.
        router.receive(id: id, down: false)
    }

    /// Each key registers on its own; a key another app holds leaves only that key unregistered.
    private func registerHotKey(_ ref: inout EventHotKeyRef?, _ shortcut: DictationShortcut, id: UInt32) throws {
        guard ref == nil else { return }
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                  GetApplicationEventTarget(), 0, &ref) == noErr else {
            ref = nil
            throw ShortcutFailure.registration
        }
    }

    private func installHandler() throws {
        guard handler == nil else { return }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                let service = Unmanaged<NativeGlobalShortcutService>.fromOpaque(context).takeUnretainedValue()
                service.router.receive(id: key.id, down: down)
            }
            return noErr
        }, events.count, &events, context, &handler)
        guard status == noErr else { handler = nil; throw ShortcutFailure.registration }
    }

    func setCaptureActive(_ active: Bool) throws {
        router.captureActive = active
        if !active {
            if let escape { UnregisterEventHotKey(escape) }
            escape = nil
        } else if escape == nil {
            let hotKey = EventHotKeyID(signature: Self.signature, id: 2)
            guard RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKey,
                                     GetApplicationEventTarget(), 0, &escape) == noErr else {
                throw ShortcutFailure.escape
            }
        }
    }

    func unregister() {
        for ref in [escape, toggle, meeting] { if let ref { UnregisterEventHotKey(ref) } }
        if let handler { RemoveEventHandler(handler) }
        escape = nil; toggle = nil; meeting = nil; handler = nil
        router.reset()
    }
}
