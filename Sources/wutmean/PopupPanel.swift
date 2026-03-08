import Cocoa

final class PopupPanel: NSPanel, NSMenuDelegate {
    private let levelNames = ["Plain", "Technical", "Examples"]
    private var currentLevel = 0
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
    private let scrollView = NSScrollView()

    // Blinking cursor for loading and streaming states
    private var cursorTimer: Timer?
    private var cursorVisible = true
    private var isStreamingActive = false

    // Bloomberg-style header band
    private let headerBand = NSView()

    // Separator line between body and bottom section
    private let separatorLine = NSView()

    // Nav row (includes copy icon and overflow menu trigger)
    private let navContainer = NSView()
    private var navButtons: [NSButton] = []
    private var navTrackingAreas: [NSTrackingArea] = []
    private let copyButton = NSButton()
    private let overflowButton = NSButton()
    private let overflowMenu = NSMenu()

    // Related concepts row
    private let relatedContainer = NSView()
    private let relatedPrefix = NSTextField(labelWithString: "explore →")
    private var relatedLabels: [NSTextField] = []
    private var relatedTrackingAreas: [NSTrackingArea] = []

    // Keyboard monitor
    private var keyMonitor: Any?

    /// The keyCode of the configured hotkey — let it pass through to spawn new popups
    var hotkeyKeyCode: UInt16 = 96  // default F5, updated by AppDelegate

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
        setAccessibilityLabel("wutmean")

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

        // Bloomberg-style header band
        headerBand.wantsLayer = true
        headerBand.layer?.backgroundColor = Theme.headerBackground.cgColor
        container.addSubview(headerBand)

        // Close button — sits on the header band
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.title = ""
        closeButton.imagePosition = .imageOnly
        closeButton.font = Theme.monoFont(size: 12, weight: .bold)
        closeButton.isBordered = false
        closeButton.contentTintColor = Theme.headerText
        closeButton.setAccessibilityLabel("Close")
        closeButton.setAccessibilityRole(.button)
        closeButton.target = self
        closeButton.action = #selector(dismissPanel)
        container.addSubview(closeButton)

        // Settings gear button — sits on the header band
        settingsButton.bezelStyle = .inline
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.title = ""
        settingsButton.imagePosition = .imageOnly
        settingsButton.font = Theme.monoFont(size: 12, weight: .bold)
        settingsButton.isBordered = false
        settingsButton.contentTintColor = Theme.headerText
        settingsButton.setAccessibilityLabel("Settings")
        settingsButton.setAccessibilityRole(.button)
        settingsButton.target = self
        settingsButton.action = #selector(openSettingsAction)
        container.addSubview(settingsButton)

        // Level label — on the header band, dark text on orange
        levelLabel.font = Theme.displayFont(size: 12, weight: .bold)
        levelLabel.textColor = Theme.headerText
        container.addSubview(levelLabel)

        // Keyword label — below the header band
        keywordLabel.font = Theme.monoFont(size: 13, weight: .medium)
        keywordLabel.textColor = Theme.accent
        keywordLabel.lineBreakMode = .byClipping
        keywordLabel.isHidden = true
        container.addSubview(keywordLabel)

        // Body text
        bodyText.isEditable = false
        bodyText.isSelectable = false
        bodyText.drawsBackground = false
        bodyText.isBordered = false
        bodyText.textColor = Theme.textPrimary
        bodyText.font = Theme.bodyFont(size: 12)
        bodyText.lineBreakMode = .byWordWrapping
        bodyText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = bodyText
        scrollView.setAccessibilityLabel("Explanation content")
        container.addSubview(scrollView)

        // Separator line
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = Theme.separator.cgColor
        container.addSubview(separatorLine)

        // Related concepts container
        relatedContainer.wantsLayer = true
        relatedContainer.layer?.masksToBounds = true
        relatedContainer.isHidden = true
        relatedPrefix.font = Theme.bodyFont(size: 11, weight: .medium)
        relatedPrefix.textColor = Theme.textTertiary
        relatedContainer.addSubview(relatedPrefix)
        container.addSubview(relatedContainer)

        // Nav hints container (includes copy + overflow)
        navContainer.wantsLayer = true
        container.addSubview(navContainer)
        setupNavHints()

