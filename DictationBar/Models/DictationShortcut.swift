import AppKit
import Carbon

struct DictationShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = DictationShortcut(validatedKeyCode: UInt32(kVK_Space),
                                             modifiers: UInt32(controlKey | optionKey))
    static let meetingDefault = DictationShortcut(validatedKeyCode: UInt32(kVK_ANSI_M),
                                                  modifiers: UInt32(controlKey | optionKey))

    init?(keyCode: UInt32, modifiers: UInt32) {
        let supported = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let required = UInt32(cmdKey | controlKey | optionKey)
        guard Self.keyNames[keyCode] != nil,
              modifiers & required != 0,
              modifiers & ~supported == 0 else { return nil }
        self.init(validatedKeyCode: keyCode, modifiers: modifiers)
    }

    private init(validatedKeyCode: UInt32, modifiers: UInt32) {
        keyCode = validatedKeyCode
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try values.decode(UInt32.self, forKey: .keyCode)
        let modifiers = try values.decode(UInt32.self, forKey: .modifiers)
        guard let shortcut = Self(keyCode: keyCode, modifiers: modifiers) else {
            throw DecodingError.dataCorruptedError(forKey: .modifiers, in: values,
                                                  debugDescription: "Ungültiges Diktier-Tastenkürzel")
        }
        self = shortcut
    }

    static func capture(_ event: NSEvent) -> Self? {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return Self(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var displayName: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + (Self.layoutCharacter(for: keyCode) ?? Self.keyNames[keyCode] ?? "Taste \(keyCode)")
    }

    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        // TIS is a UI service. Non-UI callers can still use the deterministic
        // fallback names; the Settings view uses the active keyboard layout.
        guard Thread.isMainThread, keyCode < 51, ![36, 48, 49].contains(keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var count = 0
        var characters = [UniChar](repeating: 0, count: 4)
        guard UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                             UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                             &deadKey, characters.count, &count, &characters) == noErr,
              count > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: Int(count)).uppercased()
    }

    // Carbon stores hardware key codes, including non-character keys.
    // Modifier keys themselves are deliberately absent: a chord needs a key.
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Leertaste",
        50: "`", 51: "⌫", 53: "Esc", 64: "F17", 65: "Ziffernblock .", 67: "Ziffernblock *",
        69: "Ziffernblock +", 71: "Ziffernblock Löschen", 75: "Ziffernblock /",
        76: "Ziffernblock ↩", 78: "Ziffernblock −", 79: "F18", 80: "F19", 81: "Ziffernblock =",
        82: "Ziffernblock 0", 83: "Ziffernblock 1", 84: "Ziffernblock 2", 85: "Ziffernblock 3",
        86: "Ziffernblock 4", 87: "Ziffernblock 5", 88: "Ziffernblock 6", 89: "Ziffernblock 7",
        91: "Ziffernblock 8", 92: "Ziffernblock 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "Hilfe", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
