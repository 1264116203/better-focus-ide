// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import Combine

/// 灵动岛中央编排服务（单例、`ObservableObject`）。
///
/// 汇聚四类卡片控制器（提问 / 权限 / 通知 / 历史）、socket 事件路由、悬停状态机、
/// 键盘应答、窗口呈现与设置实时生效。视图通过订阅其 `@Published` 属性驱动刷新。
final class NotchService: ObservableObject {
    static let shared = NotchService()
    
    // MARK: - 对外发布状态
    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var expanded = false
    @Published private(set) var surfaceSize: CGSize
    @Published private(set) var surfaceShift: CGFloat = 0

    // MARK: - 阶段 2：卡片
    let questionController = QuestionController()
    let permissionController = PermissionController()
    // MARK: - 阶段 3：通知
    let noticeController = NoticeController()
    // MARK: - 阶段 4：历史
    let historyController = HistoryController()
    /// 当前活动卡片（提问优先）。
    @Published private(set) var activeCard: ActiveCard = .none
    /// 所有控制器的待处理总数（驱动收起态圆点）。
    @Published private(set) var pendingTotal: Int = 0
    /// 收起态待处理圆点的提供方主题色。
    @Published private(set) var pendingTint: (r: Double, g: Double, b: Double) = NotchLayout.accentColor
    /// 铃铛摆动动画应开始的时刻（通知到达时）。
    @Published var bellSwingStart: Date?
    /// 呼吸灯覆盖层的主题色（nil 时不显示，非 nil 时按提供方主题色呼吸）。
    @Published private(set) var breathingTint: Color?
    /// 是否有未处理的通知卡片（自动收起后为 true，用于驱动呼吸灯提醒）。
    @Published private(set) var hasUnprocessedNotice: Bool = false
    /// 未处理通知的提供方主题色（用于呼吸灯颜色）。
    @Published private(set) var unprocessedNoticeTint: Color?
    /// 正在撤下的卡片（收起动画期间可见，随后清空）。
    @Published private(set) var closingCard: ActiveCard?

    enum ActiveCard {
        case none, question, permission, notice, history
    }
    
    // MARK: - 私有依赖
    private var windowHost: NotchWindowHost?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private let socketServer = AgentEventSocketServer.shared

    // MARK: - 键盘 / 钉住状态
    /// 岛上次展开的时刻——驱动防误触窗口。
    private var expandedAt = Date.distantPast
    /// 卡片正在淡出时为 true；按键被忽略，应答不会中途被改。
    private var isClosing = false
    /// 钉住的卡片保持展开而非自动收起（"固定 ⇄ 按需"）。
    @Published private(set) var pinned = false
    /// 用户对历史面板的置顶覆盖（nil = 未手动切换，实时跟随设置 pinByDefault）
    private var lastHistoryPinned: Bool?
    /// 用户对通知横幅的置顶覆盖（nil = 未手动切换，实时跟随设置 pinByDefault）
    private var lastNoticePinned: Bool?
    private var keyMonitor: Any?
    /// 由 AppDelegate 接线，使 ⌘, 打开设置窗口。
    var onOpenSettings: (() -> Void)?

    /// 卡片出现后的防误触窗口（秒），对齐 Python `CARD_CLICK_GUARD`。手正搭在
    /// "允许"将落下的位置时无法误批。实时取自 Settings（click_guard）；0 关闭守卫。
    static var cardClickGuard: TimeInterval { Settings.shared.clickGuard }
    
    /// 防误触守卫是否处于激活期（卡片刚出现）。
    var isClickGuarded: Bool {
        Date().timeIntervalSince(expandedAt) < Self.cardClickGuard
    }
    
    // MARK: - 悬停状态机（Python HOVER_EXPAND_DELAY / HOVER_COLLAPSE_DELAY）
    