        // Overflow menu for search actions
        setupOverflowMenu()
    }

    func refreshTheme() {
        guard let container = contentView else { return }
        container.layer?.backgroundColor = Theme.panelBackground.cgColor
        container.layer?.borderColor = Theme.panelBorder.cgColor
        headerBand.layer?.backgroundColor = Theme.headerBackground.cgColor
        separatorLine.layer?.backgroundColor = Theme.separator.cgColor
        closeButton.contentTintColor = Theme.headerText
        settingsButton.contentTintColor = Theme.headerText
        levelLabel.textColor = Theme.headerText
        keywordLabel.textColor = Theme.accent
        bodyText.textColor = Theme.textPrimary
        for btn in navButtons { btn.contentTintColor = Theme.textSecondary }
        copyButton.contentTintColor = Theme.textSecondary
        overflowButton.contentTintColor = Theme.textSecondary
        relatedPrefix.textColor = Theme.textTertiary
        for label in relatedLabels {
            label.textColor = label.stringValue == "·" ? Theme.relatedDot : Theme.relatedText
        }
        if !levels.isEmpty { updateDisplay() }
    }

    private func setupNavHints() {
        let items: [(String, Selector)] = [
            ("← simpler", #selector(navSimpler)),
            ("[esc] exit", #selector(dismissPanel)),
            ("harder →", #selector(navHarder))
        ]

        for (title, action) in items {
            let btn = NSButton(title: title, target: self, action: action)
            btn.font = Theme.monoFont(size: 10.5)
            btn.isBordered = false
            btn.contentTintColor = Theme.textSecondary
            btn.wantsLayer = true
            btn.setAccessibilityLabel(title)
            navContainer.addSubview(btn)
            navButtons.append(btn)
        }

        // Copy button
        copyButton.title = "⎘"
        copyButton.font = Theme.monoFont(size: 14)
        copyButton.isBordered = false
        copyButton.contentTintColor = Theme.textSecondary
        copyButton.wantsLayer = true
        copyButton.alignment = .center
        copyButton.setAccessibilityLabel("Copy explanation")
        copyButton.target = self
        copyButton.action = #selector(actionCopy)
        navContainer.addSubview(copyButton)

        // Overflow button
        overflowButton.title = "⋯"
        overflowButton.font = Theme.monoFont(size: 14)
        overflowButton.isBordered = false
        overflowButton.contentTintColor = Theme.textSecondary
        overflowButton.wantsLayer = true
        overflowButton.alignment = .center
        overflowButton.setAccessibilityLabel("More actions")
        overflowButton.target = self
        overflowButton.action = #selector(showOverflowMenu(_:))
        navContainer.addSubview(overflowButton)
    }

    private func setupOverflowMenu() {
        overflowMenu.addItem(withTitle: "Google", action: #selector(actionGoogle), keyEquivalent: "")
        overflowMenu.addItem(withTitle: "YouTube", action: #selector(actionYouTube), keyEquivalent: "")
        for item in overflowMenu.items { item.target = self }
    }

    @objc private func showOverflowMenu(_ sender: Any?) {
        overflowMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.height + 4), in: overflowButton)
    }

    private func installTrackingAreas() {
        // Related tracking areas (nav buttons handle hover natively)
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
            label.textColor = Theme.relatedHover
            NSCursor.pointingHand.push()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let label = event.trackingArea?.userInfo?["label"] as? NSTextField {
            label.textColor = Theme.relatedText
            NSCursor.pop()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let relPoint = relatedContainer.convert(event.locationInWindow, from: nil)
        for label in relatedLabels where label.stringValue != "·" {
            if label.frame.contains(relPoint) {
                label.alphaValue = 0.5
                super.mouseDown(with: event)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        for label in relatedLabels where label.stringValue != "·" {
            label.alphaValue = 1.0
        }
        super.mouseUp(with: event)
    }

    @objc private func navSimpler() {
        if currentLevel > 0 { currentLevel -= 1; updateDisplay() }
    }

    @objc private func navHarder() {
        if currentLevel < 2 { currentLevel += 1; updateDisplay() }
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
        let originalTitle = copyButton.title
        let originalColor = copyButton.contentTintColor
        copyButton.title = "✓"
        copyButton.contentTintColor = Theme.success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = originalTitle
            self?.copyButton.contentTintColor = originalColor
        }
    }

    @objc private func actionGoogle() {
        openSearch("https://www.google.com/search?q=", query: smartSearchQuery())
    }

    @objc private func actionYouTube() {
        openSearch("https://www.youtube.com/results?search_query=", query: smartSearchQuery())
    }

    /// Build a contextual search query: use first search phrase if available, else original text
    private func smartSearchQuery() -> String {
        if let first = searchPhrases.first, !first.isEmpty {
            return "\"\(originalText)\" \(first)"
        }
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

        // Header band — full-width orange strip at top
        let headerH: CGFloat = 28
        headerBand.frame = NSRect(x: 0, y: h - headerH, width: w, height: headerH)

        // Controls on header band — 44pt hit targets extending below band
        let btnSize: CGFloat = 44
        let btnY = h - headerH + (headerH - btnSize) / 2
        closeButton.frame = NSRect(x: w - btnSize - 2, y: btnY, width: btnSize, height: btnSize)
        settingsButton.frame = NSRect(x: w - btnSize * 2 - 2, y: btnY, width: btnSize, height: btnSize)
        levelLabel.frame = NSRect(x: 10, y: h - headerH + 4, width: 300, height: 20)

        // Keyword label below header — increased gap (12px instead of 6px)
        let keywordGap: CGFloat = 12
        keywordLabel.frame = NSRect(x: 10, y: h - headerH - keywordGap - 18, width: w - 20, height: 18)

        // Bottom section: 2 rows, 8px bottom padding, 6px between rows
        let navY: CGFloat = 8
        let relatedY: CGFloat = navY + 18 + 6
        let separatorY: CGFloat = relatedY + 18 + 6
        let scrollBottom: CGFloat = separatorY + 1 + 8  // increased gap above separator

        // More breathing room between keyword and body (16px gap after keyword)
        let scrollTop = h - headerH - (keywordLabel.isHidden ? 10 : keywordGap + 18 + 12)
        scrollView.frame = NSRect(x: 10, y: scrollBottom, width: w - 20, height: scrollTop - scrollBottom)

        // Separator line
        separatorLine.frame = NSRect(x: 10, y: separatorY, width: w - 20, height: 1)

        // Related concepts row
        relatedContainer.frame = NSRect(x: 10, y: relatedY, width: w - 20, height: 18)

        // Nav hints row
        navContainer.frame = NSRect(x: 10, y: navY, width: w - 20, height: 18)
        layoutNavLabels()

        resizeBodyText()
    }

    private func layoutNavLabels() {
        let spacing: CGFloat = 20
        var totalWidth: CGFloat = 0
        for btn in navButtons {
            btn.sizeToFit()
            totalWidth += btn.frame.width
        }
        totalWidth += spacing * CGFloat(navButtons.count - 1)

        // Center the nav hints
        var x = (navContainer.frame.width - totalWidth) / 2
        for btn in navButtons {
            btn.frame = NSRect(x: x, y: 0, width: btn.frame.width, height: 18)
            x += btn.frame.width + spacing
        }

        // Right-align copy + overflow icons with 44x44 hit area (M2)
        let iconSize: CGFloat = 44
        let rightEdge = navContainer.frame.width
        let iconY = (18 - iconSize) / 2  // vertically center in nav row
        overflowButton.frame = NSRect(x: rightEdge - iconSize, y: iconY, width: iconSize, height: iconSize)
        copyButton.frame = NSRect(x: overflowButton.frame.minX - iconSize, y: iconY, width: iconSize, height: iconSize)

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
                let dot = NSTextField(labelWithString: "·")
                dot.font = Theme.bodyFont(size: 11, weight: .medium)
                dot.textColor = Theme.relatedDot
                dot.isSelectable = false
                relatedContainer.addSubview(dot)
                relatedLabels.append(dot)
            }

            let label = NSTextField(labelWithString: term)
            label.font = Theme.bodyFont(size: 11, weight: .medium)
            label.textColor = Theme.relatedText
            label.isSelectable = false
            label.wantsLayer = true
            relatedContainer.addSubview(label)
            relatedLabels.append(label)

            let click = NSClickGestureRecognizer(target: self, action: #selector(relatedTermClicked(_:)))
            label.addGestureRecognizer(click)
        }

        // Layout: "explore →" prefix + dot-separated terms
        relatedPrefix.sizeToFit()
        let prefixWidth = relatedPrefix.frame.width + 6
        let containerW = relatedContainer.frame.width
        let dotSpacing: CGFloat = 4

        // Measure natural widths
        var totalWidth = prefixWidth
        for label in relatedLabels {
            label.sizeToFit()
            totalWidth += label.frame.width + dotSpacing
        }
        totalWidth -= dotSpacing

        // If overflow, cap each term label to an equal share of available space
        let termLabels = relatedLabels.filter { $0.stringValue != "·" }
        let dotLabels = relatedLabels.filter { $0.stringValue == "·" }
        let dotsWidth = dotLabels.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let termCount = CGFloat(max(1, termLabels.count))
        let spacingOverhead = dotSpacing * CGFloat(relatedLabels.count)
        let maxTermWidth = (containerW - prefixWidth - dotsWidth - spacingOverhead) / termCount

        if totalWidth > containerW {
            for label in termLabels {
                label.frame.size.width = min(label.frame.width, max(30, maxTermWidth))
            }
            // Recalculate total after capping
            totalWidth = prefixWidth
            for label in relatedLabels {
                totalWidth += label.frame.width + dotSpacing
            }
            totalWidth -= dotSpacing
        }

        // Center if fits, left-align if overflows
        var x: CGFloat = totalWidth <= containerW
            ? (containerW - totalWidth) / 2
            : 0
        relatedPrefix.frame = NSRect(x: x, y: 0, width: relatedPrefix.frame.width, height: 16)
        x += prefixWidth

        for label in relatedLabels {
            label.lineBreakMode = .byTruncatingTail
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

    func showLoading(text: String, offsetFrom: NSPoint? = nil, defaultLevel: Int = 0) {
        self.originalText = text
        self.levels = []
        self.relatedTerms = []
        self.currentLevel = defaultLevel
        self.pendingTokens = ""
        self.flushTimer?.cancel()
        self.flushTimer = nil
        navContainer.isHidden = false
        relatedContainer.isHidden = true
        isStreamingActive = true
        bodyText.isSelectable = false
        let name = levelNames[defaultLevel]
        levelLabel.stringValue = "[ \(name) ] \(defaultLevel + 1)/3"

        keywordLabel.isHidden = text.isEmpty
        bodyText.stringValue = ""
        startCursorBlink()
        applyDynamicSize()

        // Truncate keyword after layout so label frame width is known
        if !text.isEmpty {
            let display = truncateKeywordToFit(text)
            keywordLabel.stringValue = "> \(display)"
        }
        showEscOnly()
        copyButton.isHidden = true
        overflowButton.isHidden = true
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
            let display = truncateKeywordToFit(text)
            keywordLabel.stringValue = "> \(display)"
            keywordLabel.isHidden = false
        }
    }

    func showMaxDepthFlash() {
        let original = levelLabel.stringValue
        levelLabel.stringValue = "[ MAX DEPTH ]"
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
        // Strip cursor before appending new tokens
        var text = bodyText.stringValue
        if text.hasSuffix("▌") { text = String(text.dropLast()) }
        text += pendingTokens
        pendingTokens = ""
        // Re-add cursor if blinking
        if isStreamingActive && cursorVisible { text += "▌" }
        bodyText.stringValue = text
        resizeBodyText()
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let documentView = scrollView.documentView else { return }
        let maxY = max(0, documentView.frame.height - scrollView.contentSize.height)
        documentView.scroll(NSPoint(x: 0, y: maxY))
    }

    // MARK: - Blinking cursor

    private func startCursorBlink() {
        stopCursorBlink()
        cursorVisible = true
        updateCursorDisplay()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.cursorVisible.toggle()
            self.updateCursorDisplay()
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorVisible = false
        // Strip trailing cursor
        let text = bodyText.stringValue
        if text.hasSuffix("▌") {
            bodyText.stringValue = String(text.dropLast())
        }
    }

    private func updateCursorDisplay() {
        var text = bodyText.stringValue
        if text.hasSuffix("▌") { text = String(text.dropLast()) }
        if cursorVisible { text += "▌" }
        bodyText.stringValue = text
    }

    func showResult(_ result: Explainer.ExplanationResult) {
        stopCursorBlink()
        isStreamingActive = false
        bodyText.isSelectable = true
        flushPendingTokens()
        self.levels = result.levels
        self.relatedTerms = result.relatedTerms
        self.searchPhrases = result.searchPhrases
        copyButton.isHidden = false
        overflowButton.isHidden = false
        layoutRelatedLabels()
        updateDisplay()
    }

    func showError(_ message: String) {
        stopCursorBlink()
        isStreamingActive = false
        bodyText.isSelectable = true
        flushTimer?.cancel()
        flushTimer = nil
        pendingTokens = ""
        levelLabel.stringValue = "[ ERROR ]"
        bodyText.stringValue = message
        resizeBodyText()
        relatedContainer.isHidden = true
        copyButton.isHidden = true
        overflowButton.isHidden = true
        showEscOnly()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    @objc func dismissPanel() {
        stopCursorBlink()
        isStreamingActive = false
        explainTask?.cancel()
        explainTask = nil
        flushTimer?.cancel()
        flushTimer = nil
        pendingTokens = ""
        orderOut(nil)
        navContainer.isHidden = false
        removeKeyMonitor()
        onDismiss?()
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
            dismissPanel()
            return true
        case 123:  // Left arrow
            if currentLevel > 0 && !levels.isEmpty {
                currentLevel -= 1
                updateDisplay()
            }
            return true
        case 124:  // Right arrow
            if currentLevel < 2 && !levels.isEmpty {
                currentLevel += 1
                updateDisplay()
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
        for label in navButtons { label.isHidden = true }
    }

    private func showNavLabels() {
        for label in navButtons { label.isHidden = false }
    }

    private func showEscOnly() {
        for (i, label) in navButtons.enumerated() {
            label.isHidden = (i != 1)  // only [esc] (index 1)
        }
    }

    private func updateDisplay() {
        guard !levels.isEmpty else { return }
        let name = levelNames[currentLevel]
        levelLabel.stringValue = "[ \(name) ] \(currentLevel + 1)/3"
        if currentLevel == 2 {
            // Examples level needs attributed string for quote vs explanation styling
            bodyText.allowsEditingTextAttributes = true
            bodyText.attributedStringValue = styledExamplesText(content: levels[currentLevel])
        } else {
            bodyText.allowsEditingTextAttributes = false
            bodyText.stringValue = levels[currentLevel]
        }
        resizeBodyText()
        showNavLabels()
        scrollToTop()
    }

    private func scrollToTop() {
        guard let documentView = scrollView.documentView else { return }
        let topY = max(0, documentView.frame.height - scrollView.contentSize.height)
        documentView.scroll(NSPoint(x: 0, y: topY))
    }

    /// Style Level 3 (Examples) with quoted lines in primary color and explanations in muted color
    private func styledExamplesText(content: String) -> NSAttributedString {
        let baseFont = Theme.bodyFont(size: 12)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: Theme.textPrimary
        ]
        let explainColor = Theme.exampleExplainText
        let explainAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.bodyFont(size: 11.5, weight: .regular),
            .foregroundColor: explainColor
        ]

        // Paragraph style with spacing between examples
        let exampleSpacing = NSMutableParagraphStyle()
        exampleSpacing.paragraphSpacingBefore = 12

        let result = NSMutableAttributedString()
        let paragraphs = content.components(separatedBy: "\n\n")

        for (i, paragraph) in paragraphs.enumerated() {
            let lines = paragraph.components(separatedBy: "\n")
            for (j, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                if trimmed.hasPrefix("\"") {
                    var attrs = baseAttrs
                    // Add top spacing before each example's quote (except the first)
                    if i > 0 && j == 0 {
                        let para = NSMutableParagraphStyle()
                        para.paragraphSpacingBefore = 14
                        attrs[.paragraphStyle] = para
                    }
                    result.append(NSAttributedString(string: (result.length > 0 ? "\n" : "") + line, attributes: attrs))
                } else {
                    result.append(NSAttributedString(string: "\n" + line, attributes: explainAttrs))
                }
            }
        }

        return result
    }

    /// Truncate text at word boundary to fit within the given pixel width
    private func truncateKeywordToFit(_ text: String) -> String {
        let font = keywordLabel.font ?? Theme.monoFont(size: 11, weight: .medium)
        let maxWidth = keywordLabel.frame.width
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let prefixed = "> \(text)"

        if (prefixed as NSString).size(withAttributes: attrs).width <= maxWidth {
            return text
        }

        // Find longest word-boundary prefix that fits
        var end = text.count
        while end > 0 {
            let candidate = String(text.prefix(end))
            let display = "> \(candidate)..."
            if (display as NSString).size(withAttributes: attrs).width <= maxWidth {
                if let lastSpace = candidate.lastIndex(of: " ") {
                    return String(candidate[candidate.startIndex..<lastSpace]) + "..."
                }
                return candidate + "..."
            }
            end -= 1
        }
        return "..."
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
