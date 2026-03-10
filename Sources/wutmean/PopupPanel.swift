import Cocoa

final class PopupPanel: NSPanel, NSMenuDelegate {
    private let levelNames = ["Plain", "Distill", "Transfer"]
    private var currentLevel = 0
    private var relatedTerms: [String] = []
    private var searchPhrases: [String] = []
    private var originalText = ""

    /// Per-level state for parallel streaming
    enum LevelState { case loading, streaming, complete }
    private var levelTexts: [String] = ["", "", ""]
    private var levelStates: [LevelState] = [.loading, .loading, .loading]
    private var metaLoading = true

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

    // Nav row
    private let navContainer = NSView()
    private var navButtons: [NSButton] = []
    private var navTrackingAreas: [NSTrackingArea] = []

    // Action buttons (keyword row, right-aligned)
    private let copyButton = NSButton()
    private let googleButton = NSButton()
    private let youtubeButton = NSButton()

    // Related concepts row
    private let relatedContainer = NSView()
    private let relatedPrefix = NSTextField(labelWithString: "explore →")
    private var relatedLabels: [NSTextField] = []
    private var relatedTrackingAreas: [NSTrackingArea] = []

    // Keyboard monitor
    private var keyMonitor: Any?

    /// The keyCode of the configured hotkey — let it pass through to spawn new popups
    var hotkeyKeyCode: UInt16 = 122  // default F1, updated by AppDelegate

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

        // Nav hints container
        navContainer.wantsLayer = true
        container.addSubview(navContainer)
        setupNavHints()

