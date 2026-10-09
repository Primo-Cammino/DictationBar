import Foundation

enum ShortcutFailure: LocalizedError {
    case registration, escape
    var errorDescription: String? {
        switch self {
        case .registration: "Das Tastenkürzel konnte nicht registriert werden. Bitte ein anderes wählen oder über die App starten."
        case .escape: "Escape konnte nicht registriert werden. Stoppen ist über das Diktier-Tastenkürzel oder die App möglich."
        }
    }
}

@MainActor
protocol GlobalShortcutProviding: AnyObject {
    var onToggle: (() -> Void)? { get set }
    var onEscape: (() -> Void)? { get set }
    func configure(_ shortcut: DictationShortcut) throws
    func register() throws
    func setCaptureActive(_ active: Bool) throws
    func unregister()
}

extension GlobalShortcutProviding {
    func configure(_ shortcut: DictationShortcut) throws {}
}

@MainActor
final class ShortcutEventRouter {
    var onToggle: (() -> Void)?
    var onEscape: (() -> Void)?
    var captureActive = false {
        didSet { if !captureActive { pressed.remove(2) } }
    }
    private var pressed: Set<UInt32> = []

    func receive(id: UInt32, down: Bool) {
        guard down else { pressed.remove(id); return }
        guard pressed.insert(id).inserted else { return }
        if id == 1 { onToggle?() }
        else if id == 2, captureActive { onEscape?() }
    }

    func reset() { pressed = []; captureActive = false }
}
