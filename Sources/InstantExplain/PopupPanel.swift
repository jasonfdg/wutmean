import Cocoa

final class PopupPanel: NSPanel, NSTextFieldDelegate, NSMenuDelegate {
    private let levelNames = ["The Gist", "Essentials", "Mechanism", "Nuance", "Frontier"]
    private var currentLevel = 2
    private var levels: [String] = []
    private var relatedTerms: [String] = []
    private var searchPhrases: [String] = []
    private var originalText = ""

    /// Per-panel task ownership (C4): each panel owns its explain task
    var explainTask: Task<Void, Never>?

    /// Token batching (H1): accumulate tokens and flush on timer
    private var pendingTokens = ""
    private var flushTimer: DispatchSourceTimer?

    private let bodyText = NSTextField(wrappingLabelWithString: "")
    private let levelLabel = NSTextField(labelWithString: "")
    private let keywordLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let settingsButton = NSButton()
    private let loadingIndicator = NSProgressIndicator()
    private let scrollView = NSScrollView()

    // Separator line between body and bottom section
    private let separatorLine = NSView()

    // Nav row (includes copy icon and overflow menu trigger)
    private let navContainer = NSView()
    private var navLabels: [NSTextField] = []
    private var navTrackingAreas: [NSTrackingArea] = []
    private let copyLabel = NSTextField(labelWithString: "⎘")
    private let overflowLabel = NSTextField(labelWithString: "⋯")
    private let overflowMenu = NSMenu()

    // Related concepts row
    private let relatedContainer = NSView()
    private let relatedPrefix = NSTextField(labelWithString: "explore →")
    private var relatedLabels: [NSTextField] = []
    private var relatedTrackingAreas: [NSTrackingArea] = []

    // Terminal-style follow-up
    private let followUpContainer = NSView()
    private let followUpPrompt = NSTextField(labelWithString: "> ")
    private let followUpField = NSTextField()

    // Keyboard monitor
    private var keyMonitor: Any?

    /// The keyCode of the configured hotkey — let it pass through to spawn new popups
    var hotkeyKeyCode: UInt16 = 96  // default F5, updated by AppDelegate

