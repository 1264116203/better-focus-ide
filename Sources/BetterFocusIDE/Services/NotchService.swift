// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import Combine

final class NotchService: ObservableObject {
    static let shared = NotchService()
    
    // MARK: - Published State
    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var expanded = false
    @Published private(set) var surfaceSize: CGSize
    @Published private(set) var surfaceShift: CGFloat = 0

    // MARK: - Phase 2: Cards
    let questionController = QuestionController()
    let permissionController = PermissionController()
    // MARK: - Phase 3: Notice
    let noticeController = NoticeController()
    // MARK: - Phase 4: History
    let historyController = HistoryController()
    /// Which card is currently active (question takes priority).
    @Published private(set) var activeCard: ActiveCard = .none
    /// Total pending items across all controllers (drives the collapsed dot).
    @Published private(set) var pendingTotal: Int = 0
    /// Provider tint for the collapsed pending dot.
    @Published private(set) var pendingTint: (r: Double, g: Double, b: Double) = NotchLayout.accentColor
    /// Timestamp when the bell swing animation should start (notification arrival).
    @Published var bellSwingStart: Date?
    /// Card being withdrawn (visible during the collapse animation, then cleared).
    @Published private(set) var closingCard: ActiveCard?

    enum ActiveCard {
        case none, question, permission, notice, history
    }
    
    // MARK: - Private
    private var windowHost: NotchWindowHost?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private let socketServer = AgentEventSocketServer.shared

    // MARK: - Keyboard / pin state
    /// When the island last expanded — drives the anti-mistouch guard window.
    private var expandedAt = Date.distantPast
    /// True while a card is fading out; keys are ignored so an answer can't change.
    private var isClosing = false
    /// Pinned cards stay expanded instead of auto-collapsing ("固定 ⇄ 按需").
    @Published private(set) var pinned = false
    private var keyMonitor: Any?
    /// Wired by AppDelegate so ⌘, opens the settings window.
    var onOpenSettings: (() -> Void)?

    /// Anti-mistouch window (seconds) after a card appears, matching Python's
    /// `CARD_CLICK_GUARD`. A hand resting where "allow" will land can't approve.
    /// Live from Settings (click_guard); 0 disables the guard.
    static var cardClickGuard: TimeInterval { Settings.shared.clickGuard }
    
    /// True while the anti-mistouch guard is active (card just appeared).
    var isClickGuarded: Bool {
        Date().timeIntervalSince(expandedAt) < Self.cardClickGuard
    }
    
    // MARK: - Hover state machine (Python HOVER_EXPAND_DELAY / HOVER_COLLAPSE_DELAY)
    
    /// Delay before hover expands the island (seconds, live from Settings).
    static var hoverExpandDelay: TimeInterval { Settings.shared.hoverExpandDelay }
    /// Delay after mouse exits before auto-collapse (seconds, live from Settings).
    static var hoverCollapseDelay: TimeInterval { Settings.shared.hoverCollapseDelay }
    /// Hold-off after manual collapse in pinned mode (seconds, live from Settings).
    static var manualCollapseHold: TimeInterval { Settings.shared.manualCollapseHold }
    /// History panel auto-close duration (seconds, live from Settings).
    static var historyDuration: TimeInterval { Settings.shared.historyDuration }
    
    private var hovering = false
    private var hoverSince: Date?
    private var hoverExpanded = false
    /// On-demand mode: scheduled collapse time after mouse exit.
    private var collapseAt: Date?
    /// Auto-collapse deadline for transient content (notice/history).
    private var autoCollapseAt: Date?
    /// Saved deadline when hover pauses auto-collapse.
    private var autoCollapseHeld: Date?
    /// Pinned mode: manual collapse hold-off (no re-expand until this passes).
    private var manualCollapseUntil: Date?
    private var hoverTimer: Timer?
    /// Periodic stale-card sweep (Python CARD_SWEEP_INTERVAL / CARD_SWEEP_GRACE).
    private var sweepTimer: Timer?
    private var lastSweepInterval = 0