    /// 悬停多久后展开岛（秒，实时取自 Settings）。
    static var hoverExpandDelay: TimeInterval { Settings.shared.hoverExpandDelay }
    /// 鼠标移出后多久自动收起（秒，实时取自 Settings）。
    static var hoverCollapseDelay: TimeInterval { Settings.shared.hoverCollapseDelay }
    /// 固定模式下手动收起后的让位时长（秒，实时取自 Settings）。
    static var manualCollapseHold: TimeInterval { Settings.shared.manualCollapseHold }
    /// 历史面板自动关闭时长（秒，实时取自 Settings）。
    static var historyDuration: TimeInterval { Settings.shared.historyDuration }
    
    private var hovering = false
    private var hoverSince: Date?
    private var hoverExpanded = false
    /// 按需模式：鼠标移出后安排的收起时刻。
    private var collapseAt: Date?
    /// 瞬态内容（通知/历史）的自动收起截止时间。
    private var autoCollapseAt: Date?
    /// 悬停暂停自动收起时保存的截止时间。
    private var autoCollapseHeld: Date?
    /// 固定模式：手动收起的让位期（在此之前不再自动展开）。
    private var manualCollapseUntil: Date?
    private var hoverTimer: Timer?
    /// 周期性陈旧卡片清扫（Python CARD_SWEEP_INTERVAL / CARD_SWEEP_GRACE）。
    private var sweepTimer: Timer?
    private var lastSweepInterval = 0

