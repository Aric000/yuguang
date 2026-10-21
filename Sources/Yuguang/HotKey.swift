import AppKit
import Carbon
import SwiftUI

struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String
    static let standard = HotKeySpec(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey), keyLabel: "`")
    static var saved: HotKeySpec {
        guard let data = UserDefaults.standard.data(forKey: "hotKey"), let spec = try? JSONDecoder().decode(Self.self, from: data) else { return .standard }
        return spec
    }
    var label: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃ " : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥ " : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧ " : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘ " : "") + keyLabel
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "hotKey") } }
}

@MainActor final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: HotKeySpec?
    var onPress: (() -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKeyManager>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { owner.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ spec: HotKeySpec) -> Bool {
        if current == spec { return true }
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, EventHotKeyID(signature: 0x59554755, id: 1), GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate; current = spec
        return true
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; current = nil
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var apply: (HotKeySpec) -> Void
    var cancel: () -> Void
    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(); view.apply = apply; view.cancel = cancel
        return view
    }
    func updateNSView(_ view: RecorderView, context: Context) { view.apply = apply; view.cancel = cancel }
}

final class RecorderView: NSView {
    var apply: ((HotKeySpec) -> Void)?
    var cancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let label = event.keyCode == UInt16(kVK_ANSI_Grave) ? "`" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        apply?(HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label))
    }
}