        // Action buttons on keyword row
        setupActionButtons(in: container)
    }

    func refreshFonts() {
        levelLabel.font = Theme.displayFont(size: 12, weight: .bold)
        keywordLabel.font = Theme.monoFont(size: 13, weight: .medium)
        bodyText.font = Theme.bodyFont(size: 12)
        for btn in navButtons {
            btn.font = Theme.monoFont(size: 10.5)
        }
        copyButton.font = NSFont.systemFont(ofSize: 13)
        googleButton.font = NSFont.systemFont(ofSize: 13)
        youtubeButton.font = NSFont.systemFont(ofSize: 13)
        relatedPrefix.font = Theme.bodyFont(size: 11, weight: .medium)
        for label in relatedLabels {
            label.font = Theme.bodyFont(size: 11, weight: .medium)
        }
        updateDisplayForCurrentState()
        layoutSubviews()
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
        googleButton.contentTintColor = Theme.textSecondary
        youtubeButton.contentTintColor = Theme.textSecondary
        relatedPrefix.textColor = Theme.textTertiary
        for label in relatedLabels {
            label.textColor = label.stringValue == "·" ? Theme.relatedDot : Theme.relatedText
        }
        updateDisplayForCurrentState()
    }

    private func setupNavHints() {
        let items: [(String, Selector)] = [
            ("← basic", #selector(navSimpler)),
            ("[esc] exit", #selector(dismissPanel)),
            ("abstract →", #selector(navHarder))
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
    }

    private func setupActionButtons(in container: NSView) {
        let buttons: [(NSButton, String, String, Selector)] = [
            (copyButton, "doc.on.doc", "Copy explanation", #selector(actionCopy)),
            (googleButton, "magnifyingglass", "Search Google", #selector(actionGoogle)),
            (youtubeButton, "play.rectangle", "Search YouTube", #selector(actionYouTube))
        ]

        for (btn, symbolName, label, action) in buttons {
            btn.bezelStyle = .inline
            btn.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
            btn.title = ""
            btn.imagePosition = .imageOnly
            btn.font = NSFont.systemFont(ofSize: 13)
            btn.isBordered = false
            btn.contentTintColor = Theme.textSecondary
            btn.wantsLayer = true
            btn.setAccessibilityLabel(label)
            btn.setAccessibilityRole(.button)
            btn.target = self
            btn.action = action
            btn.isHidden = true
            container.addSubview(btn)
        }
    }

    private var actionTrackingAreas: [NSTrackingArea] = []

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

        // Action button hover tracking
        guard let container = contentView else { return }
        for area in actionTrackingAreas { container.removeTrackingArea(area) }
        actionTrackingAreas.removeAll()
        for btn in [copyButton, googleButton, youtubeButton] {
            let area = NSTrackingArea(
                rect: btn.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["actionButton": btn]
            )
            container.addTrackingArea(area)
            actionTrackingAreas.append(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let label = event.trackingArea?.userInfo?["label"] as? NSTextField {
            label.textColor = Theme.relatedHover
            NSCursor.pointingHand.push()
        } else if let btn = event.trackingArea?.userInfo?["actionButton"] as? NSButton {
            btn.contentTintColor = Theme.accent
            NSCursor.pointingHand.push()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let label = event.trackingArea?.userInfo?["label"] as? NSTextField {
            label.textColor = Theme.relatedText
            NSCursor.pop()
        } else if let btn = event.trackingArea?.userInfo?["actionButton"] as? NSButton {
            btn.contentTintColor = Theme.textSecondary
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
        if currentLevel > 0 { switchToLevel(currentLevel - 1) }
    }

    @objc private func navHarder() {
        if currentLevel < 2 { switchToLevel(currentLevel + 1) }
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    // MARK: - Action buttons

    @objc private func actionCopy() {
        guard levelStates[currentLevel] == .complete else { return }
        let text = levelTexts[currentLevel]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Visual feedback: swap icon to checkmark briefly
        let originalImage = copyButton.image
        let originalColor = copyButton.contentTintColor
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        copyButton.contentTintColor = Theme.success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.image = originalImage
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

        // Keyword label below header (leave room for action buttons on right)
        let keywordGap: CGFloat = 12
        let keywordFont = keywordLabel.font ?? Theme.monoFont(size: 13, weight: .medium)
        let keywordH = ceil(keywordFont.ascender - keywordFont.descender + keywordFont.leading) + 4
        let actionButtonsWidth: CGFloat = 3 * 28 + 4  // 3 buttons × 28pt + gaps
        keywordLabel.frame = NSRect(x: 10, y: h - headerH - keywordGap - keywordH, width: w - 20 - actionButtonsWidth, height: keywordH)

        // Action buttons — right-aligned on keyword row
        let btnW: CGFloat = 28
        let keywordMidY = keywordLabel.frame.midY
        let actionY = keywordMidY - btnW / 2
        youtubeButton.frame = NSRect(x: w - 10 - btnW, y: actionY, width: btnW, height: btnW)
        googleButton.frame = NSRect(x: youtubeButton.frame.minX - btnW, y: actionY, width: btnW, height: btnW)
        copyButton.frame = NSRect(x: googleButton.frame.minX - btnW, y: actionY, width: btnW, height: btnW)

        // Bottom section: 2 rows, 8px bottom padding, 6px between rows
        let navY: CGFloat = 8
        let relatedY: CGFloat = navY + 18 + 6
        let separatorY: CGFloat = relatedY + 18 + 6
        let scrollBottom: CGFloat = separatorY + 1 + 8  // increased gap above separator

        // More breathing room between keyword and body
        let scrollTop = h - headerH - (keywordLabel.isHidden ? 10 : keywordGap + keywordH + 12)
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
        self.levelTexts = ["", "", ""]
        self.levelStates = [.loading, .loading, .loading]
        self.metaLoading = true
        self.relatedTerms = []
        self.searchPhrases = []
        self.currentLevel = defaultLevel
        self.pendingTokens = ""
        self.flushTimer?.cancel()
        self.flushTimer = nil
        navContainer.isHidden = false
        relatedContainer.isHidden = true
        isStreamingActive = true
        bodyText.isSelectable = false
        let name = levelNames[defaultLevel]
        levelLabel.stringValue = "wutmean? · \(name) · \(defaultLevel + 1)/3"

        keywordLabel.isHidden = text.isEmpty
        bodyText.stringValue = ""
        startCursorBlink()
        applyDynamicSize()

        // Truncate keyword after layout so label frame width is known
        if !text.isEmpty {
            let display = truncateKeywordToFit(text)
            keywordLabel.stringValue = "> \(display)"
        }
        showNavLabels()
        copyButton.isHidden = true
        googleButton.isHidden = true
        youtubeButton.isHidden = true
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
        levelLabel.stringValue = "wutmean? · MAX DEPTH"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.levelLabel.stringValue = original
        }
    }

    func appendStreamToken(_ token: String) {
        appendLevelToken(currentLevel, token)
    }

    func appendLevelToken(_ level: Int, _ token: String) {
        guard level >= 0 && level < 3 else { return }
        if levelStates[level] == .loading {
            levelStates[level] = .streaming
        }
        if level == currentLevel {
            pendingTokens += token
            scheduleFlush()
        } else {
            levelTexts[level] += token
        }
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
        levelTexts[currentLevel] += pendingTokens
        pendingTokens = ""
        var text = levelTexts[currentLevel]
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
        for (i, text) in result.levels.enumerated() where i < 3 {
            completeLevelStreaming(i, text: text)
        }
        setMetaResults(relatedTerms: result.relatedTerms, searchPhrases: result.searchPhrases)
    }

    func completeLevelStreaming(_ level: Int, text: String) {
        guard level >= 0 && level < 3 else { return }
        levelTexts[level] = text.isEmpty ? "No explanation available." : text
        levelStates[level] = .complete
        if level == currentLevel {
            pendingTokens = ""
            flushTimer?.cancel()
            flushTimer = nil
            updateDisplayForCurrentState()
        }
    }

    func setMetaResults(relatedTerms: [String], searchPhrases: [String]) {
        self.relatedTerms = relatedTerms
        self.searchPhrases = searchPhrases
        self.metaLoading = false
        layoutRelatedLabels()
        googleButton.isHidden = searchPhrases.isEmpty
        youtubeButton.isHidden = searchPhrases.isEmpty
    }

    private func switchToLevel(_ newLevel: Int) {
        guard newLevel != currentLevel, newLevel >= 0, newLevel < 3 else { return }
        // Flush pending tokens for current level
        if !pendingTokens.isEmpty {
            levelTexts[currentLevel] += pendingTokens
            pendingTokens = ""
        }
        flushTimer?.cancel()
        flushTimer = nil
        currentLevel = newLevel
        updateDisplayForCurrentState()
    }

    func showError(_ message: String) {
        stopCursorBlink()
        isStreamingActive = false
        bodyText.isSelectable = true
        flushTimer?.cancel()
        flushTimer = nil
        pendingTokens = ""
        levelTexts = ["", "", ""]
        levelStates = [.loading, .loading, .loading]
        levelLabel.stringValue = "wutmean? · ERROR"
        bodyText.allowsEditingTextAttributes = false
        bodyText.stringValue = message
        resizeBodyText()
        relatedContainer.isHidden = true
        copyButton.isHidden = true
        googleButton.isHidden = true
        youtubeButton.isHidden = true
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
        levelTexts = ["", "", ""]
        levelStates = [.loading, .loading, .loading]
        metaLoading = true
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
            if currentLevel > 0 {
                switchToLevel(currentLevel - 1)
            }
            return true
        case 124:  // Right arrow
            if currentLevel < 2 {
                switchToLevel(currentLevel + 1)
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
        updateDisplayForCurrentState()
    }

    private func updateDisplayForCurrentState() {
        let name = levelNames[currentLevel]
        levelLabel.stringValue = "wutmean? · \(name) · \(currentLevel + 1)/3"

        switch levelStates[currentLevel] {
        case .loading:
            bodyText.allowsEditingTextAttributes = false
            bodyText.isSelectable = false
            bodyText.stringValue = cursorVisible ? "▌" : ""
            isStreamingActive = true
            if cursorTimer == nil { startCursorBlink() }
        case .streaming:
            bodyText.allowsEditingTextAttributes = false
            bodyText.isSelectable = false
            var text = levelTexts[currentLevel]
            if cursorVisible { text += "▌" }
            bodyText.stringValue = text
            isStreamingActive = true
            if cursorTimer == nil { startCursorBlink() }
        case .complete:
            isStreamingActive = levelStates.contains(where: { $0 != .complete })
            if !isStreamingActive { stopCursorBlink() }
            bodyText.isSelectable = true
            if currentLevel == 2 {
                bodyText.allowsEditingTextAttributes = true
                bodyText.attributedStringValue = styledExamplesText(content: levelTexts[currentLevel])
            } else {
                bodyText.allowsEditingTextAttributes = false
                bodyText.stringValue = levelTexts[currentLevel]
            }
        }

        copyButton.isHidden = (levelStates[currentLevel] != .complete)
        googleButton.isHidden = metaLoading || searchPhrases.isEmpty
        youtubeButton.isHidden = metaLoading || searchPhrases.isEmpty
        resizeBodyText()
        showNavLabels()
        if levelStates[currentLevel] == .complete {
            scrollToTop()
        }
    }

    private func scrollToTop() {
        guard let documentView = scrollView.documentView else { return }
        let topY = max(0, documentView.frame.height - scrollView.contentSize.height)
        documentView.scroll(NSPoint(x: 0, y: topY))
    }

    /// Style Level 3 (Examples) with quoted lines in primary color and explanations in muted color.
    /// Handles format variations across Claude, OpenAI, and Gemini models.
    private func styledExamplesText(content: String) -> NSAttributedString {
        let quoteFont = Theme.bodyFont(size: 12)
        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: quoteFont,
            .foregroundColor: Theme.textPrimary
        ]
        let explainAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.bodyFont(size: 11.5, weight: .regular),
            .foregroundColor: Theme.exampleExplainText
        ]

        // Parse into example blocks — each has a sentence (quote) and explanation
        let examples = parseExamples(content)
        let result = NSMutableAttributedString()

        for (i, example) in examples.prefix(3).enumerated() {
            // Spacing between examples
            if i > 0 {
                let spacer = NSMutableParagraphStyle()
                spacer.paragraphSpacingBefore = 16
                var spacedAttrs = quoteAttrs
                spacedAttrs[.paragraphStyle] = spacer
                result.append(NSAttributedString(string: "\n" + example.sentence, attributes: spacedAttrs))
            } else {
                result.append(NSAttributedString(string: example.sentence, attributes: quoteAttrs))
            }

            if !example.explanation.isEmpty {
                result.append(NSAttributedString(string: "\n" + example.explanation, attributes: explainAttrs))
            }
        }

        return result
    }

    private struct Example {
        let sentence: String
        let explanation: String
    }

    /// Parse level 3 content into example pairs, handling all model output formats
    private func parseExamples(_ content: String) -> [Example] {
        // Strategy 1: split on blank lines (standard format from all providers)
        let paragraphs = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 3 {
            return paragraphs.map { parseSingleExample($0) }
        }

        // Strategy 2: no blank lines — split into line pairs
        let lines = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Check if lines alternate: quote, explanation, quote, explanation...
        let hasQuotes = lines.contains { $0.hasPrefix("\"") }
        if hasQuotes {
            // Group by quote boundaries — each quote starts a new example
            var examples: [Example] = []
            var currentSentence = ""
            var currentExplain: [String] = []
            for line in lines {
                if line.hasPrefix("\"") {
                    if !currentSentence.isEmpty {
                        examples.append(Example(sentence: currentSentence, explanation: currentExplain.joined(separator: "\n")))
                    }
                    currentSentence = line
                    currentExplain = []
                } else {
                    currentExplain.append(line)
                }
            }
            if !currentSentence.isEmpty {
                examples.append(Example(sentence: currentSentence, explanation: currentExplain.joined(separator: "\n")))
            }
            return examples
        }

        // Strategy 3: no quotes, no blank lines — pair every 2 lines
        if lines.count >= 6 {
            var examples: [Example] = []
            var i = 0
            while i + 1 < lines.count {
                examples.append(Example(sentence: lines[i], explanation: lines[i + 1]))
                i += 2
            }
            return examples
        }

        // Fallback: treat each line as its own block
        return lines.map { Example(sentence: $0, explanation: "") }
    }

    /// Parse a single paragraph into sentence + explanation
    private func parseSingleExample(_ paragraph: String) -> Example {
        let lines = paragraph.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return Example(sentence: "", explanation: "") }

        // First line (possibly quoted) is the sentence, rest is explanation
        let sentence = lines[0]
        let explanation = lines.dropFirst().joined(separator: "\n")
        return Example(sentence: sentence, explanation: explanation)
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
