import Carbon
import Foundation

@MainActor
final class NativeGlobalShortcutService: GlobalShortcutProviding {
    private let router = ShortcutEventRouter()
    private var handler: EventHandlerRef?
    private var toggle: EventHotKeyRef?
    private var escape: EventHotKeyRef?
    private var shortcut = DictationShortcut.default

    var onToggle: (() -> Void)? {
        get { router.onToggle }
        set { router.onToggle = newValue }
    }
    var onEscape: (() -> Void)? {
        get { router.onEscape }
        set { router.onEscape = newValue }
    }

    func configure(_ shortcut: DictationShortcut) throws {
        guard self.shortcut != shortcut else { return }
        guard let current = toggle else {
            self.shortcut = shortcut
            return
        }
        var replacement: EventHotKeyRef?
        let hotKey = EventHotKeyID(signature: 0x44426172, id: 1)
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKey,
                                  GetApplicationEventTarget(), 0, &replacement) == noErr,
              let replacement else { throw ShortcutFailure.registration }
        UnregisterEventHotKey(current)
        toggle = replacement
        self.shortcut = shortcut
        // The old key's release will no longer arrive after unregistering it.
        router.receive(id: 1, down: false)
    }

    func register() throws {
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
        guard status == noErr else { throw ShortcutFailure.registration }
        let hotKey = EventHotKeyID(signature: 0x44426172, id: 1)
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKey,
                                  GetApplicationEventTarget(), 0, &toggle) == noErr else {
            unregister()
            throw ShortcutFailure.registration
        }
    }

    func setCaptureActive(_ active: Bool) throws {
        router.captureActive = active
        if !active {
            if let escape { UnregisterEventHotKey(escape) }
            escape = nil
        } else if escape == nil {
            let hotKey = EventHotKeyID(signature: 0x44426172, id: 2)
            guard RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKey,
                                     GetApplicationEventTarget(), 0, &escape) == noErr else {
                throw ShortcutFailure.escape
            }
        }
    }

    func unregister() {
        if let escape { UnregisterEventHotKey(escape) }
        if let toggle { UnregisterEventHotKey(toggle) }
        if let handler { RemoveEventHandler(handler) }
        escape = nil; toggle = nil; handler = nil
        router.reset()
    }
}