    var onFollowUp: ((String, String) -> Void)?
    var onExplainTerm: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Dynamic panel width based on screen
    private var panelWidth: CGFloat {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return 560 }
        return min(620, screen.visibleFrame.width * 0.45)
    }

    private let panelHeight: CGFloat = 420

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true

        // Accessibility (H6)
        setAccessibilityRole(.popover)
        setAccessibilityLabel("Instant Explain")

        setupUI()
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: panelHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.panelBackground.cgColor
        container.layer?.cornerRadius = Theme.panelCornerRadius
        container.layer?.borderColor = Theme.panelBorder.cgColor
        container.layer?.borderWidth = 1
        self.contentView = container

        // Close button
        closeButton.bezelStyle = .inline
        closeButton.title = "✕"
        closeButton.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        closeButton.isBordered = false
        closeButton.contentTintColor = Theme.controlDim
        closeButton.setAccessibilityLabel("Close")
        closeButton.setAccessibilityRole(.button)
        closeButton.target = self
        closeButton.action = #selector(dismissPanel)
        container.addSubview(closeButton)

        // Settings gear button
        settingsButton.bezelStyle = .inline
        settingsButton.title = "⚙"
        settingsButton.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        settingsButton.isBordered = false
        settingsButton.contentTintColor = Theme.controlDim
        settingsButton.setAccessibilityLabel("Settings")
        settingsButton.setAccessibilityRole(.button)
        settingsButton.target = self
        settingsButton.action = #selector(openSettingsAction)
        container.addSubview(settingsButton)

        // Level label (secondary: 11pt)
        levelLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        levelLabel.textColor = Theme.accent
        container.addSubview(levelLabel)

        // Keyword label (primary: 13pt)
        keywordLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        keywordLabel.textColor = Theme.accentDim
        keywordLabel.isHidden = true
        container.addSubview(keywordLabel)

        // Loading indicator
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        container.addSubview(loadingIndicator)

        // Body text
        bodyText.isEditable = false
        bodyText.isSelectable = true
        bodyText.drawsBackground = false
        bodyText.isBordered = false
        bodyText.textColor = Theme.textPrimary
        bodyText.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        bodyText.lineBreakMode = .byWordWrapping
        bodyText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = bodyText
        container.addSubview(scrollView)

        // Separator line
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = Theme.separator.cgColor
        container.addSubview(separatorLine)

        // Related concepts container
        relatedContainer.wantsLayer = true
        relatedContainer.isHidden = true
        relatedPrefix.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        relatedPrefix.textColor = Theme.textTertiary
        relatedContainer.addSubview(relatedPrefix)
        container.addSubview(relatedContainer)

        // Nav hints container (includes copy + overflow)
        navContainer.wantsLayer = true
        container.addSubview(navContainer)
        setupNavHints()

        // Follow-up container
        followUpContainer.isHidden = true
        container.addSubview(followUpContainer)

        followUpPrompt.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        followUpPrompt.textColor = Theme.success
        followUpContainer.addSubview(followUpPrompt)

        followUpField.placeholderString = "ask a follow-up..."
        followUpField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        followUpField.textColor = .white
        followUpField.backgroundColor = .clear
        followUpField.drawsBackground = false
        followUpField.isBordered = false
        followUpField.focusRingType = .none
        followUpField.target = self
        followUpField.action = #selector(submitFollowUp)
        followUpContainer.addSubview(followUpField)

        // Overflow menu for search actions
        setupOverflowMenu()
    }

    private func setupNavHints() {
        let items: [(String, Selector)] = [
            ("← simpler", #selector(navSimpler)),
            ("harder →", #selector(navHarder)),
            ("esc close", #selector(dismissPanel)),
            ("⏎ follow-up", #selector(navFollowUp))
        ]

        for (title, action) in items {
            let label = NSTextField(labelWithString: title)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = Theme.textSecondary
            label.isSelectable = false
            label.wantsLayer = true
            label.setAccessibilityRole(.button)
            label.setAccessibilityLabel(title)
            navContainer.addSubview(label)
            navLabels.append(label)

            let click = NSClickGestureRecognizer(target: self, action: action)
            label.addGestureRecognizer(click)
        }

        // Copy icon — right-aligned on nav row, 15pt with 28x28 hit area
        copyLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        copyLabel.textColor = Theme.textSecondary
        copyLabel.isSelectable = false
        copyLabel.wantsLayer = true
        copyLabel.alignment = .center
        copyLabel.setAccessibilityRole(.button)
        copyLabel.setAccessibilityLabel("Copy explanation")
        navContainer.addSubview(copyLabel)
        let copyClick = NSClickGestureRecognizer(target: self, action: #selector(actionCopy))
        copyLabel.addGestureRecognizer(copyClick)

        // Overflow icon — right-aligned next to copy, 15pt with 28x28 hit area
        overflowLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        overflowLabel.textColor = Theme.textSecondary
        overflowLabel.isSelectable = false
        overflowLabel.wantsLayer = true
        overflowLabel.alignment = .center
        overflowLabel.setAccessibilityRole(.button)
        overflowLabel.setAccessibilityLabel("More actions")
        navContainer.addSubview(overflowLabel)
        let overflowClick = NSClickGestureRecognizer(target: self, action: #selector(showOverflowMenu(_:)))
        overflowLabel.addGestureRecognizer(overflowClick)
    }

    private func setupOverflowMenu() {
        overflowMenu.addItem(withTitle: "Google", action: #selector(actionGoogle), keyEquivalent: "")
        overflowMenu.addItem(withTitle: "Wikipedia", action: #selector(actionWikipedia), keyEquivalent: "")
        overflowMenu.addItem(withTitle: "YouTube", action: #selector(actionYouTube), keyEquivalent: "")
        for item in overflowMenu.items { item.target = self }
    }

    @objc private func showOverflowMenu(_ gesture: NSClickGestureRecognizer) {
        overflowMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowLabel.bounds.height + 4), in: overflowLabel)
    }

    private func installTrackingAreas() {
        // Nav tracking areas
        for area in navTrackingAreas { navContainer.removeTrackingArea(area) }
        navTrackingAreas.removeAll()
        for label in navLabels {
            let area = NSTrackingArea(
                rect: label.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["label": label]
            )
            navContainer.addTrackingArea(area)
            navTrackingAreas.append(area)
        }

        // Copy + overflow tracking
        for view in [copyLabel, overflowLabel] {
            let area = NSTrackingArea(
                rect: view.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["label": view]
            )
            navContainer.addTrackingArea(area)
            navTrackingAreas.append(area)
        }

        // Related tracking areas
        for area in relatedTrackingAreas { relatedContainer.removeTrackingArea(area) }
        relatedTrackingAreas.removeAll()
        for label in relatedLabels {
            let area = NSTrackingArea(
                rect: label.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["label": label]
            )
            relatedContainer.addTrackingArea(area)
            relatedTrackingAreas.append(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let label = event.trackingArea?.userInfo?["label"] as? NSTextField {
            label.textColor = relatedLabels.contains(label) ? Theme.relatedHover : Theme.textHover
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let label = event.trackingArea?.userInfo?["label"] as? NSTextField {
            label.textColor = relatedLabels.contains(label) ? Theme.relatedText : Theme.textSecondary
        }
    }

    @objc private func navSimpler() {
        if currentLevel > 0 { currentLevel -= 1; updateDisplay() }
    }

    @objc private func navHarder() {
        if currentLevel < 4 { currentLevel += 1; updateDisplay() }
    }

    @objc private func navFollowUp() {
        if followUpContainer.isHidden { toggleFollowUp() }
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    // MARK: - Action buttons

    @objc private func actionCopy() {
        guard !levels.isEmpty else { return }
        let text = levels[currentLevel]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Visual + text feedback (M1: not color-only)
        let originalText = copyLabel.stringValue
        let originalColor = copyLabel.textColor
        copyLabel.stringValue = "✓"
        copyLabel.textColor = Theme.success
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.copyLabel.stringValue = originalText
            self?.copyLabel.textColor = originalColor
        }
    }

    @objc private func actionGoogle() {
        openSearch("https://www.google.com/search?q=", query: smartSearchQuery())
    }

    @objc private func actionWikipedia() {
        openSearch("https://en.wikipedia.org/wiki/Special:Search?search=", query: originalText)
    }

    @objc private func actionYouTube() {
        openSearch("https://www.youtube.com/results?search_query=", query: smartSearchQuery())
    }

    /// Build a contextual search query: use first search phrase if available, else "keyword" + original text
    private func smartSearchQuery() -> String {
        // If we have search phrases from the LLM, use the first one as a general search
        if let first = searchPhrases.first, !first.isEmpty {
            return "\"\(originalText)\" \(first)"
        }
        // Fallback: just the original text
        return originalText
    }

    private func openSearch(_ baseURL: String, query: String) {
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseURL + encoded) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Layout

    private func applyDynamicSize() {
        let w = panelWidth
        let h = panelHeight
        setContentSize(NSSize(width: w, height: h))
        contentView?.frame = NSRect(x: 0, y: 0, width: w, height: h)
        layoutSubviews()
    }

    private func layoutSubviews() {
        guard let container = contentView else { return }
        let w = container.frame.width
        let h = container.frame.height

        closeButton.frame = NSRect(x: w - 34, y: h - 34, width: 24, height: 24)
        settingsButton.frame = NSRect(x: w - 58, y: h - 34, width: 24, height: 24)
        levelLabel.frame = NSRect(x: 16, y: h - 36, width: 300, height: 20)
        loadingIndicator.frame = NSRect(x: 220, y: h - 36, width: 16, height: 16)
        keywordLabel.frame = NSRect(x: 16, y: h - 54, width: w - 32, height: 16)

        // Bottom section: 2 rows, 10px bottom padding, 8px between rows
        let navY: CGFloat = 10
        let relatedY: CGFloat = navY + 18 + 8
        let separatorY: CGFloat = relatedY + 18 + 8
        let scrollBottom: CGFloat = separatorY + 1 + 4

        let scrollTop = h - 60
        scrollView.frame = NSRect(x: 16, y: scrollBottom, width: w - 32, height: scrollTop - scrollBottom)

        // Separator line
        separatorLine.frame = NSRect(x: 16, y: separatorY, width: w - 32, height: 1)

        // Related concepts row
        relatedContainer.frame = NSRect(x: 16, y: relatedY, width: w - 32, height: 18)

        // Nav hints row
        navContainer.frame = NSRect(x: 16, y: navY, width: w - 32, height: 18)
        layoutNavLabels()

        // Follow-up container (replaces nav when active)
        followUpContainer.frame = NSRect(x: 16, y: navY, width: w - 32, height: 22)
        followUpPrompt.frame = NSRect(x: 0, y: 1, width: 20, height: 20)
        followUpField.frame = NSRect(x: 20, y: 0, width: w - 32 - 20, height: 22)

        resizeBodyText()
    }

    private func layoutNavLabels() {
        let spacing: CGFloat = 20
        var totalWidth: CGFloat = 0
        for label in navLabels {
            label.sizeToFit()
            totalWidth += label.frame.width
        }
        totalWidth += spacing * CGFloat(navLabels.count - 1)

        // Center the nav hints
        var x = (navContainer.frame.width - totalWidth) / 2
        for label in navLabels {
            label.frame = NSRect(x: x, y: 0, width: label.frame.width, height: 18)
            x += label.frame.width + spacing
        }

        // Right-align copy + overflow icons with 28x28 hit area
        let iconSize: CGFloat = 28
        let rightEdge = navContainer.frame.width
        let iconY = (18 - iconSize) / 2  // vertically center in nav row
        overflowLabel.frame = NSRect(x: rightEdge - iconSize - 12, y: iconY, width: iconSize, height: iconSize)
        copyLabel.frame = NSRect(x: overflowLabel.frame.minX - iconSize - 8, y: iconY, width: iconSize, height: iconSize)

        installTrackingAreas()
    }

    private func layoutRelatedLabels() {
        // Remove old related labels
        for label in relatedLabels { label.removeFromSuperview() }
        for area in relatedTrackingAreas { relatedContainer.removeTrackingArea(area) }
        relatedLabels.removeAll()
        relatedTrackingAreas.removeAll()

        guard !relatedTerms.isEmpty else {
            relatedContainer.isHidden = true
            return
        }

        // Build term labels separated by · (middle dot)
        let terms = Array(relatedTerms.prefix(3))
        for (i, term) in terms.enumerated() {
            if i > 0 {
                // Add middle dot separator
                let dot = NSTextField(labelWithString: "·")
                dot.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                dot.textColor = Theme.relatedDot
                dot.isSelectable = false
                relatedContainer.addSubview(dot)
                relatedLabels.append(dot)  // track for layout but no click
            }

            let label = NSTextField(labelWithString: term)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = Theme.relatedText
            label.isSelectable = false
            label.wantsLayer = true
            relatedContainer.addSubview(label)
            relatedLabels.append(label)

            let click = NSClickGestureRecognizer(target: self, action: #selector(relatedTermClicked(_:)))
            label.addGestureRecognizer(click)
        }

        // Layout: "explore →" prefix + dot-separated terms, centered
        relatedPrefix.sizeToFit()
        let prefixWidth = relatedPrefix.frame.width + 6

        let dotSpacing: CGFloat = 4
        var totalWidth = prefixWidth
        for label in relatedLabels {
            label.sizeToFit()
            totalWidth += label.frame.width + dotSpacing
        }
        totalWidth -= dotSpacing  // no trailing space

        var x = max(0, (relatedContainer.frame.width - totalWidth) / 2)
        relatedPrefix.frame = NSRect(x: x, y: 0, width: relatedPrefix.frame.width, height: 16)
        x += prefixWidth

        for label in relatedLabels {
            label.frame = NSRect(x: x, y: 0, width: label.frame.width, height: 16)
            x += label.frame.width + dotSpacing
        }

        // Install tracking areas only for clickable term labels (not dots)
        for area in relatedTrackingAreas { relatedContainer.removeTrackingArea(area) }
        relatedTrackingAreas.removeAll()
        for label in relatedLabels where label.stringValue != "·" {
            let area = NSTrackingArea(
                rect: label.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["label": label]
            )
            relatedContainer.addTrackingArea(area)
            relatedTrackingAreas.append(area)
        }

        relatedContainer.isHidden = false
    }

    @objc private func relatedTermClicked(_ gesture: NSClickGestureRecognizer) {
        guard let label = gesture.view as? NSTextField else { return }
        let term = label.stringValue
        guard term != "·" else { return }
        onExplainTerm?(term)
    }

    private func resizeBodyText() {
        let width = scrollView.contentSize.width
        bodyText.preferredMaxLayoutWidth = width
        let fittingSize = bodyText.sizeThatFits(NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        bodyText.frame = NSRect(x: 0, y: 0, width: width, height: max(fittingSize.height, scrollView.frame.height))
    }

    // MARK: - Public API

    func showLoading(text: String, offsetFrom: NSPoint? = nil, defaultLevel: Int = 2) {
        self.originalText = text
        self.levels = []
        self.relatedTerms = []
        self.currentLevel = defaultLevel
        self.followUpContainer.isHidden = true
        self.followUpField.stringValue = ""
        self.pendingTokens = ""
        self.flushTimer?.cancel()
        self.flushTimer = nil
        navContainer.isHidden = false
        relatedContainer.isHidden = true
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimation(nil)
        let name = levelNames[defaultLevel]
        levelLabel.stringValue = "[ \(name) ] \(defaultLevel + 1)/5"

        // Show keyword being explained
        if !text.isEmpty {
            let display = text.count > 60 ? String(text.prefix(57)) + "..." : text
            keywordLabel.stringValue = "> explaining: \"\(display)\""
            keywordLabel.isHidden = false
        } else {
            keywordLabel.isHidden = true
        }

        bodyText.stringValue = ""
        applyDynamicSize()
        hideNavLabels()
        copyLabel.isHidden = true
        overflowLabel.isHidden = true
        if let offset = offsetFrom {
            setFrameOrigin(NSPoint(x: offset.x + 20, y: offset.y - 20))
        } else {
            centerOnScreen()
        }
        makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKey()
        installKeyMonitor()

        // Accessibility announcement (H5)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    /// Update the keyword label after async text extraction (C1)
    func updateKeyword(_ text: String) {
        self.originalText = text
        if !text.isEmpty {
            let display = text.count > 60 ? String(text.prefix(57)) + "..." : text
            keywordLabel.stringValue = "> explaining: \"\(display)\""
            keywordLabel.isHidden = false
        }
    }

    func showMaxDepthFlash() {
        let original = levelLabel.stringValue
        levelLabel.stringValue = "[ max popups open ]"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.levelLabel.stringValue = original
        }
    }

    func appendStreamToken(_ token: String) {
        pendingTokens += token
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.flushPendingTokens()
        }
        timer.resume()
        flushTimer = timer
    }

    private func flushPendingTokens() {
        flushTimer?.cancel()
        flushTimer = nil
        guard !pendingTokens.isEmpty else { return }
        bodyText.stringValue += pendingTokens
        pendingTokens = ""
        resizeBodyText()
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let documentView = scrollView.documentView else { return }
        let maxY = max(0, documentView.frame.height - scrollView.contentSize.height)
        documentView.scroll(NSPoint(x: 0, y: maxY))
    }

    func showResult(_ result: Explainer.ExplanationResult) {
        flushPendingTokens()
        self.levels = result.levels
        self.relatedTerms = result.relatedTerms
        self.searchPhrases = result.searchPhrases
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true
        copyLabel.isHidden = false
        overflowLabel.isHidden = false
        layoutRelatedLabels()
        updateDisplay()
    }

    func showError(_ message: String) {
        flushTimer?.cancel()
        flushTimer = nil
        pendingTokens = ""
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true
        levelLabel.stringValue = "[ Error ]"
        bodyText.stringValue = message
        resizeBodyText()
        relatedContainer.isHidden = true
        copyLabel.isHidden = true
        overflowLabel.isHidden = true
        showNavLabels()
        for (i, label) in navLabels.enumerated() {
            label.isHidden = (i != 2)  // only "esc close"
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    @objc func dismissPanel() {
        explainTask?.cancel()
        explainTask = nil
        flushTimer?.cancel()
        flushTimer = nil
        pendingTokens = ""
        orderOut(nil)
        followUpContainer.isHidden = true
        navContainer.isHidden = false
        followUpField.stringValue = ""
        removeKeyMonitor()
        onDismiss?()
    }

    func toggleFollowUp() {
        followUpContainer.isHidden.toggle()
        navContainer.isHidden = !followUpContainer.isHidden
        if !followUpContainer.isHidden {
            makeFirstResponder(followUpField)
        }
    }

    @objc private func submitFollowUp() {
        let question = followUpField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        followUpField.stringValue = ""
        followUpContainer.isHidden = true
        navContainer.isHidden = false
        onFollowUp?(originalText, question)
    }

    // MARK: - Keyboard handling

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:  // Esc
            if !followUpContainer.isHidden {
                // Close follow-up field, return to nav
                followUpField.stringValue = ""
                followUpContainer.isHidden = true
                navContainer.isHidden = false
                return true
            }
            dismissPanel()
            return true
        case 123:  // Left arrow
            if currentLevel > 0 && !levels.isEmpty {
                currentLevel -= 1
                updateDisplay()
            }
            return true
        case 124:  // Right arrow
            if currentLevel < 4 && !levels.isEmpty {
                currentLevel += 1
                updateDisplay()
            }
            return true
        case 36:  // Enter/Return
            // If follow-up field is active (first responder), let NSTextField handle it
            if let responder = firstResponder, responder === followUpField || (responder as? NSText)?.delegate === followUpField {
                return false
            }
            if followUpContainer.isHidden && !levels.isEmpty {
                toggleFollowUp()
            }
            return true
        case hotkeyKeyCode:  // configured hotkey — let it pass through to spawn new popup
            return false
        default:
            return false
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyEvent(event) {
            super.keyDown(with: event)
        }
    }

    // MARK: - Display

    private func hideNavLabels() {
        for label in navLabels { label.isHidden = true }
    }

    private func showNavLabels() {
        for label in navLabels { label.isHidden = false }
    }

    private func updateDisplay() {
        guard !levels.isEmpty else { return }
        let name = levelNames[currentLevel]
        levelLabel.stringValue = "[ \(name) ] \(currentLevel + 1)/5"
        bodyText.stringValue = levels[currentLevel]
        resizeBodyText()
        showNavLabels()
        scrollView.documentView?.scroll(.zero)
    }

    private func centerOnScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