    private init() {
        // Pin to the notch display, not whatever currently has focus.
        let screen = Self.preferredScreen() ?? NSScreen.screens.first!
        let safeAreaTop = screen.safeAreaInsets.top
        let cameraWidth = Self.detectCameraWidth(screen: screen)
        
        let initialGeometry = NotchGeometry(
            screen: screen.frame,
            safeAreaTop: safeAreaTop,
            cameraWidth: cameraWidth
        )
        
        self.geometry = initialGeometry
        
        // Start with collapsed size
        self.surfaceSize = initialGeometry.restingSize(showsContent: false)
        
        // Observe screen changes
        observeScreenChanges()

        // Wire up controllers
        setupControllers()

        // Live config: re-layout the island whenever a setting changes so edits
        // apply at once (Python settings.on_change), and keep the stale-card
        // sweep running on the configured interval.
        Settings.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSettingsChanged() }
            .store(in: &cancellables)
        startSweepTimer()
    }
    
    // MARK: - Public Methods
    
    func show() {
        if windowHost == nil {
            createWindowHost()
        }
        windowHost?.present(
            size: surfaceSize,
            geometry: geometry,
            animated: false,
            showsContent: expanded
        )
    }
    
    func hide() {
        windowHost?.hide(animated: true)
    }
    
    func toggle() {
        if expanded {
            collapse()
        } else if activeCard != .none {
            // Card showing but collapsed (on-demand mode): expand it.
            expand()
        } else {
            // Idle island: clicking reviews recent notifications.
            showHistory()
        }
    }
    
    func expand() {
        guard !expanded else { return }
        expanded = true
        expandedAt = Date()
        isClosing = false
        let newSize = targetSizeForCurrentCard()
        animateTo(size: newSize)
        syncKeyFocus()
    }
    
    func collapse() {
        guard expanded else { return }
        expanded = false
        isClosing = true
        // Pinned mode: record hold-off so auto-expand doesn't immediately re-open.
        if pinned {
            manualCollapseUntil = Date().addingTimeInterval(Self.manualCollapseHold)
        }
        cancelAutoCollapse()
        collapseAt = nil
        // History and notice are transient: collapsing dismisses them.
        // Question and permission persist (card still awaits the user).
        if activeCard == .history {
            activeCard = .none
        } else if activeCard == .notice {
            noticeController.dismiss()
            activeCard = .none
        }
        let newSize = geometry.restingSize(showsContent: false)
        animateTo(size: newSize)
        syncKeyFocus()
        updatePendingTotal()
        // Clear the closing flag once the fade settles so keys resume next time.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.expanded else { return }
            self.isClosing = false
        }
    }

    /// The panel may take keyboard focus only while a card is on screen, so a
    /// click can make it key and the shortcuts come alive — without ever stealing
    /// focus from the user's editor/terminal on its own.
    private func syncKeyFocus() {
        let cardShowing = expanded && (activeCard == .question || activeCard == .permission)
        windowHost?.panel.acceptsKeyFocus = cardShowing
        if !cardShowing, let panel = windowHost?.panel, panel.isKeyWindow {
            panel.resignKey()
        }
    }

    // MARK: - Socket

    func startSocket() -> AgentEventSocketServer.StartOutcome {
        socketServer.onMessage = { [weak self] message in
            self?.routeSocketMessage(message)
        }
        return socketServer.start()
    }

    func stopSocket() {
        socketServer.stop()
    }
    
    // MARK: - Private Methods
    
    private func createWindowHost() {
        let contentView = AnyView(NotchView(service: self))
        windowHost = NotchWindowHost(
            content: contentView,
            geometry: geometry,
            size: surfaceSize
        )
        windowHost?.setMouseCallbacks(
            enter: { [weak self] in self?.mouseEntered() },
            exit: { [weak self] in self?.mouseExited() },
            move: { [weak self] point in self?.mouseMoved(point) },
            rightClick: { [weak self] point in self?.showContextMenu(at: point) }
        )
        startHoverTimer()
    }
    
    private func animateTo(size: CGSize) {
        surfaceSize = size
        windowHost?.present(
            size: size,
            geometry: geometry,
            animated: true,
            showsContent: expanded
        )
    }
    
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateGeometry()
        }
    }
    
    private func updateGeometry() {
        guard let screen = Self.preferredScreen() else { return }
        let safeAreaTop = screen.safeAreaInsets.top
        let cameraWidth = Self.detectCameraWidth(screen: screen)
        
        geometry = NotchGeometry(
            screen: screen.frame,
            safeAreaTop: safeAreaTop,
            cameraWidth: cameraWidth
        )
        
        if !expanded {
            surfaceSize = geometry.restingSize(showsContent: false)
        }
        
        windowHost?.present(
            size: surfaceSize,
            geometry: geometry,
            animated: false,
            showsContent: expanded
        )
    }
    
    /// The display to pin the island to. Prefers the built-in notch screen
    /// (`safeAreaInsets.top > 0`); falls back to the main screen only when no
    /// notch display exists. Resolved from the full screen list rather than
    /// `NSScreen.main`, so the island stays put instead of hopping to whichever
    /// display currently has keyboard focus.
    private static func preferredScreen() -> NSScreen? {
        if let notch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notch
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func detectCameraWidth(screen: NSScreen) -> CGFloat {
        // Try to read camera width from safe area
        let safeAreaTop = screen.safeAreaInsets.top
        if safeAreaTop > 0 {
            // Has notch - estimate camera width
            return 180
        }
        // No notch - use simulated width
        return 150
    }

    // MARK: - Controller wiring

    private func setupControllers() {
        questionController.onPresent = { [weak self] in
            self?.showCard(.question)
            if let prompt = self?.questionController.prompt {
                self?.historyController.remember(
                    HistoryController.question(prompt: prompt, state: "待回答"))
            }
        }
        questionController.onDismiss = { [weak self] in
            self?.handleCardDismissal()
        }
        permissionController.onPresent = { [weak self] in
            self?.showCard(.permission)
            if let req = self?.permissionController.request {
                self?.historyController.remember(
                    HistoryController.permission(request: req, state: "待审批"))
            }
        }
        permissionController.onDismiss = { [weak self] in
            self?.handleCardDismissal()
        }
        noticeController.onPresent = { [weak self] in
            self?.showNoticeBanner()
        }
        noticeController.onRemember = { [weak self] notice in
            self?.historyController.remember(
                HistoryController.turn(notice: notice, state: "回复完成"))
        }
        noticeController.onDismiss = { [weak self] in
            self?.handleCardDismissal()
        }
        // Suppress the notice banner while an interactive card awaits the user.
        noticeController.hasPendingCard = { [weak self] in
            guard let self else { return false }
            return self.questionController.hasActiveCard
                || self.permissionController.hasActiveCard
        }
        // A pinned banner holds open instead of retracting on its own.
        noticeController.isPinned = { [weak self] in self?.pinned ?? false }
    }

    // MARK: - Phase 4: Install / history

    /// One-click install of both integrations. Returns a human summary.
    @discardableResult
    func installAll() -> String {
        var lines: [String] = []
        do {
            try QoderHookInstaller.install()
            lines.append("✓ Qoder Hook 已安装")
        } catch {
            lines.append("✗ Qoder Hook 失败：\(error.localizedDescription)")
        }
        do {
            try OpenCodePluginInstaller.install()
            lines.append("✓ OpenCode Plugin 已安装")
        } catch {
            lines.append("✗ OpenCode Plugin 失败：\(error.localizedDescription)")
        }
        Log.info("installAll: " + lines.joined(separator: " | "), topic: "install")
        return lines.joined(separator: "\n")
    }

    func uninstallAll() {
        QoderHookInstaller.uninstall()
        OpenCodePluginInstaller.uninstall()
    }

    /// Show the recent-notifications panel (from an idle island).
    func showHistory() {
        // Don't preempt an interactive card for history.
        if activeCard == .question || activeCard == .permission { return }
        activeCard = .history
        pinned = false
        let rows = max(1, historyController.entries.count)
        // Metrics mirror the Python reference (config.HISTORY_*): 12pt inset,
        // 20pt header, 40pt rows with 4pt gaps, 380pt wide. On top we still
        // clear the camera cutout the way our window-at-screen-top needs.
        let content = 12.0 * 2 + 20.0 + 4.0
            + Double(rows) * 40.0 + Double(max(0, rows - 1)) * 4.0
        let height = geometry.safeContentTop + content
        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
        }
        animateTo(size: CGSize(width: NotchLayout.historyWidth, height: height))
        syncKeyFocus()
        // History auto-closes after 8s (Python HISTORY_DURATION).
        scheduleAutoCollapse(after: Self.historyDuration)
    }

    /// Show the transient turn-finished banner at a compact height.
    private func showNoticeBanner() {
        activeCard = .notice
        pinned = Settings.shared.pinByDefault
        bellSwingStart = Date()  // Trigger bell swing animation.
        let bannerSize = CGSize(width: NotchLayout.expandedWidth,
                                height: NotchLayout.expandedHeight)
        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
        }
        animateTo(size: bannerSize)
        syncKeyFocus()
        updatePendingTotal()
        // Auto-collapse after the configured duration (unless pinned).
        scheduleAutoCollapse(after: Settings.shared.notifyBannerDuration)
    }

    private func showCard(_ card: ActiveCard) {
        activeCard = card
        pinned = Settings.shared.pinByDefault
        FeedbackService.onArrive()
        
        if pinned {
            // Pinned mode: always expand immediately.
            if !expanded {
                expanded = true
                expandedAt = Date()
                isClosing = false
            }
            animateTo(size: targetSizeForCurrentCard())
        } else {
            // On-demand mode: expand only if hovering; otherwise stay collapsed.
            if hovering {
                if !expanded {
                    expanded = true
                    expandedAt = Date()
                    isClosing = false
                }
                animateTo(size: targetSizeForCurrentCard())
            }
            // If not hovering, the card stays queued. Hover-expand will trigger
            // via tickHoverTimer when the mouse enters.
        }
        syncKeyFocus()
        updatePendingTotal()
    }

    private func handleCardDismissal() {
        // Check if any controller still has an active card
        if questionController.hasActiveCard {
            activeCard = .question
            animateTo(size: targetSizeForCurrentCard())
        } else if permissionController.hasActiveCard {
            activeCard = .permission
            animateTo(size: targetSizeForCurrentCard())
        } else if noticeController.hasActiveNotice {
            activeCard = .notice
        } else {
            // No more content: play withdrawal animation then collapse.
            closingCard = activeCard
            activeCard = .none
            if expanded {
                expanded = false
                isClosing = true
                cancelAutoCollapse()
                collapseAt = nil
                let newSize = geometry.restingSize(showsContent: false)
                animateTo(size: newSize)
                syncKeyFocus()
                // Clear closing card once animation settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    guard let self else { return }
                    self.closingCard = nil
                    self.isClosing = false
                }
            } else {
                closingCard = nil
            }
        }
        syncKeyFocus()
        updatePendingTotal()
    }
    
    // MARK: - Card size computation
    
    /// Compute the target size for the currently active card (aligned with Python).
    private func targetSizeForCurrentCard() -> CGSize {
        switch activeCard {
        case .question:
            return CGSize(width: NotchLayout.questionCardWidth,
                          height: questionCardHeight())
        case .permission:
            return CGSize(width: NotchLayout.questionCardWidth,
                          height: permissionCardHeight())
        case .notice:
            return CGSize(width: NotchLayout.expandedWidth,
                          height: NotchLayout.expandedHeight)
        case .history:
            let rows = max(1, historyController.entries.count)
            let content = 12.0 * 2 + 20.0 + 4.0
                + Double(rows) * 40.0 + Double(max(0, rows - 1)) * 4.0
            let height = geometry.safeContentTop + content
            return CGSize(width: NotchLayout.historyWidth, height: height)
        case .none:
            // Idle: shouldn't be expanded; return minimal size.
            return CGSize(width: NotchLayout.expandedWidth,
                          height: NotchLayout.expandedHeight)
        }
    }
    
    /// Question card height (mirrors Python QuestionCard.total_height).
    private func questionCardHeight() -> CGFloat {
        let q = questionController.prompt
        let textWidth = NotchLayout.questionCardWidth - NotchLayout.cardInset * 2
        // Outer .padding(.vertical, 10) = 20; header badge tightly fits 18pt.
        var height: CGFloat = 20 + 18

        let body = q?.question.question ?? "Agent has a question for you:"
        // Each body line: fontSize * 1.3 (SwiftUI system font default line height).
        let bodyLineH = NotchLayout.questionBodyFont * 1.3
        let bodyLines = ceil(bodyHeight(body, width: textWidth - 36, font: NotchLayout.questionBodyFont)
                             / bodyLineH)
        let clampedLines = min(bodyLines, CGFloat(NotchLayout.questionMaxBodyLines))
        // VStack(spacing: 8) between header and body.
        height += 8 + clampedLines * bodyLineH

        // Option rows: .padding(.vertical, 7) × 2 = 14 + option label (fontSize*1.3).
        // Desc text can add extra, so use a conservative single-desc-line bump.
        let optionRowH = NotchLayout.questionOptionRowMin
        let optionCount = CGFloat(q?.question.options.count ?? 0)
        var optionsH: CGFloat = 0
        if optionCount > 0 {
            // Each option inside VStack(spacing: 6); baseline = optionRowH.
            optionsH = optionCount * optionRowH + max(0, optionCount - 1) * 6
            // Assume at least one option has a description → 2 extra lines per option.
            // (A real text-measure would read actual desc texts; this is a safe heuristic.)
            let descBump = optionCount * NotchLayout.questionBodyFont * 0.7
            optionsH += descBump
        }
        // Other row: 14 padding + label + possible text field (height 26)
        let otherH: CGFloat = (questionController.writingOwn.contains(q?.question.id ?? "")
            ? (optionRowH + 26) : optionRowH)
        // VStack(spacing: 8) between body and ScrollView, and inside ScrollView's VStack(spacing: 6)
        // between options and other row.
        height += 8 + optionsH + 6 + otherH
        // VStack(spacing: 8) between ScrollView and send button.
        height += 8 + NotchLayout.questionSendHeight

        // Floor the content height at card_min_height (0 = fit content exactly).
        height = max(height, CGFloat(Settings.shared.cardMinHeight))
        // Add safeContentTop for our window-at-screen-top geometry.
        return height + geometry.safeContentTop
    }
    
    /// Permission card height (mirrors Python PermissionCard.total_height).
    private func permissionCardHeight() -> CGFloat {
        let p = permissionController.request
        let textWidth = NotchLayout.questionCardWidth - NotchLayout.cardInset * 2
        // Outer .padding(.vertical, 10) = 20; header badge tightly fits 18pt.
        var height: CGFloat = 20 + 18

        // Prompt line: "Agent(xxx) 请求执行「title」，是否允许？" — single 11pt text,
        // wrapped with fixedSize so it can take multiple lines.
        let agent = p?.agent.isEmpty ?? true ? "" : "（\(p!.agent)）"
        let promptText = "Agent\(agent) 请求执行「\(p?.toolName ?? "Permission")」，是否允许？"
        let promptLines = ceil(bodyHeight(promptText, width: textWidth, font: 11) / (11 * 1.3))
        // VStack(spacing: 8) between header and body text.
        height += 8 + promptLines * 11 * 1.3

        let detail = p?.detail ?? ""
        if !detail.isEmpty {
            // Detail block: .font(.system(size: 10, monospaced)), .padding(10,8)*2 = 20+16,
            // background RoundedRectangle, .lineLimit(4).
            let detailLines = min(ceil(bodyHeight(detail, width: textWidth - 16, font: 10) / (10 * 1.3)), 4)
            // VStack(spacing: 2) for detail header + detail text.
            height += 8 + 16 + detailLines * 10 * 1.3 + 16
        }

        // VStack(spacing: 8) before buttons, button height 28 (permissionButtonHeight=32 → use actual 28).
        height += 8 + 28

        // Floor the content height at card_min_height (0 = fit content exactly).
        height = max(height, CGFloat(Settings.shared.cardMinHeight))
        return height + geometry.safeContentTop
    }
    
    /// Approximate text height given a width and font size (single-line height = fontSize * 1.3).
    private func bodyHeight(_ text: String, width: CGFloat, font: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return font * 1.3 }
        let lineHeight = font * 1.3
        // Rough char-width estimate for mixed CJK/Latin.
        let avgCharWidth = font * 0.6
        let charsPerLine = max(1, Int(width / avgCharWidth))
        let lines = max(1, CGFloat(text.count) / CGFloat(charsPerLine))
        return ceil(lines) * lineHeight
    }
    
    // MARK: - Pending total
    
    /// Recompute the total pending items (drives collapsed dot appearance).
    private func updatePendingTotal() {
        let total = questionController.count + permissionController.count + noticeController.count
        pendingTotal = total
        // Tint from the highest-priority pending provider.
        if questionController.count > 0 {
            pendingTint = questionController.pendingTint ?? NotchLayout.accentColor
        } else if permissionController.count > 0 {
            pendingTint = permissionController.pendingTint ?? NotchLayout.accentColor
        } else if noticeController.count > 0 {
            pendingTint = noticeController.pendingTint ?? NotchLayout.accentColor
        } else {
            pendingTint = NotchLayout.accentColor
        }
    }
    
    // MARK: - Hover state machine
    
    private func mouseEntered() {
        hovering = true
        hoverSince = Date()
        // Pause auto-collapse while hovering.
        if let deadline = autoCollapseAt {
            autoCollapseHeld = deadline
            autoCollapseAt = nil
        }
        // On-demand mode: schedule delayed expand if collapsed with pending content.
        if !pinned && !expanded && activeCard != .none {
            // hoverExpandDelay checked in tickHoverTimer
        }
        ensureHoverTimer()
    }
    
    private func mouseExited() {
        hovering = false
        hoverSince = nil
        hoverExpanded = false
        // Restore auto-collapse deadline.
        if let held = autoCollapseHeld {
            autoCollapseAt = held
            autoCollapseHeld = nil
        }
        // On-demand: schedule delayed collapse if expanded by hover.
        if !pinned && expanded && activeCard != .question && activeCard != .permission {
            collapseAt = Date().addingTimeInterval(Self.hoverCollapseDelay)
        }
        ensureHoverTimer()
    }
    
    private func mouseMoved(_ point: NSPoint) {
        // Reserved for future: cursor proximity effects, hit testing, etc.
    }
    
    // MARK: - Hover timer
    
    private func startHoverTimer() {
        ensureHoverTimer()
    }
    
    private func ensureHoverTimer() {
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickHoverTimer()
        }
        // Don't block the main thread during scrolling.
        if let timer = hoverTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func tickHoverTimer() {
        let now = Date()
        var needsTimer = false
        
        // 1. Hover-expand: on-demand mode, mouse on island, collapsed with content.
        if hovering && !pinned && !expanded && activeCard != .none,
           let since = hoverSince,
           now.timeIntervalSince(since) >= Self.hoverExpandDelay {
            // Respect manual-collapse hold-off.
            if let holdUntil = manualCollapseUntil, now < holdUntil {
                // Still in hold-off period; skip.
            } else if !hoverExpanded {
                hoverExpanded = true
                expand()
            }
        }
        if hovering { needsTimer = true }
        
        // 2. Hover-collapse: on-demand mode, mouse left, expanded.
        if let deadline = collapseAt, now >= deadline {
            collapseAt = nil
            // Don't collapse if user is typing in a text field.
            let editing = windowHost?.panel.firstResponder is NSTextView
            if editing != true {
                collapse()
            }
        }
        if collapseAt != nil { needsTimer = true }
        
        // 3. Auto-collapse: notice/history timed dismissal.
        if let deadline = autoCollapseAt, now >= deadline {
            autoCollapseAt = nil
            if activeCard == .notice || activeCard == .history {
                collapse()
            }
        }
        if autoCollapseAt != nil { needsTimer = true }
        
        // 4. Stop timer when idle (no hover, no pending deadlines).
        if !needsTimer {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }
    
    // MARK: - Auto-collapse scheduling
    
    /// Schedule auto-collapse for transient content (notice, history).
    func scheduleAutoCollapse(after duration: TimeInterval) {
        guard !pinned else { return }
        if hovering {
            // Paused: save for when mouse exits.
            autoCollapseHeld = Date().addingTimeInterval(duration)
        } else {
            autoCollapseAt = Date().addingTimeInterval(duration)
        }
        ensureHoverTimer()
    }
    
    /// Cancel any pending auto-collapse.
    func cancelAutoCollapse() {
        autoCollapseAt = nil
        autoCollapseHeld = nil
    }
    
    // MARK: - Context menu (right-click)
    
    private func showContextMenu(at point: NSPoint) {
        let menu = buildContextMenu()
        guard let panel = windowHost?.panel else { return }
        // Convert canvas-local point to screen coordinates for the menu.
        let windowPoint = NSPoint(x: point.x, y: point.y)
        menu.popUp(positioning: nil, at: windowPoint, in: windowHost?.panel.contentView)
        _ = panel // suppress unused warning
    }
    
    /// Build the right-click context menu (Python parity: pin toggle, collapse, settings, quit).
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Pin toggle
        let pinItem = NSMenuItem(title: pinned ? "切换为按需模式" : "切换为固定模式",
                                 action: #selector(contextMenuTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        
        // Collapse
        let collapseItem = NSMenuItem(title: "立即收起",
                                      action: #selector(contextMenuCollapse), keyEquivalent: "")
        collapseItem.target = self
        collapseItem.isEnabled = expanded
        menu.addItem(collapseItem)
        
        menu.addItem(.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "设置…",
                                      action: #selector(contextMenuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出 BetterFocusIDE",
                                  action: #selector(contextMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func contextMenuTogglePin() { togglePin() }
    @objc private func contextMenuCollapse() { collapse() }
    @objc private func contextMenuSettings() { onOpenSettings?() }
    @objc private func contextMenuQuit() { NSApplication.shared.terminate(nil) }

    private func routeSocketMessage(_ message: AgentSocketMessage) {
        guard let event = SocketEvent(rawValue: message.event) else { return }
        switch event {
        case .questionRequested:
            // Gate: question_enabled off → ignore, the request falls back to the IDE.
            guard Settings.shared.questionEnabled else { return }
            questionController.handleEvent(event, message: message)
        case .questionAnswered, .questionTimeout:
            questionController.handleEvent(event, message: message)
        case .permissionRequested:
            // Gate: permission_enabled off → ignore, the request falls back to the IDE.
            guard Settings.shared.permissionEnabled else { return }
            permissionController.handleEvent(event, message: message)
        case .permissionResolved, .permissionTimeout:
            permissionController.handleEvent(event, message: message)
        case .sessionEnded:
            questionController.handleEvent(.sessionEnded, message: message)
            permissionController.handleEvent(.sessionEnded, message: message)
        case .turnFinished:
            noticeController.handleTurnFinished(message: message)
        case .activity:
            showHistory()  // TEMP: debug trigger to open history from a script
        }
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        hoverTimer?.invalidate()
        sweepTimer?.invalidate()
    }

    // MARK: - Keyboard answering

    /// Install a local key monitor. It fires only while one of our windows is key
    /// (the island, after the user clicks it), so shortcuts never steal typing from
    /// another app. Unclaimed keys are returned to the system untouched.
    func startKeyboard() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    /// Returns true when the island claimed the key.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let panel = windowHost?.panel, panel.isKeyWindow else { return false }
        let action = Keymap.resolve(key: Keymap.key(from: event),
                                    modifiers: Keymap.modifiers(from: event.modifierFlags),
                                    context: keyContext(editing: panel.firstResponder is NSTextView))
        guard let action else { return false }
        dispatch(action)
        return true
    }

    private func keyContext(editing: Bool) -> Keymap.Context {
        let visible = expanded
        let guarded = Date().timeIntervalSince(expandedAt) < Self.cardClickGuard
        switch activeCard {
        case .question:
            let p = questionController.prompt
            return Keymap.Context(
                kind: .question, visible: visible, editing: editing,
                guarded: guarded, closing: isClosing,
                answered: questionController.choice != nil,
                optionCount: p?.question.options.count ?? 0,
                index: p?.index ?? 0,
                questionCount: p?.questions.count ?? 1)
        case .permission:
            return Keymap.Context(
                kind: .permission, visible: visible, editing: editing,
                guarded: guarded, closing: isClosing,
                answered: permissionController.choice != nil)
        default:
            return Keymap.Context(kind: .none, visible: visible, editing: editing)
        }
    }

    private func dispatch(_ action: Keymap.Action) {
        switch action {
        case .option(let index):
            guard let p = questionController.prompt else { return }
            questionController.pick(.option(index), for: p.question.id)
        case .nav(let index):
            questionController.navigate(to: index)
        case .other:
            guard let p = questionController.prompt else { return }
            questionController.requestFocusOther(for: p.question.id)
        case .send:
            questionController.submit()
        case .decide(let decision):
            permissionController.decide(decision)
        case .collapse:
            collapse()
        case .settings:
            onOpenSettings?()
        case .togglePin:
            togglePin()
        }
    }

    /// Flip hold mode: a pinned card stays expanded instead of auto-collapsing.
    func togglePin() {
        pinned.toggle()
        Log.info("图钉切换 pinned=\(pinned)", topic: "pin")
        if pinned {
            // Pinning cancels any pending auto-collapse.
            cancelAutoCollapse()
        } else {
            // Unpinning re-arms auto-collapse for transient content.
            if activeCard == .notice {
                scheduleAutoCollapse(after: Settings.shared.notifyBannerDuration)
            } else if activeCard == .history {
                scheduleAutoCollapse(after: Self.historyDuration)
            }
        }
        noticeController.applyPinChange()
    }

    // MARK: - Live settings

    /// A setting changed: re-present the island at its recomputed size so edits
    /// (card width, fonts, colors, timings) apply immediately without a restart.
    private func handleSettingsChanged() {
        updatePendingTotal()
        restartSweepTimerIfNeeded()
        guard windowHost != nil else { return }
        let size = expanded ? targetSizeForCurrentCard()
                            : geometry.restingSize(showsContent: false)
        // Assigning surfaceSize (even to the same value) republishes, so the
        // SwiftUI content re-renders and picks up new fonts / colors.
        surfaceSize = size
        windowHost?.present(size: size, geometry: geometry, animated: false, showsContent: expanded)
    }

    /// The island body was tapped. For a permission reminder, optionally jump to
    /// the IDE first (permission_notice_jump), then run the normal toggle.
    func handleSurfaceTap() {
        if activeCard == .permission, Settings.shared.permissionNoticeJump,
           let req = permissionController.request {
            IDELauncher.activateAsync(provider: req.provider.rawValue, host: nil)
        }
        toggle()
    }

    // MARK: - Stale-card sweep

    private func startSweepTimer() {
        sweepTimer?.invalidate()
        lastSweepInterval = Settings.shared.sweepInterval
        let interval = TimeInterval(max(5, lastSweepInterval))
        sweepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sweepStaleCards()
        }
        if let timer = sweepTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func restartSweepTimerIfNeeded() {
        if Settings.shared.sweepInterval != lastSweepInterval { startSweepTimer() }
    }

    /// Drop cards whose hook has already timed out — the wait limit plus the
    /// +60s hook margin plus the grace — so a forgotten request can't pin the
    /// island open forever (Python card sweep).
    private func sweepStaleCards() {
        let deadline = TimeInterval(
            Settings.shared.agentWaitLimit + 60 + max(0, Settings.shared.sweepGrace))
        questionController.sweepStale(olderThan: deadline)
        permissionController.sweepStale(olderThan: deadline)
    }
}
