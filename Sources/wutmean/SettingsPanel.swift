import Cocoa
import Carbon.HIToolbox

final class SettingsPanel: NSPanel {
    // Per-provider key fields (secure + plain pairs)
    private struct KeyRow {
        let provider: APIProvider
        let label: NSTextField
        let secureField: NSSecureTextField
        let plainField: NSTextField
        let eyeButton: NSButton
        var isVisible = false
    }
    private var keyRows: [KeyRow] = []

    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontSizeSlider = NSSlider()
    private let fontSizeLabel = NSTextField(labelWithString: "12")
    private let levelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hotkeyButton = NSButton()
    private let doubleTapCheckbox = NSButton(checkboxWithTitle: "Double-tap", target: nil, action: nil)
    private var containerView: NSView!
    private var settingsLabels: [NSTextField] = []
    private var sectionHeaders: [NSTextField] = []
    private var dividers: [NSView] = []
    private var modelLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!

    private var isRecordingHotkey = false
    private var recordedKeyCode: UInt32 = UInt32(kVK_F1)
    private var recordedModifiers: UInt32 = 0
    private var recordedKeyName: String = "F1"
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    private let modelFetcher = ModelFetcher()

    var onSave: ((Config) -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onModelsUpdated: (([APIProvider: [String]]) -> Void)?
    var onFontPreviewChanged: (() -> Void)?

    private let levelOptions = [
        "1 — Plain",
        "2 — Technical",
        "3 — Examples",
    ]

    private let languageOptions = [
        ("English", "English"),
        ("中文", "中文"),
    ]

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var availableFonts: [FontFamily] = FontFamily.available

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "wutmean — Settings"
        self.level = .floating
        setupUI()
    }

