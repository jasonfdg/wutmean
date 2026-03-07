import Cocoa
import ApplicationServices
import ServiceManagement
import os.log

private let log = OSLog(subsystem: "com.chaukam.instant-explain", category: "text-selection")

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
        guard let config = Config.load() else {
            showConfigAlert()
            return
        }
        currentConfig = config
        explainer = Explainer(apiKey: config.apiKey, model: config.model, maxTokens: config.maxTokens)

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Instant Explain")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Instant Explain", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Edit Prompt...", action: #selector(editPrompt), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Test Explain", action: #selector(testExplain), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Hotkey
        hotkeyListener.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        hotkeyListener.start(
            keyCode: UInt32(config.hotkeyKeyCode),
            modifiers: UInt32(config.hotkeyModifiers),
            doubleTap: config.hotkeyDoubleTap
        )

        // Settings callbacks
        settingsPanel.onSave = { [weak self] config in
            self?.applyConfig(config)
        }
        settingsPanel.onStartRecording = { [weak self] in
            self?.hotkeyListener.pause()
        }
        settingsPanel.onStopRecording = { [weak self] in
            self?.hotkeyListener.resume()
        }

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

    /// 0-based index for the configured default level (clamped to 0...4)
    private var defaultLevelIndex: Int {
        let level = currentConfig?.defaultLevel ?? 3
        return max(0, min(4, level - 1))
    }

    // MARK: - Config management

    private func applyConfig(_ config: Config) {
        Config.save(config)
        currentConfig = config
        explainer = Explainer(apiKey: config.apiKey, model: config.model, maxTokens: config.maxTokens)
        hotkeyListener.updateHotkey(
            keyCode: UInt32(config.hotkeyKeyCode),
            modifiers: UInt32(config.hotkeyModifiers),
            doubleTap: config.hotkeyDoubleTap
        )
    }

    // MARK: - Hotkey handler

    private func handleHotkey() {
        // Debounce rapid presses (M7)
        let now = ProcessInfo.processInfo.systemUptime
        if now - hotkeyDebounceTime < 0.25 { return }
        hotkeyDebounceTime = now

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
            // AX succeeded — show panel with text immediately
            os_log("handleHotkey: AX extracted %d chars", log: log, type: .debug, axResult.text.count)
            let panel = makePanel()
            let offset = popupStack.dropLast().last?.frame.origin
            panel.showLoading(text: axResult.text, offsetFrom: offset, defaultLevel: defaultLevelIndex)
            startExplain(text: axResult.text, context: axResult.context, on: panel)
        } else {
            // AX failed — show loading immediately, try async fallbacks (C1)
            os_log("handleHotkey: AX failed, trying async fallbacks", log: log, type: .debug)
            let panel = makePanel()
            let offset = popupStack.dropLast().last?.frame.origin
            panel.showLoading(text: "", offsetFrom: offset, defaultLevel: defaultLevelIndex)

            Task { @MainActor in
                // Cmd+C with async sleep (no main thread block)
                if let text = await getSelectedTextViaCmdC(sourcePID: sourcePID), !text.isEmpty {
                    os_log("handleHotkey: Cmd+C succeeded (%d chars)", log: log, type: .debug, text.count)
                    panel.updateKeyword(text)
                    startExplain(text: text, context: nil, on: panel)
                    return
                }

                // Cursor position (synchronous, fast)
                if let result = getTextAtCursorPosition() {
                    os_log("handleHotkey: cursor extraction succeeded", log: log, type: .debug)
                    panel.updateKeyword(result.keyword)
                    startExplain(text: result.keyword, context: result.context, on: panel)
                    return
                }

                os_log("handleHotkey: all stages failed", log: log, type: .debug)
                panel.showError("No text found.\n\nSelect text or hover over a word, then press \(hotkeyDisplayName).\n\nSome apps may need Accessibility permissions enabled in System Settings > Privacy & Security.")
            }
        }
    }

    private func startExplain(text: String, context: String?, on panel: PopupPanel) {
        panel.explainTask?.cancel()
        panel.explainTask = Task {
            do {
                guard let result = try await explainer?.explain(text: text, context: context, onStreamToken: { [weak panel] token in
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

        // Set the hotkey keycode so the panel lets it pass through
        if let config = currentConfig {
            panel.hotkeyKeyCode = UInt16(config.hotkeyKeyCode)
        }

        panel.onFollowUp = { [weak self, weak panel] originalText, question in
            guard let panel else { return }
            self?.handleFollowUp(originalText: originalText, question: question, on: panel)
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
            // LIFO: make the new topmost panel key so it receives Esc next
            if let topPanel = self.popupStack.last {
                topPanel.makeKeyAndOrderFront(nil)
            }
        }

        return panel
    }

    private func handleFollowUp(originalText: String, question: String, on panel: PopupPanel) {
        panel.showLoading(text: originalText, defaultLevel: defaultLevelIndex)

        panel.explainTask?.cancel()
        panel.explainTask = Task {
            do {
                guard let result = try await explainer?.explain(text: originalText, followUp: question, onStreamToken: { [weak panel] token in
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

    private func explainTerm(_ term: String, on panel: PopupPanel) {
        panel.showLoading(text: term, defaultLevel: defaultLevelIndex)

        panel.explainTask?.cancel()
        panel.explainTask = Task {
            do {
                guard let result = try await explainer?.explain(text: term, onStreamToken: { [weak panel] token in
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

    // Text extraction stages are now called individually from handleHotkey
    // to allow async Cmd+C without blocking the main thread (C1)

    private func getSelectedTextViaAXWithContext(sourcePID: pid_t?) -> TextExtraction? {
        // If we know the source app PID, target it directly instead of asking
        // the system for the "focused app" (which may be us after panel activation)
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
            // swiftlint:disable:next force_cast — CF type always succeeds; AX API guarantees type
            appElement = focusedApp as! AXUIElement
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            os_log("AX: could not get focused element", log: log, type: .debug)
            return nil
        }
        let element = focusedElement as! AXUIElement // CF type — guaranteed by AX API

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

        // Convert Cocoa global coords (origin = bottom-left of primary screen)
        // to CG coords (origin = top-left of primary screen)
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

        // Log the element role for debugging
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            os_log("cursor: element role = %{public}@", log: log, type: .info, roleValue as? String ?? "nil")
        }

        // Try to get text: element itself, then children, then walk up to parents
        let (fullText, textElement) = getTextFromElementOrAncestors(element)
        guard let fullText, !fullText.isEmpty else {
            os_log("cursor: no text content found in element, children, or parents", log: log, type: .info)
            return nil
        }
        os_log("cursor: got text (%d chars): \"%{public}@\"", log: log, type: .info,
               fullText.count, String(fullText.prefix(80)))

        let targetElement = textElement ?? element

        // Try to find character index at cursor position
        var charIndex: Int?

        // Method 1: AXCharacterForPoint parameterized attribute
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

        // Method 2: Fall back to insertion point / selected text range
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

        // Extract a meaningful phrase around the cursor position
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

        // No char index — extract the sentence or first meaningful chunk
        os_log("cursor: no char index, using full text extraction", log: log, type: .info)
        let sentence = extractFirstSentence(from: fullText)
        guard !sentence.isEmpty else { return nil }
        let context = String(fullText.prefix(min(fullText.count, 300)))
        return (keyword: sentence, context: context)
    }

    /// Try to get text from element, its children, and then walk UP to parent/grandparent.
    /// Returns the text and the element it came from (for AXCharacterForPoint targeting).
    private func getTextFromElementOrAncestors(_ element: AXUIElement) -> (String?, AXUIElement?) {
        // Try this element and its children first
        if let text = getTextFromElement(element), !text.isEmpty {
            return (text, element)
        }

        // Walk up to parent (up to 3 levels) — handles cases like <span> inside <p>
        var current = element
        for _ in 0..<3 {
            var parentValue: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success else {
                break
            }
            let parent = parentValue as! AXUIElement // CF type — guaranteed by AX API
            if let text = getTextFromElement(parent), !text.isEmpty {
                os_log("cursor: found text in parent element", log: log, type: .info)
                return (text, parent)
            }
            current = parent
        }

        return (nil, nil)
    }

    /// Extract text from a single AX element via multiple strategies
    private func getTextFromElement(_ element: AXUIElement) -> String? {
        // Strategy 1: kAXValueAttribute (text fields, text areas, web text nodes)
        var textValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let text = textValue as? String, !text.isEmpty {
            return text
        }

        // Strategy 2: AXStringForRange — for elements that expose char count but not value
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

        // Strategy 3: kAXTitleAttribute (buttons, labels, headings)
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String, !title.isEmpty {
            return title
        }

        // Strategy 4: kAXDescriptionAttribute
        var descValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue) == .success,
           let desc = descValue as? String, !desc.isEmpty {
            return desc
        }

        // Strategy 5: Walk children to find text
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            // Collect text from all text-bearing children (not just the first one)
            var collected: [String] = []
            for child in children.prefix(20) {
                // Only go one level deep for children to avoid explosion
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

    /// Extract a meaningful phrase (clause or noun phrase) around a character index
    private func extractPhrase(from text: NSString, around index: Int) -> String {
        let length = text.length
        guard length > 0 else { return "" }

        // Find sentence boundaries around the index
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
                sentEnd += 1  // include the period
                break
            }
            sentEnd += 1
        }

        let sentence = text.substring(with: NSRange(location: sentStart, length: sentEnd - sentStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If the sentence is short enough (< 80 chars), use it directly
        if sentence.count <= 80 {
            return sentence
        }

        // Otherwise, extract a clause: find comma/semicolon/dash boundaries within ±40 chars
        let clauseBreakers = CharacterSet(charactersIn: ",;:—–")
        var clauseStart = index
        var charsLeft = 40
        while clauseStart > sentStart && charsLeft > 0 {
            clauseStart -= 1
            charsLeft -= 1
            let ch = text.character(at: clauseStart)
            if let scalar = Unicode.Scalar(ch), clauseBreakers.contains(scalar) {
                clauseStart += 1  // skip the comma
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

    /// Extract the first meaningful sentence from a text block
    private func extractFirstSentence(from text: String) -> String {
        let sentenceBreakers = CharacterSet(charactersIn: ".!?;\n")
        let components = text.components(separatedBy: sentenceBreakers)
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 5 { return trimmed }
        }
        // Fall back to first 60 chars
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

        // Async sleep — yields the main thread (C1)
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard pasteboard.changeCount != oldChangeCount else {
            os_log("Cmd+C: pasteboard unchanged", log: log, type: .debug)
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    // MARK: - Menu actions

    private func showConfigAlert() {
        let alert = NSAlert()
        alert.messageText = "API Key Needed"
        alert.informativeText = "Instant Explain needs an Anthropic API key to work.\n\nOpen the config file and paste your key (starts with sk-ant-...).\n\nFile location:\n\(Config.configFile.path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Config")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Config.configFile)
        }
        NSApp.terminate(nil)
    }

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
        if let config = currentConfig ?? Config.load() {
            settingsPanel.loadConfig(config)
        }
        settingsPanel.showCentered()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Instant Explain"
        alert.informativeText = "Select text anywhere, press \(hotkeyDisplayName) to get instant explanations at 5 levels of complexity.\n\nLeft/Right arrows to switch levels.\nEnter for follow-up questions.\nEsc to dismiss."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

