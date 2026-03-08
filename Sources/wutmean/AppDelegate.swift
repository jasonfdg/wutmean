import Cocoa
import ApplicationServices
import ServiceManagement
import os.log

private let log = OSLog(subsystem: "com.chaukam.wutmean", category: "text-selection")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyListener = HotkeyListener()
    private var popupStack: [PopupPanel] = []
    private let settingsPanel = SettingsPanel()
    private var explainer: Explainer?
    private var currentConfig: Config?
    private let maxPopupDepth = 5
    private var hotkeyDebounceTime: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.ensureConfigExists()
        let config = Config.load()
        currentConfig = config
        Theme.darkMode = config.darkMode

        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: icnsURL) {
            NSApp.applicationIconImage = icon
        }

        if let provider = APIProvider.provider(forModel: config.model),
           let key = config.key(for: provider) {
            explainer = Explainer(provider: provider, apiKey: key, model: config.model, maxTokens: config.maxTokens)
        }

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        setupMenuBar()
        setupHotkey()
        setupSettingsCallbacks()
        registerLoginItem()

        if let warning = Config.loadWarning {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "wutmean"
                alert.informativeText = warning
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeMenuBarImage()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "wutmean", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Edit Prompt...", action: #selector(editPrompt), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makeMenuBarImage() -> NSImage {
        let text = "wut"
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let imageSize = NSSize(width: ceil(size.width) + 2, height: 18)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let y = (rect.height - size.height) / 2
            (text as NSString).draw(at: NSPoint(x: 1, y: y), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func setupHotkey() {
        guard let config = currentConfig else { return }
        hotkeyListener.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        hotkeyListener.start(
            keyCode: UInt32(config.hotkeyKeyCode),
            modifiers: UInt32(config.hotkeyModifiers),
            doubleTap: config.hotkeyDoubleTap
        )
    }

    private func setupSettingsCallbacks() {
        settingsPanel.onSave = { [weak self] config in
            self?.applyConfig(config)
        }
        settingsPanel.onStartRecording = { [weak self] in
            self?.hotkeyListener.pause()
        }
        settingsPanel.onStopRecording = { [weak self] in
            self?.hotkeyListener.resume()
        }
    }

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                os_log("Failed to register login item: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyListener.stop()
    }

    /// Returns the current hotkey display name (e.g., "F5", "double-tap F1", "⌃⌥E")
    private var hotkeyDisplayName: String {
        guard let config = currentConfig else { return "hotkey" }
        let name = config.hotkey
        return config.hotkeyDoubleTap ? "double-tap \(name)" : name
    }

    /// 0-based index for the configured default level (clamped to 0...2)
    private var defaultLevelIndex: Int {
        let level = currentConfig?.defaultLevel ?? 1
        return max(0, min(2, level - 1))
    }

    /// Configured output language
    private var outputLanguage: String {
        currentConfig?.outputLanguage ?? "English"
    }

    // MARK: - Config management

    private func applyConfig(_ config: Config) {
        Config.save(config)
        currentConfig = config
        Theme.darkMode = config.darkMode
        if let provider = APIProvider.provider(forModel: config.model),
           let key = config.key(for: provider) {
            explainer = Explainer(provider: provider, apiKey: key, model: config.model, maxTokens: config.maxTokens)
        } else {
            explainer = nil
        }
        hotkeyListener.updateHotkey(
            keyCode: UInt32(config.hotkeyKeyCode),
            modifiers: UInt32(config.hotkeyModifiers),
            doubleTap: config.hotkeyDoubleTap
        )
        for panel in popupStack where panel.isVisible {
            panel.refreshTheme()
        }
    }

    // MARK: - Hotkey handler

    private func handleHotkey() {
        // Debounce rapid presses (M7)
        let now = ProcessInfo.processInfo.systemUptime
        if now - hotkeyDebounceTime < 0.25 { return }
        hotkeyDebounceTime = now

        // No API key — show message in popup
        if explainer == nil {
            let panel = makePanel()
            panel.showLoading(text: "Setup", defaultLevel: defaultLevelIndex)
            panel.showError("No API key configured.\n\nGo to Settings (menu bar) and paste your API key(s) — Anthropic, OpenAI, or Google.")
            return
        }

        // Prune deallocated panels
        popupStack.removeAll(where: { !$0.isVisible })

        // Cap at max depth
        if popupStack.count >= maxPopupDepth {
            popupStack.last?.showMaxDepthFlash()
            return
        }

        // CRITICAL: Capture the frontmost app BEFORE we create/show any panel.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourcePID = sourceApp?.processIdentifier
        os_log("handleHotkey: source app = %{public}@ (pid %d)", log: log, type: .debug,
               sourceApp?.localizedName ?? "nil", sourcePID ?? -1)

        // Try AX extraction synchronously (fast path)
        let axResult = getSelectedTextViaAXWithContext(sourcePID: sourcePID)

        if let axResult, !axResult.text.isEmpty {
            os_log("handleHotkey: AX extracted %d chars", log: log, type: .debug, axResult.text.count)
            let panel = makePanel()
            let offset = popupStack.dropLast().last?.frame.origin
            panel.showLoading(text: axResult.text, offsetFrom: offset, defaultLevel: defaultLevelIndex)
            startExplain(text: axResult.text, context: axResult.context, on: panel)
        } else {
            // AX failed — try Cmd+C BEFORE showing panel (app must stay frontmost for Chrome)
            os_log("handleHotkey: AX failed, trying Cmd+C before showing panel", log: log, type: .debug)

            Task { @MainActor in
                if let text = await getSelectedTextViaCmdC(sourcePID: sourcePID), !text.isEmpty {
                    os_log("handleHotkey: Cmd+C succeeded (%d chars)", log: log, type: .debug, text.count)
                    let panel = makePanel()
                    let offset = popupStack.dropLast().last?.frame.origin
                    panel.showLoading(text: text, offsetFrom: offset, defaultLevel: defaultLevelIndex)
                    startExplain(text: text, context: nil, on: panel)
                    return
                }

                if let result = getTextAtCursorPosition() {
                    os_log("handleHotkey: cursor extraction succeeded", log: log, type: .debug)
                    let panel = makePanel()
                    let offset = popupStack.dropLast().last?.frame.origin
                    panel.showLoading(text: result.keyword, offsetFrom: offset, defaultLevel: defaultLevelIndex)
                    startExplain(text: result.keyword, context: result.context, on: panel)
                    return
                }

                os_log("handleHotkey: all stages failed", log: log, type: .debug)
                let panel = makePanel()
                let offset = popupStack.dropLast().last?.frame.origin
                panel.showLoading(text: "", offsetFrom: offset, defaultLevel: defaultLevelIndex)
                panel.showError("No text found.\n\nSelect text or hover over a word, then press \(hotkeyDisplayName).\n\nSome apps may need Accessibility permissions enabled in System Settings > Privacy & Security.")
            }
        }
    }

    private func startExplain(text: String, context: String?, on panel: PopupPanel) {
        let language = outputLanguage
        panel.explainTask?.cancel()
        panel.explainTask = Task {
            do {
                guard let result = try await explainer?.explain(text: text, context: context, language: language, onStreamToken: { [weak panel] token in
                    Task { @MainActor in
                        panel?.appendStreamToken(token)
                    }
                }) else { return }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    panel.showResult(result)
                }
            } catch is CancellationError {
                // Rapid press or dismiss, ignore
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    panel.showError(error.localizedDescription)
                }
            }
        }
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel()
        popupStack.append(panel)

        if let config = currentConfig {
            panel.hotkeyKeyCode = UInt16(config.hotkeyKeyCode)
        }

        panel.onExplainTerm = { [weak self, weak panel] term in
            guard let panel else { return }
            self?.explainTerm(term, on: panel)
        }
        panel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.popupStack.removeAll(where: { $0 === panel })
            if let topPanel = self.popupStack.last {
                topPanel.makeKeyAndOrderFront(nil)
            }
        }

        return panel
    }

    private func explainTerm(_ term: String, on panel: PopupPanel) {
        let defaultLevel = defaultLevelIndex
        panel.showLoading(text: term, defaultLevel: defaultLevel)

        let language = outputLanguage
        panel.explainTask?.cancel()
        panel.explainTask = Task {
            do {
                guard let result = try await explainer?.explain(text: term, language: language, onStreamToken: { [weak panel] token in
                    Task { @MainActor in
                        panel?.appendStreamToken(token)
                    }
                }) else { return }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    panel.showResult(result)
                }
            } catch is CancellationError {
                // ignore
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    panel.showError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Text extraction with context

    private struct TextExtraction {
        let text: String
        let context: String?
    }

    private func getSelectedTextViaAXWithContext(sourcePID: pid_t?) -> TextExtraction? {
        let appElement: AXUIElement
        if let pid = sourcePID {
            appElement = AXUIElementCreateApplication(pid)
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedApp: AnyObject?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
                os_log("AX: could not get focused app", log: log, type: .debug)
                return nil
            }
            appElement = focusedApp as! AXUIElement
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            os_log("AX: could not get focused element", log: log, type: .debug)
            return nil
        }
        let element = focusedElement as! AXUIElement

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
              let text = selectedText as? String, !text.isEmpty else {
            os_log("AX: no selected text", log: log, type: .debug)
            return nil
        }

        let context = extractSurroundingContext(from: element, selectedText: text)
        return TextExtraction(text: text, context: context)
    }

    private func extractSurroundingContext(from element: AXUIElement, selectedText: String) -> String? {
        var fullTextValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullTextValue) == .success,
              let fullText = fullTextValue as? String else {
            return nil
        }

        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }
        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, AXValueType.cfRange, &cfRange) else {
            return nil
        }

        let selStart = cfRange.location
        let selEnd = cfRange.location + cfRange.length
        let contextRadius = 100
        let beforeStart = max(0, selStart - contextRadius)
        let afterEnd = min(fullText.count, selEnd + contextRadius)

        let nsString = fullText as NSString
        let beforeText = nsString.substring(with: NSRange(location: beforeStart, length: selStart - beforeStart))
        let afterText = nsString.substring(with: NSRange(location: selEnd, length: afterEnd - selEnd))

        return "...\(beforeText)[SELECTED: \(selectedText)]\(afterText)..."
    }

    // MARK: - Point-and-trigger

    private func getTextAtCursorPosition() -> (keyword: String, context: String)? {
        let mouseLocation = NSEvent.mouseLocation
        os_log("cursor: mouse at (%{public}.0f, %{public}.0f)", log: log, type: .info, mouseLocation.x, mouseLocation.y)

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(
            x: mouseLocation.x,
            y: primaryScreenHeight - mouseLocation.y
        )
        os_log("cursor: CG point (%{public}.0f, %{public}.0f)", log: log, type: .info, cgPoint.x, cgPoint.y)

        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let posResult = AXUIElementCopyElementAtPosition(systemWide, Float(cgPoint.x), Float(cgPoint.y), &elementRef)
        guard posResult == .success, let element = elementRef else {
            os_log("cursor: AXUIElementCopyElementAtPosition failed (%d)", log: log, type: .info, posResult.rawValue)
            return nil
        }

        // Skip elements belonging to our own app (popup may overlay the cursor position)
        var elementPid: pid_t = 0
        AXUIElementGetPid(element, &elementPid)
        if elementPid == ProcessInfo.processInfo.processIdentifier {
            os_log("cursor: element belongs to our app, skipping", log: log, type: .info)
            return nil
        }

        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            os_log("cursor: element role = %{public}@", log: log, type: .info, roleValue as? String ?? "nil")
        }

        let (fullText, textElement) = getTextFromElementOrAncestors(element)
        guard let fullText, !fullText.isEmpty else {
            os_log("cursor: no text content found in element, children, or parents", log: log, type: .info)
            return nil
        }
        os_log("cursor: got text (%d chars): \"%{public}@\"", log: log, type: .info,
               fullText.count, String(fullText.prefix(80)))

        let targetElement = textElement ?? element

        var charIndex: Int?

        var mutablePoint = cgPoint
        if let axPoint = AXValueCreate(AXValueType.cgPoint, &mutablePoint) {
            var resultValue: AnyObject?
            if AXUIElementCopyParameterizedAttributeValue(
                targetElement, "AXCharacterForPoint" as CFString, axPoint, &resultValue
            ) == .success {
                charIndex = resultValue as? Int
                os_log("cursor: AXCharacterForPoint -> index %d", log: log, type: .info, charIndex ?? -1)
            }
        }

        if charIndex == nil {
            var insertionValue: AnyObject?
            if AXUIElementCopyAttributeValue(targetElement, kAXSelectedTextRangeAttribute as CFString, &insertionValue) == .success {
                var cfRange = CFRange(location: 0, length: 0)
                if AXValueGetValue(insertionValue as! AXValue, AXValueType.cfRange, &cfRange) {
                    charIndex = cfRange.location
                    os_log("cursor: insertion point -> index %d", log: log, type: .info, charIndex ?? -1)
                }
            }
        }

        let nsString = fullText as NSString

        if let idx = charIndex, idx >= 0, idx < nsString.length {
            let phrase = extractPhrase(from: nsString, around: idx)
            guard !phrase.isEmpty else { return nil }
            let contextRadius = 150
            let contextStart = max(0, idx - contextRadius)
            let contextEnd = min(nsString.length, idx + contextRadius)
            let context = nsString.substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
            os_log("cursor: extracted phrase \"%{public}@\"", log: log, type: .info, phrase)
            return (keyword: phrase, context: "..." + context + "...")
        }

        os_log("cursor: no char index, using full text extraction", log: log, type: .info)
        let sentence = extractFirstSentence(from: fullText)
        guard !sentence.isEmpty else { return nil }
        let context = String(fullText.prefix(min(fullText.count, 300)))
        return (keyword: sentence, context: context)
    }

    private func getTextFromElementOrAncestors(_ element: AXUIElement) -> (String?, AXUIElement?) {
        if let text = getTextFromElement(element), !text.isEmpty {
            return (text, element)
        }

        var current = element
        for _ in 0..<3 {
            var parentValue: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success else {
                break
            }
            let parent = parentValue as! AXUIElement
            if let text = getTextFromElement(parent), !text.isEmpty {
                os_log("cursor: found text in parent element", log: log, type: .info)
                return (text, parent)
            }
            current = parent
        }

        return (nil, nil)
    }

    private func getTextFromElement(_ element: AXUIElement) -> String? {
        var textValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let text = textValue as? String, !text.isEmpty {
            return text
        }

        var charCountValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &charCountValue) == .success,
           let charCount = charCountValue as? Int, charCount > 0 {
            var cfRange = CFRange(location: 0, length: min(charCount, 2000))
            if let rangeValue = AXValueCreate(AXValueType.cfRange, &cfRange) {
                var stringResult: AnyObject?
                if AXUIElementCopyParameterizedAttributeValue(
                    element, "AXStringForRange" as CFString, rangeValue, &stringResult
                ) == .success, let text = stringResult as? String, !text.isEmpty {
                    return text
                }
            }
        }

        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String, !title.isEmpty {
            return title
        }

        var descValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue) == .success,
           let desc = descValue as? String, !desc.isEmpty {
            return desc
        }

        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            var collected: [String] = []
            for child in children.prefix(20) {
                var cv: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &cv) == .success,
                   let t = cv as? String, !t.isEmpty {
                    collected.append(t)
                } else if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &cv) == .success,
                          let t = cv as? String, !t.isEmpty {
                    collected.append(t)
                }
            }
            if !collected.isEmpty {
                return collected.joined(separator: " ")
            }
        }

        return nil
    }

    private func extractPhrase(from text: NSString, around index: Int) -> String {
        let length = text.length
        guard length > 0 else { return "" }

        let sentenceBreakers = CharacterSet(charactersIn: ".!?;\n\r")
        var sentStart = index
        while sentStart > 0 {
            let ch = text.character(at: sentStart - 1)
            if let scalar = Unicode.Scalar(ch), sentenceBreakers.contains(scalar) { break }
            sentStart -= 1
        }
        var sentEnd = index
        while sentEnd < length {
            let ch = text.character(at: sentEnd)
            if let scalar = Unicode.Scalar(ch), sentenceBreakers.contains(scalar) {
                sentEnd += 1
                break
            }
            sentEnd += 1
        }

        let sentence = text.substring(with: NSRange(location: sentStart, length: sentEnd - sentStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sentence.count <= 80 {
            return sentence
        }

        let clauseBreakers = CharacterSet(charactersIn: ",;:—–")
        var clauseStart = index
        var charsLeft = 40
        while clauseStart > sentStart && charsLeft > 0 {
            clauseStart -= 1
            charsLeft -= 1
            let ch = text.character(at: clauseStart)
            if let scalar = Unicode.Scalar(ch), clauseBreakers.contains(scalar) {
                clauseStart += 1
                break
            }
        }
        var clauseEnd = index
        var charsRight = 40
        while clauseEnd < sentEnd && charsRight > 0 {
            let ch = text.character(at: clauseEnd)
            if let scalar = Unicode.Scalar(ch), clauseBreakers.contains(scalar) { break }
            clauseEnd += 1
            charsRight -= 1
        }

        return text.substring(with: NSRange(location: clauseStart, length: clauseEnd - clauseStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractFirstSentence(from text: String) -> String {
        let sentenceBreakers = CharacterSet(charactersIn: ".!?;\n")
        let components = text.components(separatedBy: sentenceBreakers)
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 5 { return trimmed }
        }
        let prefix = String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix
    }

    private func getSelectedTextViaCmdC(sourcePID: pid_t?) async -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand

        if let pid = sourcePID {
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        } else {
            keyDown?.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
            keyUp?.post(tap: CGEventTapLocation.cgAnnotatedSessionEventTap)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        guard pasteboard.changeCount != oldChangeCount else {
            os_log("Cmd+C: pasteboard unchanged", log: log, type: .debug)
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    // MARK: - Menu actions

    @objc private func testExplain() {
        let testText = "Quantum entanglement is a phenomenon where two particles become interconnected and the quantum state of one instantly influences the other, regardless of distance."
        let panel = makePanel()
        panel.showLoading(text: testText, defaultLevel: defaultLevelIndex)
        startExplain(text: testText, context: nil, on: panel)
    }

    @objc private func editPrompt() {
        Config.ensureConfigExists()
        NSWorkspace.shared.open(Config.promptFile)
    }

    @objc private func openSettings() {
        let config = currentConfig ?? Config.load()
        settingsPanel.loadConfig(config)
        settingsPanel.showCentered()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "wutmean"
        alert.informativeText = "Select text anywhere, press \(hotkeyDisplayName) to get instant explanations at 3 levels: Plain, Technical, and Examples.\n\nLeft/Right arrows to switch levels.\nEsc to dismiss."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