    private func setupUI() {
        let panelH: CGFloat = 560
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: panelH))
        container.wantsLayer = true
        self.contentView = container
        self.containerView = container

        let font = Theme.fixedFont(size: 12, weight: .regular)
        let labelFont = Theme.fixedFont(size: 12, weight: .medium)

        // `y` = baseline of next element (Cocoa: y=0 at bottom)
        var y: CGFloat = panelH - 34
        let lx: CGFloat = 20      // label x
        let fx: CGFloat = 150     // field x
        let fw: CGFloat = 260     // field width
        let rh: CGFloat = 24      // row height
        let rowGap: CGFloat = 30  // between standard rows
        let keyGap: CGFloat = 28  // between API key rows (tighter)

        // ── PROVIDER section ──
        addSectionHeader("PROVIDER", x: lx, y: y, to: container)
        y -= 24

        // API Key rows
        let providers: [APIProvider] = [.anthropic, .openai, .google]
        for (i, provider) in providers.enumerated() {
            let rowY = y - CGFloat(i) * keyGap

            let provLabel = NSTextField(labelWithString: provider.displayName + ":")
            provLabel.font = labelFont
            provLabel.frame = NSRect(x: lx, y: rowY, width: 120, height: 20)
            container.addSubview(provLabel)
            settingsLabels.append(provLabel)

            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.font = Theme.fixedFont(size: 9, weight: .medium)
            statusLabel.alignment = .right
            statusLabel.frame = NSRect(x: fx + fw - 24, y: rowY + rh + 2, width: 24, height: 12)
            statusLabel.isHidden = true
            container.addSubview(statusLabel)

            let secure = NSSecureTextField()
            secure.font = font
            secure.placeholderString = provider.placeholder
            secure.frame = NSRect(x: fx, y: rowY, width: fw - 28, height: rh)
            secure.focusRingType = .none
            container.addSubview(secure)

            let plain = NSTextField()
            plain.font = font
            plain.placeholderString = provider.placeholder
            plain.frame = secure.frame
            plain.focusRingType = .none
            plain.isHidden = true
            container.addSubview(plain)

            let eye = NSButton()
            eye.bezelStyle = .inline
            eye.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show key")
            eye.title = ""
            eye.imagePosition = .imageOnly
            eye.isBordered = false
            eye.frame = NSRect(x: fx + fw - 24, y: rowY + 2, width: 20, height: 20)
            eye.tag = i
            eye.target = self
            eye.action = #selector(toggleRowVisibility(_:))
            eye.setAccessibilityLabel("Show/hide \(provider.displayName) key")
            container.addSubview(eye)

            keyRows.append(KeyRow(
                provider: provider,
                label: statusLabel,
                secureField: secure,
                plainField: plain,
                eyeButton: eye,
                isVisible: false
            ))
        }

        y -= CGFloat(providers.count) * keyGap + 4

        // Model
        let mLabel = addLabel("Model:", font: labelFont, x: lx, y: y, to: container)
        self.modelLabel = mLabel
        modelPopup.font = font
        modelPopup.frame = NSRect(x: fx, y: y - 2, width: fw, height: rh + 2)
        container.addSubview(modelPopup)

        y -= 16
        addDivider(y: y, to: container)
        y -= 20

        // ── DISPLAY section ──
        addSectionHeader("DISPLAY", x: lx, y: y, to: container)
        y -= 24

        // Font
        addLabel("Font:", font: labelFont, x: lx, y: y, to: container)
        fontPopup.font = font
        for ff in availableFonts {
            let item = NSMenuItem(title: ff.displayName, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: ff.displayName,
                attributes: [.font: ff.font(size: 12, weight: .regular)]
            )
            fontPopup.menu?.addItem(item)
        }
        fontPopup.frame = NSRect(x: fx, y: y - 2, width: fw, height: rh + 2)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        container.addSubview(fontPopup)

        y -= rowGap

        // Font Size
        addLabel("Size:", font: labelFont, x: lx, y: y, to: container)
        fontSizeSlider.minValue = 10
        fontSizeSlider.maxValue = 18
        fontSizeSlider.doubleValue = 12
        fontSizeSlider.numberOfTickMarks = 9
        fontSizeSlider.allowsTickMarkValuesOnly = true
        fontSizeSlider.isContinuous = true
        fontSizeSlider.frame = NSRect(x: fx, y: y - 2, width: fw - 40, height: rh)
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged)
        container.addSubview(fontSizeSlider)

        fontSizeLabel.font = Theme.fixedFont(size: 12, weight: .medium)
        fontSizeLabel.alignment = .right
        fontSizeLabel.frame = NSRect(x: fx + fw - 36, y: y, width: 36, height: 20)
        container.addSubview(fontSizeLabel)
        settingsLabels.append(fontSizeLabel)

        y -= rowGap

        // Default Level
        addLabel("Default Level:", font: labelFont, x: lx, y: y, to: container)
        levelPopup.font = font
        for opt in levelOptions { levelPopup.addItem(withTitle: opt) }
        levelPopup.frame = NSRect(x: fx, y: y - 2, width: fw, height: rh + 2)
        container.addSubview(levelPopup)

        y -= rowGap

        // Language + Theme on one row
        addLabel("Language:", font: labelFont, x: lx, y: y, to: container)
        languagePopup.font = font
        for opt in languageOptions { languagePopup.addItem(withTitle: opt.0) }
        languagePopup.frame = NSRect(x: fx, y: y - 2, width: 110, height: rh + 2)
        container.addSubview(languagePopup)

        let themeLabel = addLabel("Theme:", font: labelFont, x: fx + 120, y: y, to: container)
        themeLabel.frame = NSRect(x: fx + 118, y: y, width: 56, height: 20)
        themePopup.font = font
        themePopup.addItem(withTitle: "Dark")
        themePopup.addItem(withTitle: "Light")
        themePopup.frame = NSRect(x: fx + 176, y: y - 2, width: 84, height: rh + 2)
        container.addSubview(themePopup)

        y -= 16
        addDivider(y: y, to: container)
        y -= 20

        // ── CONTROLS section ──
        addSectionHeader("CONTROLS", x: lx, y: y, to: container)
        y -= 24

        // Hotkey
        addLabel("Hotkey:", font: labelFont, x: lx, y: y, to: container)
        hotkeyButton.title = "F5"
        hotkeyButton.font = Theme.fixedFont(size: 12, weight: .medium)
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.frame = NSRect(x: fx, y: y - 2, width: 100, height: rh + 4)
        hotkeyButton.target = self
        hotkeyButton.action = #selector(startRecordingHotkey)
        container.addSubview(hotkeyButton)

        doubleTapCheckbox.font = font
        doubleTapCheckbox.frame = NSRect(x: fx + 110, y: y, width: 140, height: rh)
        doubleTapCheckbox.state = .off
        container.addSubview(doubleTapCheckbox)

        y -= 16
        let hint = NSTextField(labelWithString: "click button, then press desired key")
        hint.font = Theme.fixedFont(size: 10, weight: .regular)
        hint.frame = NSRect(x: fx, y: y, width: fw, height: 14)
        container.addSubview(hint)
        self.hintLabel = hint

        // ── Save / Cancel (pinned to bottom) ──
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.font = Theme.fixedFont(size: 12, weight: .bold)
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.cornerRadius = 6
        saveBtn.frame = NSRect(x: 340, y: 14, width: 80, height: 30)
        saveBtn.keyEquivalent = "\r"
        container.addSubview(saveBtn)
        self.saveButton = saveBtn

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancelBtn.font = Theme.fixedFont(size: 12, weight: .medium)
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.frame = NSRect(x: 250, y: 14, width: 80, height: 30)
        cancelBtn.keyEquivalent = "\u{1b}"
        container.addSubview(cancelBtn)
        self.cancelButton = cancelBtn
    }

    @discardableResult
    private func addLabel(_ text: String, font: NSFont, x: CGFloat, y: CGFloat, to view: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.frame = NSRect(x: x, y: y, width: 120, height: 20)
        view.addSubview(label)
        settingsLabels.append(label)
        return label
    }

    private func addSectionHeader(_ text: String, x: CGFloat, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.fixedFont(size: 11, weight: .bold)
        label.frame = NSRect(x: x, y: y, width: 200, height: 16)
        view.addSubview(label)
        sectionHeaders.append(label)
    }

    private func addDivider(y: CGFloat, to view: NSView) {
        let line = NSView(frame: NSRect(x: 20, y: y, width: 400, height: 1))
        line.wantsLayer = true
        view.addSubview(line)
        dividers.append(line)
    }

    // MARK: - Theme

    private func applyTheme() {
        self.appearance = NSAppearance(named: Theme.darkMode ? .darkAqua : .aqua)
        containerView.layer?.backgroundColor = Theme.panelBackground.cgColor

        for label in settingsLabels {
            label.textColor = Theme.textSecondary
        }

        for header in sectionHeaders {
            header.textColor = Theme.textTertiary
        }

        for div in dividers {
            div.layer?.backgroundColor = Theme.separator.cgColor
        }

        // Model label
        modelLabel.textColor = Theme.textSecondary

        for row in keyRows {
            row.secureField.textColor = Theme.textPrimary
            row.secureField.backgroundColor = Theme.fieldBackground
            row.secureField.drawsBackground = true
            row.secureField.isBordered = true
            row.plainField.textColor = Theme.textPrimary
            row.plainField.backgroundColor = Theme.fieldBackground
            row.plainField.drawsBackground = true
            row.plainField.isBordered = true
            row.eyeButton.contentTintColor = Theme.textSecondary
            row.label.textColor = Theme.textTertiary
        }

        hintLabel.textColor = Theme.textTertiary

        saveButton.layer?.backgroundColor = Theme.accent.cgColor
        saveButton.contentTintColor = Theme.headerText

        cancelButton.layer?.backgroundColor = Theme.buttonSecondaryBackground.cgColor
        cancelButton.contentTintColor = Theme.textPrimary
    }

    // MARK: - Font live preview

    @objc private func fontChanged() {
        let idx = fontPopup.indexOfSelectedItem
        guard idx >= 0, idx < availableFonts.count else { return }
        let selected = availableFonts[idx]
        Theme.fontFamily = selected
        applyFonts()
        onFontPreviewChanged?()
    }

    @objc private func fontSizeChanged() {
        let size = CGFloat(Int(fontSizeSlider.doubleValue))
        fontSizeSlider.doubleValue = Double(size)
        fontSizeLabel.stringValue = "\(Int(size))px"
        Theme.fontSize = size
        applyFonts()
        onFontPreviewChanged?()
    }

    /// Re-apply fonts to all controls after font family/size change
    private func applyFonts() {
        let font = Theme.fixedFont(size: 12, weight: .regular)
        let labelFont = Theme.fixedFont(size: 12, weight: .medium)

        for label in settingsLabels {
            label.font = labelFont
        }
        for header in sectionHeaders {
            header.font = Theme.fixedFont(size: 11, weight: .bold)
        }
        for row in keyRows {
            row.secureField.font = font
            row.plainField.font = font
            row.label.font = Theme.fixedFont(size: 9, weight: .medium)
        }
        modelPopup.font = font
        fontPopup.font = font
        fontSizeLabel.font = Theme.fixedFont(size: 12, weight: .medium)
        levelPopup.font = font
        languagePopup.font = font
        themePopup.font = font
        hotkeyButton.font = Theme.fixedFont(size: 12, weight: .medium)
        doubleTapCheckbox.font = font
        hintLabel.font = Theme.fixedFont(size: 10, weight: .regular)
        saveButton.font = Theme.fixedFont(size: 12, weight: .bold)
        cancelButton.font = Theme.fixedFont(size: 12, weight: .medium)
    }

    // MARK: - Key visibility (per-row)

    @objc private func toggleRowVisibility(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < keyRows.count else { return }

        if keyRows[idx].isVisible {
            // Hide: copy plain → secure, show secure
            keyRows[idx].secureField.stringValue = keyRows[idx].plainField.stringValue
            keyRows[idx].plainField.isHidden = true
            keyRows[idx].secureField.isHidden = false
            keyRows[idx].isVisible = false
            keyRows[idx].eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show key")
        } else {
            // Show: copy secure → plain, show plain
            keyRows[idx].plainField.stringValue = keyRows[idx].secureField.stringValue
            keyRows[idx].secureField.isHidden = true
            keyRows[idx].plainField.isHidden = false
            keyRows[idx].isVisible = true
            keyRows[idx].eyeButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide key")
        }
    }

    /// Get the current key value for a row (from whichever field is visible)
    private func keyValue(for idx: Int) -> String {
        keyRows[idx].isVisible
            ? keyRows[idx].plainField.stringValue
            : keyRows[idx].secureField.stringValue
    }

    /// Set the key value for a row
    private func setKeyValue(_ value: String, for idx: Int) {
        keyRows[idx].secureField.stringValue = value
        keyRows[idx].plainField.stringValue = value
    }

    private func updateProviderLabels() {
        // Provider names are now static labels — no dynamic update needed
    }

    // MARK: - Model dropdown

    func updateModelDropdown(models: [APIProvider: [String]], selectedModel: String) {
        modelPopup.removeAllItems()

        let providerOrder: [APIProvider] = [.anthropic, .openai, .google]
        var firstGroup = true

        for provider in providerOrder {
            guard let providerModels = models[provider], !providerModels.isEmpty else { continue }
            if !firstGroup {
                modelPopup.menu?.addItem(NSMenuItem.separator())
            }

            let header = NSMenuItem(title: "── \(provider.displayName) ──", action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(
                string: "── \(provider.displayName) ──",
                attributes: [
                    .font: Theme.fixedFont(size: 10, weight: .bold),
                    .foregroundColor: Theme.textTertiary
                ]
            )
            modelPopup.menu?.addItem(header)

            for model in providerModels {
                modelPopup.addItem(withTitle: model)
            }
            firstGroup = false
        }

        if modelPopup.numberOfItems == 0 {
            modelPopup.addItem(withTitle: "(no models — add API keys)")
            modelPopup.lastItem?.isEnabled = false
        }

        if modelPopup.itemTitles.contains(selectedModel) {
            modelPopup.selectItem(withTitle: selectedModel)
        } else if let firstSelectable = modelPopup.itemArray.first(where: { $0.isEnabled && !$0.isSeparatorItem }) {
            modelPopup.select(firstSelectable)
        }
    }

    // MARK: - Load / Show

    func loadConfig(_ config: Config) {
        // Apply theme first — setting appearance after values clears NSSecureTextField
        applyTheme()

        // Distribute keys into provider-specific fields
        for i in 0..<keyRows.count {
            setKeyValue("", for: i)
        }
        for (provider, key) in config.providerKeys {
            if let idx = keyRows.firstIndex(where: { $0.provider == provider }) {
                setKeyValue(key, for: idx)
            }
        }
        updateProviderLabels()

        // Font family
        let configFont = FontFamily(rawValue: config.fontFamily) ?? .systemMono
        if let fontIdx = availableFonts.firstIndex(of: configFont) {
            fontPopup.selectItem(at: fontIdx)
        }
        Theme.fontFamily = configFont

        // Font size
        let configSize = CGFloat(max(10, min(18, config.fontSize)))
        fontSizeSlider.doubleValue = Double(configSize)
        fontSizeLabel.stringValue = "\(Int(configSize))px"
        Theme.fontSize = configSize

        levelPopup.selectItem(at: max(0, min(2, config.defaultLevel - 1)))
        if let idx = languageOptions.firstIndex(where: { $0.1 == config.outputLanguage }) {
            languagePopup.selectItem(at: idx)
        }
        themePopup.selectItem(at: config.darkMode ? 0 : 1)
        recordedKeyCode = UInt32(config.hotkeyKeyCode)
        recordedModifiers = UInt32(config.hotkeyModifiers)
        recordedKeyName = config.hotkey
        hotkeyButton.title = recordedKeyName
        doubleTapCheckbox.state = config.hotkeyDoubleTap ? .on : .off

        // Load cached models first
        let cached = Config.loadModelsCache()
        var models: [APIProvider: [String]] = [:]
        for (key, value) in cached {
            if let provider = APIProvider(rawValue: key) {
                models[provider] = value
            }
        }
        let providerKeys = config.providerKeys
        let detectedProviders = Set(providerKeys.map { $0.provider })
        models = models.filter { detectedProviders.contains($0.key) }
        updateModelDropdown(models: models, selectedModel: config.model)

        // Fetch fresh models in background
        if !providerKeys.isEmpty {
            let selectedModel = config.model
            Task {
                let fetched = await modelFetcher.fetchAll(keys: providerKeys)
                await MainActor.run {
                    self.updateModelDropdown(models: fetched, selectedModel: selectedModel)
                    self.onModelsUpdated?(fetched)
                }
            }
        }
    }

    func showCentered() {
        // Theme already applied in loadConfig (must happen before setting secure field values)
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
        onStartRecording?()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureHotkey(event)
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureHotkey(event)
        }
    }

    private func captureHotkey(_ event: NSEvent) {
        guard isRecordingHotkey else { return }
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

        recordedKeyCode = UInt32(event.keyCode)
        recordedModifiers = Self.carbonModifiers(from: event.modifierFlags)
        recordedKeyName = Self.keyDisplayName(keyCode: event.keyCode, modifiers: event.modifierFlags)
        hotkeyButton.title = recordedKeyName
    }

    // MARK: - Save / Cancel

    @objc private func saveSettings() {
        // Collect non-empty keys from all rows
        var keys: [String] = []
        for i in 0..<keyRows.count {
            let value = keyValue(for: i).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                keys.append(value)
            }
        }

        let selectedModel = modelPopup.titleOfSelectedItem ?? "claude-sonnet-4-6"
        let level = levelPopup.indexOfSelectedItem + 1
        let language = languageOptions[languagePopup.indexOfSelectedItem].1
        let isDarkMode = themePopup.indexOfSelectedItem == 0
        let doubleTap = doubleTapCheckbox.state == .on
        let fontIdx = fontPopup.indexOfSelectedItem
        let selectedFont = (fontIdx >= 0 && fontIdx < availableFonts.count)
            ? availableFonts[fontIdx] : .systemMono

        let config = Config(
            apiKeys: keys,
            hotkey: recordedKeyName,
            defaultLevel: level,
            model: selectedModel,
            maxTokens: 4096,
            hotkeyKeyCode: Int(recordedKeyCode),
            hotkeyModifiers: Int(recordedModifiers),
            hotkeyDoubleTap: doubleTap,
            outputLanguage: language,
            darkMode: isDarkMode,
            fontFamily: selectedFont.rawValue,
            fontSize: Int(fontSizeSlider.doubleValue)
        )
        onSave?(config)

        // Fetch models in background
        let providerKeys = APIProvider.detectAll(from: keys)
        if !providerKeys.isEmpty {
            Task {
                let models = await modelFetcher.fetchAll(keys: providerKeys)
                await MainActor.run {
                    self.updateModelDropdown(models: models, selectedModel: selectedModel)
                    self.onModelsUpdated?(models)
                }
            }
        }

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
