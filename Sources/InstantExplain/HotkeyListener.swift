import Cocoa
import Carbon.HIToolbox

final class HotkeyListener {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onHotkey: (() -> Void)?
    var isEnabled = true

    // Double-tap support
    private var doubleTapMode = false
    private var lastPressTime: TimeInterval = 0
    private let doubleTapInterval: TimeInterval = 0.4

    // Stored for pause/resume
    private var currentKeyCode: UInt32 = UInt32(kVK_F5)
    private var currentModifiers: UInt32 = 0

    // nonisolated(unsafe) — accessed from Carbon event handler on main run loop (M2)
    private nonisolated(unsafe) static var instance: HotkeyListener?

    func start(keyCode: UInt32 = UInt32(kVK_F5), modifiers: UInt32 = 0, doubleTap: Bool = false) {
        HotkeyListener.instance = self
        self.doubleTapMode = doubleTap
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers
        installHandler()
        registerHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32, doubleTap: Bool) {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        self.doubleTapMode = doubleTap
        self.lastPressTime = 0
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers
        registerHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Temporarily unregister the Carbon hotkey so keyDown events flow normally (for hotkey recording)
    func pause() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        isEnabled = false
    }

    /// Re-register the Carbon hotkey after recording
    func resume() {
        isEnabled = true
        registerHotkey(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                HotkeyListener.instance?.handlePress()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        let hotkeyID = EventHotKeyID(signature: OSType(0x4945_5850), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotkeyRef = ref }
    }

    private func handlePress() {
        guard isEnabled else { return }

        if doubleTapMode {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPressTime < doubleTapInterval && lastPressTime > 0 {
                lastPressTime = 0
                onHotkey?()
            } else {
                lastPressTime = now
            }
        } else {
            onHotkey?()
        }
    }

    func stop() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        HotkeyListener.instance = nil
    }
}