    private init() {
        // 钉在刘海屏，而非当前有焦点的那块屏。
        let screen = Self.preferredScreen() ?? NSScreen.screens.first!
        let safeAreaTop = screen.safeAreaInsets.top
        let cameraWidth = Self.detectCameraWidth(screen: screen)
        
        let initialGeometry = NotchGeometry(
            screen: screen.frame,
            safeAreaTop: safeAreaTop,
            cameraWidth: cameraWidth
        )
        
        self.geometry = initialGeometry
        
        // 以收起尺寸启动
        self.surfaceSize = initialGeometry.restingSize(showsContent: false)

        // 观察屏幕变化
        observeScreenChanges()

        // 接线各控制器
        setupControllers()

        // 实时配置：任一设置变更都重排岛，使改动即时生效（Python settings.on_change），
        // 并按配置的周期让陈旧卡片清扫持续运行。
        Settings.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSettingsChanged() }
            .store(in: &cancellables)
        startSweepTimer()
    }
    
    // MARK: - 公开方法

    /// 首次显示岛：惰性创建窗口宿主后无动画呈现。
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
    
    /// 带动画隐藏岛。
    func hide() {
        windowHost?.hide(animated: true)
    }
    
    /// 点击表面的三分支：已展开则收起；有卡片但收起（按需模式）则展开；空闲岛则优先展示未读通知，否则回顾历史。
    func toggle() {
        if expanded {
            collapse()
        } else if activeCard != .none {
            // 有卡片但处于收起态（按需模式）：展开它。
            expand()
        } else if hasUnprocessedNotice, let restored = noticeController.restoreLastDismissed() {
            // 有自动收起的未读通知：恢复展示（而非打开历史）。
            hasUnprocessedNotice = false
            unprocessedNoticeTint = nil
            updateBreathingTint()
            noticeController.show(restored)
        } else if noticeController.hasQueuedNotices {
            // 有未读通知排队：弹出下一条，而非打开历史。
            hasUnprocessedNotice = false
            unprocessedNoticeTint = nil
            updateBreathingTint()
            noticeController.promoteNextFromQueue()
            if noticeController.hasActiveNotice {
                activeCard = .notice
                showNoticeBanner()
            }
        } else {
            // 空闲岛：点击回顾最近通知。
            showHistory()
        }
    }
    
    /// 展开到当前卡片的目标尺寸。
    func expand() {
        guard !expanded else { return }
        expanded = true
        expandedAt = Date()
        isClosing = false
        let newSize = targetSizeForCurrentCard()
        animateTo(size: newSize)
        syncKeyFocus()
    }
    
    /// 收起岛。
    ///
    /// 固定模式下记录让位期，避免自动展开立刻重开。历史与通知是瞬态的，收起即消失；
    /// 提问与权限持续存在（卡片仍在等用户）。
    func collapse() {
        guard expanded else { return }
        expanded = false
        isClosing = true
        // 固定模式：记录让位期，使自动展开不会立即重开。
        if pinned {
            manualCollapseUntil = Date().addingTimeInterval(Self.manualCollapseHold)
        }
        cancelAutoCollapse()
        collapseAt = nil
        // 历史与通知是瞬态的：收起即消失。提问与权限持续（卡片仍等用户）。
        if activeCard == .history {
            activeCard = .none
        } else if activeCard == .notice {
            noticeController.dismiss()
            // 如果队列中有下一条通知，promoteNext 已在 onDismiss→handleCardDismissal 中触发，
            // 此时 hasActiveNotice 为 true，不应收起——让 showNoticeBanner 接管。
            if noticeController.hasActiveNotice { return }
            activeCard = .none
        }
        let newSize = geometry.restingSize(showsContent: false)
        animateTo(size: newSize)
        syncKeyFocus()
        updatePendingTotal()
        // 淡出落定后清掉 closing 标志，使下次按键恢复。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.expanded else { return }
            self.isClosing = false
        }
    }

    /// 面板只在有卡片上屏时才接管键盘焦点，这样点击能使其成为 key、快捷键随之生效——
    /// 而绝不主动从用户的编辑器/终端抢走焦点。
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
        Log.debug("NotchService.animateTo: surfaceSize=\(size), expanded=\(expanded), activeCard=\(activeCard)", topic: "layout")
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

    /// 显示最近通知历史面板（从空闲状态的灵动岛触发）
    ///
    /// ## 布局公式
    /// ```
    /// contentHeight = 垂直内边距×2 + 标题栏高度 + 标题栏下间距
    ///               + 行数×行高 + (行数-1)×行间距
    ///             = 12×2 + 20 + 4 + rows×40 + (rows-1)×4
    /// ```
    ///
    /// ## 前置条件
    /// - 不抢占交互式卡片（问题/权限请求优先）
    /// - 自动折叠计时器：8 秒后自动收起（Python HISTORY_DURATION）
    func showHistory() {
        // 不抢占交互式卡片
        if activeCard == .question || activeCard == .permission { return }
        // 用户点击气泡查看历史，清除未处理通知标记（呼吸灯随之关闭）
        hasUnprocessedNotice = false
        unprocessedNoticeTint = nil
        updateBreathingTint()
        let cardChanged = activeCard != .history
        activeCard = .history
        // 置顶偏好：用户手动切换过的以用户为准，否则实时跟随设置（改动即刻生效）
        if cardChanged {
            pinned = lastHistoryPinned ?? Settings.shared.pinByDefault
        }
        Log.info("showHistory: pinned=\(pinned), lastHistoryPinned=\(String(describing: lastHistoryPinned)), cardChanged=\(cardChanged)", topic: "history")

        let rows = max(1, historyController.entries.count)

        // 内容高度计算（对齐 Python 参考实现 config.HISTORY_*）
        // - 12pt 垂直内边距 × 2（上下）
        // - 20pt 标题栏高度
        // - 4pt 标题栏与首行间距
        // - 40pt 单行高度 × 行数
        // - 4pt 行间距 × (行数-1)
        let content = 12.0 * 2 + 20.0 + 4.0
            + Double(rows) * 40.0 + Double(max(0, rows - 1)) * 4.0

        // 加上刘海安全区域高度（窗口贴屏幕顶部时需要避开摄像头）
        let height = geometry.safeContentTop + content

        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
        }

        animateTo(size: CGSize(width: NotchLayout.historyWidth, height: height))
        syncKeyFocus()

        // 8 秒后自动收起（Python HISTORY_DURATION = 8s）
        scheduleAutoCollapse(after: Self.historyDuration)
    }

    /// Show the transient turn-finished banner at a compact height.
    private func showNoticeBanner() {
        let cardChanged = activeCard != .notice
        activeCard = .notice
        // 置顶偏好：用户手动切换过的以用户为准，否则实时跟随设置（改动即刻生效）
        if cardChanged {
            pinned = lastNoticePinned ?? Settings.shared.pinByDefault
        }
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
        let cardChanged = activeCard != card
        activeCard = card
        // 只在卡片类型变化时重置置顶状态
        if cardChanged {
            pinned = Settings.shared.pinByDefault
        }
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
        } else if noticeController.count > 0 {
            // 通知队列有待展示项（之前因交互卡片在屏而被排队）：弹出下一条。
            hasUnprocessedNotice = false
            unprocessedNoticeTint = nil
            updateBreathingTint()
            noticeController.promoteNextFromQueue()
            if noticeController.hasActiveNotice {
                activeCard = .notice
                showNoticeBanner()
            } else {
                // 队列实际已空（不应到达）：收起。
                closingCard = activeCard
                activeCard = .none
                if expanded {
                    expanded = false
                    isClosing = true
                    cancelAutoCollapse()
                    collapseAt = nil
                    let newSize = geometry.restingSize(showsContent: false)
                    animateTo(size: newSize)
                }
            }
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
    
    /// 计算当前活动卡片的目标尺寸（对齐 Python 实现）
    ///
    /// 根据卡片类型返回对应的宽高：
    /// - 问题卡片：固定宽度 + 动态高度（基于文本行数）
    /// - 权限卡片：固定宽度 + 动态高度（基于文本行数）
    /// - 通知横幅：固定宽高
    /// - 历史面板：固定宽度 + 动态高度（基于条目数）
    /// - 无卡片：返回最小尺寸（空闲状态）
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
            // 历史面板高度计算（与 showHistory() 保持一致）
            let rows = max(1, historyController.entries.count)
            let content = 12.0 * 2 + 20.0 + 4.0
                + Double(rows) * 40.0 + Double(max(0, rows - 1)) * 4.0
            let height = geometry.safeContentTop + content
            return CGSize(width: NotchLayout.historyWidth, height: height)
        case .none:
            // 空闲状态：不应展开，返回最小尺寸
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
    
    /// 近似文本高度：给定宽度与字号（单行高 = fontSize × 1.3）。
    private func bodyHeight(_ text: String, width: CGFloat, font: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return font * 1.3 }
        let lineHeight = font * 1.3
        // 中英混排的粗略字符宽估计。
        let avgCharWidth = font * 0.6
        let charsPerLine = max(1, Int(width / avgCharWidth))
        let lines = max(1, CGFloat(text.count) / CGFloat(charsPerLine))
        return ceil(lines) * lineHeight
    }
    
    // MARK: - 待处理总数
    
    /// 重算待处理总数（驱动收起态圆点外观），并按最高优先级提供方取色。
    private func updatePendingTotal() {
        let total = questionController.count + permissionController.count + noticeController.count
        pendingTotal = total
        // 主题色取优先级最高的待处理项：提问 > 权限 > 通知。
        if questionController.count > 0 {
            pendingTint = questionController.pendingTint ?? NotchLayout.accentColor
        } else if permissionController.count > 0 {
            pendingTint = permissionController.pendingTint ?? NotchLayout.accentColor
        } else if noticeController.count > 0 {
            pendingTint = noticeController.pendingTint ?? NotchLayout.accentColor
        } else {
            pendingTint = NotchLayout.accentColor
        }
        // 同步更新呼吸灯颜色
        updateBreathingTint()
    }
    
    /// 更新呼吸灯覆盖层的主题色。
    ///
    /// 只有当通知卡片未操作自动收起后（hasUnprocessedNotice = true），
    /// 才显示呼吸灯提醒，颜色取该通知的提供方主题色。
    private func updateBreathingTint() {
        if hasUnprocessedNotice {
            // 有未处理通知：显示呼吸灯
            breathingTint = unprocessedNoticeTint
        } else {
            // 无未处理通知：关闭呼吸灯
            breathingTint = nil
        }
    }
    
    // MARK: - 悬停状态机

    /// 鼠标进入：置悬停态、暂停自动收起（保存截止时间待鼠标移出后恢复），并确保计时器运行。
    private func mouseEntered() {
        hovering = true
        hoverSince = Date()
        // 悬停期间暂停自动收起。
        if let deadline = autoCollapseAt {
            autoCollapseHeld = deadline
            autoCollapseAt = nil
        }
        // 按需模式：收起态且有待处理内容时，安排延迟展开。
        if !pinned && !expanded && activeCard != .none {
            // hoverExpandDelay 在 tickHoverTimer 中检查
        }
        ensureHoverTimer()
    }
    
    /// 鼠标移出：清悬停态、恢复自动收起截止、按需模式下安排延迟收起。
    private func mouseExited() {
        hovering = false
        hoverSince = nil
        hoverExpanded = false
        // 恢复自动收起截止时刻。
        if let held = autoCollapseHeld {
            autoCollapseAt = held
            autoCollapseHeld = nil
        }
        // 按需模式：若因悬停而展开，则安排延迟收起。
        Log.debug("mouseExited: pinned=\(pinned), expanded=\(expanded), activeCard=\(activeCard)", topic: "hover")
        if !pinned && expanded && activeCard != .question && activeCard != .permission {
            collapseAt = Date().addingTimeInterval(Self.hoverCollapseDelay)
            Log.debug("mouseExited: setting collapseAt", topic: "hover")
        }
        ensureHoverTimer()
    }
    
    private func mouseMoved(_ point: NSPoint) {
        // 预留给未来：光标邻近效果、命中测试等。
    }
    
    // MARK: - 悬停计时器
    
    private func startHoverTimer() {
        ensureHoverTimer()
    }
    
    /// 惰性创建 60Hz 悬停计时器（加入 .common runloop 模式，滚动时不阻塞主线程）。
    private func ensureHoverTimer() {
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickHoverTimer()
        }
        // 滚动时不阻塞主线程。
        if let timer = hoverTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// 每 tick 推进四类判定：悬停展开、悬停收起、自动收起、空闲停表。
    private func tickHoverTimer() {
        let now = Date()
        var needsTimer = false
        
        // 1. 悬停展开：按需模式，鼠标在岛上，收起态且有内容。
        if hovering && !pinned && !expanded && activeCard != .none,
           let since = hoverSince,
           now.timeIntervalSince(since) >= Self.hoverExpandDelay {
            // 尊重手动收起让位期。
            if let holdUntil = manualCollapseUntil, now < holdUntil {
                // 仍在让位期内：跳过。
            } else if !hoverExpanded {
                hoverExpanded = true
                expand()
            }
        }
        if hovering { needsTimer = true }
        
        // 2. 悬停收起：按需模式，鼠标已移开，处于展开。
        if let deadline = collapseAt, now >= deadline {
            collapseAt = nil
            // 用户正在文本框输入时不收起。
            let editing = windowHost?.panel.firstResponder is NSTextView
            if editing != true {
                collapse()
            }
        }
        if collapseAt != nil { needsTimer = true }
        
        // 3. 自动收起：通知/历史到时消失。
        if let deadline = autoCollapseAt, now >= deadline {
            autoCollapseAt = nil
            if activeCard == .notice || activeCard == .history {
                if activeCard == .notice {
                    // 通知自动到时：先尝试弹出队列中下一条，队列空才标记未处理+收起。
                    let savedTint = noticeController.notice.flatMap {
                        AgentProvider(rawValue: $0.provider)?.tint
                    }
                    noticeController.saveForRestore()   // 保存当前通知供气泡点击恢复
                    noticeController.dismiss()        // 清当前 + onDismiss + promoteNext()
                    if !noticeController.hasActiveNotice {
                        // 队列已空：标记未处理以驱动呼吸灯，然后收起。
                        hasUnprocessedNotice = true
                        unprocessedNoticeTint = savedTint
                        collapse()
                    }
                    // promoteNext 成功时 showNoticeBanner 已重设 autoCollapse，无需额外处理。
                } else {
                    collapse()
                }
            }
        }
        if autoCollapseAt != nil { needsTimer = true }
        
        // 4. 空闲时停表（无悬停、无待处理截止）。
        if !needsTimer {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }
    
    // MARK: - 自动收起调度

    /// 为瞬态内容（通知、历史）安排自动收起。
    ///
    /// 钉住时不调度；正在悬停则保存截止（待鼠标移出后生效），否则立即设截止。
    func scheduleAutoCollapse(after duration: TimeInterval) {
        guard !pinned else { return }
        if hovering {
            // 暂停：留待鼠标移出时用。
            autoCollapseHeld = Date().addingTimeInterval(duration)
        } else {
            autoCollapseAt = Date().addingTimeInterval(duration)
        }
        ensureHoverTimer()
    }
    
    /// 取消所有待执行的自动收起。
    func cancelAutoCollapse() {
        autoCollapseAt = nil
        autoCollapseHeld = nil
    }
    
    // MARK: - 上下文菜单（右键）

    /// 在给定画布局标点弹出右键菜单。
    private func showContextMenu(at point: NSPoint) {
        let menu = buildContextMenu()
        guard let panel = windowHost?.panel else { return }
        // 把画布局部点转成窗口坐标供菜单定位。
        let windowPoint = NSPoint(x: point.x, y: point.y)
        menu.popUp(positioning: nil, at: windowPoint, in: windowHost?.panel.contentView)
        _ = panel // 抑制未使用警告
    }
    
    /// 构建右键上下文菜单（对齐 Python：钉住切换、立即收起、设置、退出）。
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 钉住切换
        let pinItem = NSMenuItem(title: pinned ? "切换为按需模式" : "切换为固定模式",
                                 action: #selector(contextMenuTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        
        // 立即收起
        let collapseItem = NSMenuItem(title: "立即收起",
                                      action: #selector(contextMenuCollapse), keyEquivalent: "")
        collapseItem.target = self
        collapseItem.isEnabled = expanded
        menu.addItem(collapseItem)
        
        menu.addItem(.separator())
        
        // 设置
        let settingsItem = NSMenuItem(title: "设置…",
                                      action: #selector(contextMenuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        // 退出
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

    /// 把一条 socket 消息路由到对应控制器。
    ///
    /// 提问/权限请求受各自开关门控：关掉即忽略，请求回落到 IDE 自己的弹窗。
    private func routeSocketMessage(_ message: AgentSocketMessage) {
        guard let event = SocketEvent(rawValue: message.event) else { return }
        switch event {
        case .questionRequested:
            // 门控：question_enabled 关 → 忽略，请求回落到 IDE。
            guard Settings.shared.questionEnabled else { return }
            questionController.handleEvent(event, message: message)
        case .questionAnswered, .questionTimeout:
            questionController.handleEvent(event, message: message)
        case .permissionRequested:
            // 门控：permission_enabled 关 → 忽略，请求回落到 IDE。
            guard Settings.shared.permissionEnabled else { return }
            permissionController.handleEvent(event, message: message)
        case .permissionResolved, .permissionTimeout:
            permissionController.handleEvent(event, message: message)
        case .permissionNotice:
            // 权限通知（只提醒，不拦截）：以横幅形式展示，让 Qoder 原生窗做决策。
            Log.debug("routeSocketMessage: permission_notice received, permissionEnabled=\(Settings.shared.permissionEnabled)", topic: "permission")
            guard Settings.shared.permissionEnabled else { return }
            noticeController.handlePermissionNotice(message: message)
        case .sessionEnded:
            questionController.handleEvent(.sessionEnded, message: message)
            permissionController.handleEvent(.sessionEnded, message: message)
        case .turnFinished:
            noticeController.handleTurnFinished(message: message)
        case .activity:
            showHistory()  // 临时：供脚本触发打开历史，便于调试
        }
    }

    /// 释放：移除屏幕观察与键盘监听、停掉悬停与清扫计时器。
    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        hoverTimer?.invalidate()
        sweepTimer?.invalidate()
    }

    // MARK: - 键盘应答

    /// 安装本地按键监听器。它只在我们某个窗口为 key 时（用户点击岛之后）触发，
    /// 因此快捷键绝不会从别的应用抢走打字。未认领的按键原样交还系统。
    func startKeyboard() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    /// 岛认领了该按键时返回 true。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let panel = windowHost?.panel, panel.isKeyWindow else { return false }
        let action = Keymap.resolve(key: Keymap.key(from: event),
                                    modifiers: Keymap.modifiers(from: event.modifierFlags),
                                    context: keyContext(editing: panel.firstResponder is NSTextView))
        guard let action else { return false }
        dispatch(action)
        return true
    }

    /// 依据当前活动卡片组装 Keymap 上下文快照（可见性、守卫、是否已应答等）。
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

    /// 把 Keymap 解析出的动作分发到对应控制器。
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

    /// 翻转固定模式：钉住的卡片保持展开而非自动收起。
    func togglePin() {
        Log.info("togglePin called: before pinned=\(pinned), activeCard=\(activeCard)", topic: "pin")
        pinned.toggle()
        Log.info("图钉切换 pinned=\(pinned)", topic: "pin")
        // 记住用户对瞬态卡片（历史/通知）的置顶偏好
        if activeCard == .history {
            lastHistoryPinned = pinned
        } else if activeCard == .notice {
            lastNoticePinned = pinned
        }
        if pinned {
            // 钉住：取消任何待执行的自动收起。
            cancelAutoCollapse()
        } else {
            // 取消钉住：为瞬态内容重新装载自动收起。
            if activeCard == .notice {
                scheduleAutoCollapse(after: Settings.shared.notifyBannerDuration)
            } else if activeCard == .history {
                scheduleAutoCollapse(after: Self.historyDuration)
            }
        }
        noticeController.applyPinChange()
    }

    // MARK: - 实时设置

    /// 某设置已变更：按重算尺寸重新呈现岛，使改动（卡片宽度、字号、颜色、时长）
    /// 无需重启即刻生效。
    private func handleSettingsChanged() {
        updatePendingTotal()
        restartSweepTimerIfNeeded()
        guard windowHost != nil else { return }
        let size = expanded ? targetSizeForCurrentCard()
                            : geometry.restingSize(showsContent: false)
        // 给 surfaceSize 赋值（哪怕是相同值）会重新发布，使 SwiftUI 内容重渲染、
        // 采纳新的字号 / 颜色。
        surfaceSize = size
        windowHost?.present(size: size, geometry: geometry, animated: false, showsContent: expanded)
    }

    /// 岛表面被点击。权限提醒可先按需跳回 IDE（permission_notice_jump），再走常规 toggle。
    func handleSurfaceTap() {
        if activeCard == .permission, Settings.shared.permissionNoticeJump,
           let req = permissionController.request {
            IDELauncher.activateAsync(provider: req.provider.rawValue, host: req.host)
        }
        toggle()
    }

    // MARK: - 陈旧卡片清扫

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
