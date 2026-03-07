import Cocoa
import Carbon.HIToolbox

final class SettingsPanel: NSPanel {
    private let apiKeyField = NSTextField()
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let levelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hotkeyButton = NSButton()
    private let doubleTapCheckbox = NSButton(checkboxWithTitle: "Double-tap", target: nil, action: nil)

    private var isRecordingHotkey = false
    private var recordedKeyCode: UInt32 = UInt32(kVK_F5)
    private var recordedModifiers: UInt32 = 0
    private var recordedKeyName: String = "F5"
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    var onSave: ((Config) -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    private let modelOptions: [(name: String, id: String)] = [
        ("Sonnet 4.6", "claude-sonnet-4-6"),
        ("Haiku 4.5", "claude-haiku-4-5-20251001"),
        ("Opus 4.6", "claude-opus-4-6"),
    ]

    private let levelOptions = [
        "1 — The Gist",
        "2 — Essentials",
        "3 — Mechanism",
        "4 — Nuance",
        "5 — Frontier",
    ]

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "Instant Explain — Settings"
        self.level = .floating
        self.appearance = NSAppearance(named: .darkAqua)
        setupUI()
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 330))
        container.wantsLayer = true
        self.contentView = container

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        var y: CGFloat = 280
        let labelX: CGFloat = 20
        let fieldX: CGFloat = 150
        let fieldW: CGFloat = 260
        let rowH: CGFloat = 24
        let gap: CGFloat = 38

        // API Key
        addLabel("API Key:", font: labelFont, x: labelX, y: y, to: container)

        apiKeyField.font = font
        apiKeyField.placeholderString = "sk-ant-..."
        apiKeyField.frame = NSRect(x: fieldX, y: y, width: fieldW, height: rowH)
        apiKeyField.lineBreakMode = .byTruncatingTail
        container.addSubview(apiKeyField)

        y -= gap

        // Model
        addLabel("Model:", font: labelFont, x: labelX, y: y, to: container)

        modelPopup.font = font
        for opt in modelOptions { modelPopup.addItem(withTitle: opt.name) }
        modelPopup.frame = NSRect(x: fieldX, y: y - 2, width: fieldW, height: rowH + 2)
        container.addSubview(modelPopup)

        y -= gap

        // Default Level
        addLabel("Default Level:", font: labelFont, x: labelX, y: y, to: container)

        levelPopup.font = font
        for opt in levelOptions { levelPopup.addItem(withTitle: opt) }
        levelPopup.frame = NSRect(x: fieldX, y: y - 2, width: fieldW, height: rowH + 2)
        container.addSubview(levelPopup)

        y -= gap

        // Hotkey
        addLabel("Hotkey:", font: labelFont, x: labelX, y: y, to: container)

        hotkeyButton.title = "F5"
        hotkeyButton.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.frame = NSRect(x: fieldX, y: y - 2, width: 100, height: rowH + 4)
        hotkeyButton.target = self
        hotkeyButton.action = #selector(startRecordingHotkey)
        container.addSubview(hotkeyButton)

        doubleTapCheckbox.font = font
        doubleTapCheckbox.frame = NSRect(x: fieldX + 110, y: y, width: 140, height: rowH)
        doubleTapCheckbox.state = .off
        container.addSubview(doubleTapCheckbox)

        y -= 16
        let hint = NSTextField(labelWithString: "click button, then press desired key")
        hint.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 14)
        container.addSubview(hint)

        // Buttons
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.font = labelFont
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 340, y: 16, width: 80, height: 32)
        saveBtn.keyEquivalent = "\r"
        container.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancelBtn.font = labelFont
        cancelBtn.bezelStyle = .rounded
        cancelBtn.frame = NSRect(x: 250, y: 16, width: 80, height: 32)
        cancelBtn.keyEquivalent = "\u{1b}"
        container.addSubview(cancelBtn)
    }

    private func addLabel(_ text: String, font: NSFont, x: CGFloat, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.frame = NSRect(x: x, y: y, width: 120, height: 20)
        view.addSubview(label)
    }

    func loadConfig(_ config: Config) {
        apiKeyField.stringValue = config.apiKey
        if let idx = modelOptions.firstIndex(where: { $0.id == config.model }) {
            modelPopup.selectItem(at: idx)
        }
        levelPopup.selectItem(at: max(0, min(4, config.defaultLevel - 1)))
        recordedKeyCode = UInt32(config.hotkeyKeyCode)
        recordedModifiers = UInt32(config.hotkeyModifiers)
        recordedKeyName = config.hotkey
        hotkeyButton.title = recordedKeyName
        doubleTapCheckbox.state = config.hotkeyDoubleTap ? .on : .off
    }

    func showCentered() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Hotkey recording

    @objc private func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        isRecordingHotkey = true
        hotkeyButton.title = "Press key..."
        onStartRecording?()  // This calls hotkeyListener.pause() to unregister Carbon hotkey

        // Local monitor for when our window is focused
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureHotkey(event)
            return nil
        }
        // Global monitor as backup (catches keys even if focus is elsewhere)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureHotkey(event)
        }
    }

    private func captureHotkey(_ event: NSEvent) {
        guard isRecordingHotkey else { return }  // Prevent double-fire from local + global
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        isRecordingHotkey = false
        onStopRecording?()  // This calls hotkeyListener.resume() to re-register Carbon hotkey

        recordedKeyCode = UInt32(event.keyCode)
        recordedModifiers = Self.carbonModifiers(from: event.modifierFlags)
        recordedKeyName = Self.keyDisplayName(keyCode: event.keyCode, modifiers: event.modifierFlags)
        hotkeyButton.title = recordedKeyName
    }

    // MARK: - Save / Cancel

    @objc private func saveSettings() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = modelOptions[modelPopup.indexOfSelectedItem].id
        let level = levelPopup.indexOfSelectedItem + 1
        let doubleTap = doubleTapCheckbox.state == .on

        let config = Config(
            apiKey: apiKey,
            hotkey: recordedKeyName,
            defaultLevel: level,
            model: modelId,
            maxTokens: 4096,
            hotkeyKeyCode: Int(recordedKeyCode),
            hotkeyModifiers: Int(recordedModifiers),
            hotkeyDoubleTap: doubleTap
        )
        onSave?(config)
        orderOut(nil)
    }

    @objc private func cancelSettings() {
        if isRecordingHotkey {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = globalKeyMonitor {
                NSEvent.removeMonitor(monitor)
                globalKeyMonitor = nil
            }
            isRecordingHotkey = false
            onStopRecording?()
        }
        orderOut(nil)
    }

    // MARK: - Key utilities

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    static func keyDisplayName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_F1: keyName = "F1"
        case kVK_F2: keyName = "F2"
        case kVK_F3: keyName = "F3"
        case kVK_F4: keyName = "F4"
        case kVK_F5: keyName = "F5"
        case kVK_F6: keyName = "F6"
        case kVK_F7: keyName = "F7"
        case kVK_F8: keyName = "F8"
        case kVK_F9: keyName = "F9"
        case kVK_F10: keyName = "F10"
        case kVK_F11: keyName = "F11"
        case kVK_F12: keyName = "F12"
        case kVK_F13: keyName = "F13"
        case kVK_F14: keyName = "F14"
        case kVK_F15: keyName = "F15"
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "Return"
        case kVK_Tab: keyName = "Tab"
        case kVK_Escape: keyName = "Esc"
        case kVK_Delete: keyName = "Delete"
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        case kVK_ANSI_0: keyName = "0"
        case kVK_ANSI_1: keyName = "1"
        case kVK_ANSI_2: keyName = "2"
        case kVK_ANSI_3: keyName = "3"
        case kVK_ANSI_4: keyName = "4"
        case kVK_ANSI_5: keyName = "5"
        case kVK_ANSI_6: keyName = "6"
        case kVK_ANSI_7: keyName = "7"
        case kVK_ANSI_8: keyName = "8"
        case kVK_ANSI_9: keyName = "9"
        default: keyName = "Key\(keyCode)"
        }

        parts.append(keyName)
        return parts.joined()
    }
}
