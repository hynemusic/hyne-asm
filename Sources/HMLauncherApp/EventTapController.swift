import AppKit
import HMLauncherCore

/// Global session event tap: double-right-click → panel, keys → panel while open, close-window shortcuts.
/// Active only while Ableton Live is frontmost. Handlers return true to swallow the event.
@MainActor
final class EventTapController {
    var onDoubleRightClick: ((CGPoint) -> Void)?
    /// A plain or ⇧ left click in Live (screen coordinates, origin top left, and whether ⇧ is held);
    /// true swallows it, with its drags and mouse-up.
    var onClick: ((CGPoint, Bool) -> Bool)?
    var isPanelVisible: (() -> Bool)?
    var isPointInPanel: ((CGPoint) -> Bool)?
    var panelKeyHandler: ((PanelKey) -> Bool)?
    var panelBindings: (() -> PanelKeyBindings)?
    var shortcutHandler: ((UInt16, ModifierSet) -> Bool)?

    private let monitor: LiveAppMonitor
    private var detector = DoubleRightClickDetector(interval: NSEvent.doubleClickInterval)
    private var swallowNextRightUp = false
    private var swallowingLeftClick = false
    private var tap: CFMachPort?

    init(monitor: LiveAppMonitor) { self.monitor = monitor }

    /// Fails while the Accessibility permission is missing.
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            swallowingLeftClick = leftMouseDown(event)
            return swallowingLeftClick
        case .leftMouseDragged:
            return swallowingLeftClick
        case .leftMouseUp:
            defer { swallowingLeftClick = false }
            return swallowingLeftClick
        case .rightMouseDown:
            return rightMouseDown(event)
        case .rightMouseUp:
            if swallowNextRightUp { swallowNextRightUp = false; return true }
            return false
        case .keyDown:
            return keyDown(event)
        default:
            return false
        }
    }

    /// ⌥, ⌘ and ⌃ clicks always reach Live untouched, so its own controls stay usable.
    private func leftMouseDown(_ event: CGEvent) -> Bool {
        let mods = Self.modifiers(event.flags)
        guard mods.isEmpty || mods == [.shift], monitor.isLiveFrontmost,
              !(isPointInPanel?(NSEvent.mouseLocation) ?? false) else { return false }
        return onClick?(event.location, mods == [.shift]) ?? false
    }

    private func rightMouseDown(_ event: CGEvent) -> Bool {
        guard monitor.isLiveFrontmost, !(isPointInPanel?(NSEvent.mouseLocation) ?? false) else { return false }
        let time = Double(event.timestamp) / 1_000_000_000
        guard detector.rightMouseDown(at: time) == .openPanel else { return false }
        swallowNextRightUp = true
        closeLiveContextMenu()
        onDoubleRightClick?(NSEvent.mouseLocation)
        return true
    }

    /// The first right-click already opened Live's context menu; Escape closes it.
    private func closeLiveContextMenu() {
        guard let pid = monitor.livePID else { return }
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(pid)
        }
    }

    private func keyDown(_ event: CGEvent) -> Bool {
        let mods = Self.modifiers(event.flags)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if isPanelVisible?() == true {
            if let key = panelBindings?().key(for: KeyCombo(keyCode: keyCode, modifiers: mods)) {
                return panelKeyHandler?(key) ?? false
            }
            if let key = Self.editKey(keyCode, mods, event) {
                return panelKeyHandler?(key) ?? false
            }
            if mods.isDisjoint(with: [.cmd, .ctrl]), let key = Self.textKey(keyCode, event) {
                return panelKeyHandler?(key) ?? false
            }
        }
        guard monitor.isLiveFrontmost else { return false }
        return shortcutHandler?(keyCode, mods) ?? false
    }

    static func modifiers(_ flags: CGEventFlags) -> ModifierSet {
        var m: ModifierSet = []
        if flags.contains(.maskCommand) { m.insert(.cmd) }
        if flags.contains(.maskAlternate) { m.insert(.alt) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskControl) { m.insert(.ctrl) }
        return m
    }

    /// macOS text-field editing for the filter / quick search: ⌘A select all, ⌥⌫ delete word, ⌘⌫ delete to start.
    /// (Without this, ⌘A would reach Live and select everything in the set.)
    static func editKey(_ keyCode: UInt16, _ mods: ModifierSet, _ event: CGEvent) -> PanelKey? {
        if keyCode == 51 {
            if mods.contains(.cmd) { return .deleteToStart }
            if mods.contains(.alt) { return .deleteWord }
            return nil
        }
        if mods == [.cmd], NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() == "a" { return .selectAll }
        return nil
    }

    /// Fixed panel keys: ⌫ edits the filter, digits pick rows, everything printable filters.
    /// Navigation keys come from the rebindable PanelKeyBindings.
    static func textKey(_ keyCode: UInt16, _ event: CGEvent) -> PanelKey? {
        switch keyCode {
        case 51: return .backspace
        case 36, 76, 48, 53, 123, 124, 125, 126: return nil // unbound navigation keys do nothing
        default:
            guard let ch = NSEvent(cgEvent: event)?.characters?.first,
                  !ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            if let d = ch.wholeNumberValue, ch.isASCII { return .digit(d) }
            // ⇧ + a digit key (pinned mode) types "!" etc.; it still picks the row.
            if event.flags.contains(.maskShift), let d = DigitKeys.digit(forKeyCode: keyCode) { return .digit(d) }
            return .character(ch)
        }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    let swallow = MainActor.assumeIsolated { controller.handle(type, event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
