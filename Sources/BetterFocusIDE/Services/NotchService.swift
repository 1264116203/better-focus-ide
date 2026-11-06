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
    // MARK: - 阶段 5：任务进度（各宿主 todowrite）
    let todoController = TodoController()
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
    /// 上一次的呼吸灯亮/灭状态，仅用于「状态翻转时才打日志」。
    private var lastGlowLit: Bool?
    /// 正在撤下的卡片（收起动画期间可见，随后清空）。
    @Published private(set) var closingCard: ActiveCard?

    enum ActiveCard {
        case none, question, permission, notice, history, todo
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
    /// 初值必须与设置一致：否则启动后、第一张卡片上屏前，图钉图标会显示成"按需"
    /// 而设置里其实是"固定"，两者短暂不同步。
    @Published private(set) var pinned = Settings.shared.pinByDefault
    /// 用户手动置顶偏好（**所有卡片共享一份**；nil = 未手动切换，实时跟随设置 pinByDefault）。
    /// 进程内记忆：重启 app 后回到设置默认值。
    private var userPinned: Bool?
    /// 上次看到的设置默认值；用于在设置面板切换「卡片默认固定展示」时清除手动覆盖。
    private var lastPinByDefault = Settings.shared.pinByDefault
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
    /// 手动收起时鼠标是否还停在岛上：为真时必须先移出再移入，悬停才允许重开。
    /// 否则「点气泡收起 → 鼠标没动 → 延迟一到又自己弹开」。
    private var manualCollapseNeedsMouseExit = false
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
        restartTodoIdleTimer()
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
    
    /// 展开到当前卡片的目标尺寸。`gentle` = 悬停重展开，用更弱回弹避免明显超调。
    func expand(gentle: Bool = false) {
        guard !expanded else { return }
        expanded = true
        expandedAt = Date()
        isClosing = false
        closingCard = nil
        let newSize = targetSizeForCurrentCard()
        animateTo(size: newSize, gentle: gentle)
        syncKeyFocus()
    }
    
    /// 收起岛。
    ///
    /// 固定模式下记录让位期，避免自动展开立刻重开。历史与通知是瞬态的，收起即消失；
    /// 提问与权限持续存在（卡片仍在等用户）。
    func collapse() {
        guard expanded else { return }
        if activeCard != .none { closingCard = activeCard }
        expanded = false
        isClosing = true
        // 手动收起后一律记录让位期。原先只有固定模式记录，导致按需模式下
        // 「用户点气泡收起 → 鼠标还在岛上 → tickHoverTimer 立刻重新展开」，
        // 表现为卡片反复闪烁、根本收不起来。
        manualCollapseUntil = Date().addingTimeInterval(Self.manualCollapseHold)
        manualCollapseNeedsMouseExit = hovering
        cancelAutoCollapse()
        collapseAt = nil
        // 历史、通知、任务进度是瞬态的：收起即消失。提问与权限持续（卡片仍等用户）。
        if activeCard == .history {
            activeCard = .none
        } else if activeCard == .todo {
            // 收起即视为「看过了」：不清空控制器会挡住下一次自动上屏。
            todoController.reset()
            activeCard = .none
        } else if activeCard == .notice {
            // 手动收起通知前，先保存通知数据供气泡点击恢复
            let savedTint = noticeController.notice.flatMap {
                AgentProvider(rawValue: $0.provider)?.tint
            }
            let saved = noticeController.saveForRestore()
            noticeController.dismiss()
            // 如果队列中有下一条通知，promoteNext 已在 onDismiss→handleCardDismissal 中触发，
            // 此时 hasActiveNotice 为 true，不应收起——让 showNoticeBanner 接管。
            if noticeController.hasActiveNotice {
                closingCard = nil
                return
            }
            // 保存成功且队列空：标记未处理以驱动呼吸灯
            if saved {
                hasUnprocessedNotice = true
                unprocessedNoticeTint = savedTint
                updateBreathingTint()
            }
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
        // 应用当前呼吸辉光状态（辉光层挂在 AppKit 画布上，需在窗口创建后刷新）。
        updateBreathingTint()
        startHoverTimer()
    }
    
    private func animateTo(size: CGSize, gentle: Bool = false) {
        // 收起时先别把 SwiftUI 收成气泡尺寸。玻璃还是整张卡片，内容先缩进气泡
        // 会在卡片中间闪出一块，气泡越大越明显，调到最小就看不见。
        let toBubble = !expanded && (size.width < surfaceSize.width - 0.5 || size.height < surfaceSize.height - 0.5)
        if !toBubble {
            surfaceSize = size
        }
        Log.debug("NotchService.animateTo: surfaceSize=\(size), expanded=\(expanded), activeCard=\(activeCard)", topic: "layout")
        windowHost?.present(
            size: size,
            geometry: geometry,
            animated: true,
            showsContent: expanded,
            gentle: gentle,
            preserveContentFrame: toBubble,
            onSettled: toBubble ? { [weak self] in
                guard let self, !self.expanded else { return }
                self.surfaceSize = size
                self.closingCard = nil
                self.isClosing = false
            } : nil
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
            surfaceSize = geometry.restingSize(showsContent: true)  // 收起态使用 bubbleWidth/bubbleHeight
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
        // 真实刘海宽与卡片宽度同源（NotchLayout.physicalNotchWidth），避免两处逻辑漂移。
        if let width = NotchLayout.physicalNotchWidth(of: screen) { return width }
        // 兜底：刘海屏但辅助区不可用时估 180；无刘海屏用模拟宽 150。
        return screen.safeAreaInsets.top > 0 ? 180 : 150
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

    /// One-click install of all four integrations. Returns a human summary.
    /// 任一宿主失败不影响其余条目：用户能直接从汇总里看到是哪一项出问题。
    @discardableResult
    func installAll() -> String {
        var lines: [String] = []
        func install(_ label: String, _ work: () throws -> Void) {
            do {
                try work()
                lines.append("✓ \(label) 已安装")
            } catch {
                lines.append("✗ \(label) 失败：\(error.localizedDescription)")
            }
        }
        install("Qoder Hook") { try QoderHookInstaller.install() }
        install("OpenCode Plugin") { try OpenCodePluginInstaller.install() }
        install("Cursor Hook") { try CursorHookInstaller.install() }
        install("WorkBuddy Hook") { try WorkBuddyHookInstaller.install() }
        // 其余宿主一律「装在本机才写配置」：给没装的宿主建目录，只会在人家
        // 那边留一堆没人读的脚本，卸载时还得靠用户自己清理。
        if InstallerPaths.hostDirectoryExists(InstallerPaths.claudeDir)
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app") {
            install("Claude Code Hook") { try ClaudeCodeHookInstaller.install() }
        }
        if CodexHookInstaller.isPresent {
            install("Codex Notify") { try CodexHookInstaller.install() }
        }
        if TraeHookInstaller.Flavor.cn.isPresent {
            install("Trae CN Hook") { try TraeHookInstaller.install(.cn) }
        }
        if TraeHookInstaller.Flavor.international.isPresent {
            install("Trae Hook") { try TraeHookInstaller.install(.international) }
        }
        if KimiHookInstaller.isPresent {
            install("Kimi Hook") { try KimiHookInstaller.install() }
        }
        if QoderCnHookInstaller.isPresent {
            install("Qoder CN Hook") { try QoderCnHookInstaller.install() }
        }
        Log.info("installAll: " + lines.joined(separator: " | "), topic: "install")
        return lines.joined(separator: "\n")
    }

    func uninstallAll() {
        QoderHookInstaller.uninstall()
        OpenCodePluginInstaller.uninstall()
        CursorHookInstaller.uninstall()
        WorkBuddyHookInstaller.uninstall()
        ClaudeCodeHookInstaller.uninstall()
        CodexHookInstaller.uninstall()
        TraeHookInstaller.uninstall(.cn)
        TraeHookInstaller.uninstall(.international)
        KimiHookInstaller.uninstall()
        QoderCnHookInstaller.uninstall()
    }

    /// 启动时校验**已装**的集成，内容与本构建不一致就重写回去。
    ///
    /// 为什么需要：这些脚本/插件一旦内容不合法，宿主会整份拒绝加载，
    /// 而应用侧只看到「已安装」——OpenCode 插件里残留一行半截表达式，
    /// 就会让提问、权限、完成通知同时静默消失，排查成本极高。
    /// `install()` 本身是幂等的（内容相同不写），所以这里只负责触发；
    /// 只对已存在的文件动手，不给没装宿主的人凭空建配置。
    func repairInstalledIntegrations() {
        var repaired: [String] = []
        func repair(_ label: String, _ installed: Bool, _ work: () throws -> Void) {
            guard installed else { return }
            do {
                try work()
                repaired.append(label)
            } catch {
                Log.error("\(label) 自愈失败：\(error.localizedDescription)", topic: "install")
            }
        }
        repair("OpenCode Plugin", OpenCodePluginInstaller.isInstalled,
               OpenCodePluginInstaller.install)
        repair("Qoder Hook", QoderHookInstaller.isInstalled,
               QoderHookInstaller.install)
        repair("Cursor Hook", CursorHookInstaller.isInstalled,
               CursorHookInstaller.install)
        repair("WorkBuddy Hook", WorkBuddyHookInstaller.isInstalled,
               WorkBuddyHookInstaller.install)
        // Qoder CN 只在装了才碰：它的配置里若残留指向英文版脚本的注册，
        // 通知会丢掉 BETTERFOCUS_VARIANT=cn，国内版被记成国际版。
        if QoderCnHookInstaller.isPresent {
            repair("Qoder CN Hook", QoderCnHookInstaller.isInstalled,
                   QoderCnHookInstaller.install)
        }
        // 升级后的脚本多了「让位」分支：老副本读到 answer_index = -4 会当成未知
        // 下标，等于把工具晾在那儿。GUI 宿主（Trae）拿到的正是这条信号，
        // 所以凡是装过的都要跟着本构建刷新，不能只挑几个。
        repair("Claude Code Hook", ClaudeCodeHookInstaller.isInstalled,
               ClaudeCodeHookInstaller.install)
        for flavor in [TraeHookInstaller.Flavor.international, .cn] {
            guard flavor.isPresent else { continue }
            repair("Trae Hook (\(flavor.dir))",
                   TraeHookInstaller.isInstalled(flavor)) {
                try TraeHookInstaller.install(flavor)
            }
        }
        if KimiHookInstaller.isPresent {
            repair("Kimi Hook", KimiHookInstaller.isInstalled, KimiHookInstaller.install)
        }
        if CodexHookInstaller.isPresent {
            repair("Codex Hook", CodexHookInstaller.isInstalled, CodexHookInstaller.install)
        }
        if !repaired.isEmpty {
            Log.info("已校验安装态集成：" + repaired.joined(separator: "、"), topic: "install")
        }
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
        activeCard = .history
        // 置顶状态全局统一：不按卡片重置，从共享偏好解析
        refreshPinned()
        Log.info("showHistory: pinned=\(pinned), userPinned=\(String(describing: userPinned))", topic: "history")

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
            closingCard = nil
        }

        animateTo(size: CGSize(width: NotchLayout.historyWidth, height: height))
        syncKeyFocus()

        // 8 秒后自动收起（Python HISTORY_DURATION = 8s）
        scheduleAutoCollapse(after: Self.historyDuration)
    }

    /// Show the transient turn-finished banner at a compact height.
    private func showNoticeBanner() {
        activeCard = .notice
        // 新通知上屏：清除旧的未处理标记（呼吸灯随之关闭）
        hasUnprocessedNotice = false
        unprocessedNoticeTint = nil
        // 置顶状态全局统一：不按卡片重置，从共享偏好解析
        refreshPinned()
        bellSwingStart = Date()  // Trigger bell swing animation.
        let bannerSize = CGSize(width: NotchLayout.expandedWidth,
                                height: NotchLayout.expandedHeight)
        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
            closingCard = nil
        }
        animateTo(size: bannerSize)
        syncKeyFocus()
        updatePendingTotal()
        // Auto-collapse after the configured duration (unless pinned).
        scheduleAutoCollapse(after: Settings.shared.notifyBannerDuration)
    }

    /// 交互式卡片（提问 / 权限）上屏。
    ///
    /// 这两类请求是**阻塞式**的：hook 正同步等用户回答，超时就回落到 IDE 自己的弹窗。
    /// 因此无论「固定」还是「按需」模式都必须主动展开一次——pinned 只决定展开后
    /// 是否保持（鼠标移出是否自动收起），不能把卡片吞进队列里只留一个圆点。
    /// 瞬态的通知 / 历史仍走 showNoticeBanner / showHistory 的按需逻辑。
    private func showCard(_ card: ActiveCard) {
        activeCard = card
        // 置顶状态全局统一：不按卡片重置，从共享偏好解析
        refreshPinned()
        // 先记日志再形变：首帧布局可能耗时数百毫秒到数秒，日志放在 animateTo
        // 之后会让「卡片已弹出」的记录晚于真实时刻，干扰问题定位。
        Log.info("showCard: \(card) 主动弹出, pinned=\(pinned)", topic: "card")

        // 新请求到达即清掉上一次手动收起的让位期，避免悬停状态机把它压住。
        manualCollapseUntil = nil
        manualCollapseNeedsMouseExit = false
        collapseAt = nil
        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
            closingCard = nil
        }
        animateTo(size: targetSizeForCurrentCard())
        syncKeyFocus()
        updatePendingTotal()
        // 提示音 / 触感必须排在形变之后：`NSSound(named:)` 第一次会拉起整个
        // 音频栈，实测把「卡片上屏」整体拖后 60~600ms。宿主的提问面板早在
        // 模型吐出 tool_use 时就画好了，这几百毫秒正好决定谁先被看见。
        FeedbackService.onArrive()
    }

    /// 待办进度卡片上屏。
    ///
    /// 与 `showCard` 的差别有三处，都是刻意的：
    /// - **不受功能开关门控**：它不拦截任何请求，用户没有需要回应的东西。
    /// - **不进入 `pendingTotal`**：待处理圆点表示「等你处理」，任务进度不是。
    /// - **让位交互式卡片**：提问/权限在屏时不抢占，等它们撤下后由
    ///   `handleCardDismissal` 把进度接回来。
    private func presentTodoCard() {
        guard todoController.hasTodo else { return }
        if activeCard == .question || activeCard == .permission { return }
        activeCard = .todo
        refreshPinned()
        manualCollapseUntil = nil
        manualCollapseNeedsMouseExit = false
        collapseAt = nil
        if !expanded {
            expanded = true
            expandedAt = Date()
            isClosing = false
            closingCard = nil
        }
        // 每个 todo 事件都会走到这里；高度没变时不必再推进画布，
        // 否则同一尺寸反复 animateTo 会让岛面出现细微抖动。
        let size = targetSizeForCurrentCard()
        if size != surfaceSize { animateTo(size: size) }
        syncKeyFocus()
        // 全部完成：留 2.5s 给人看清「全部完成」，再自动收起（钉住时不收）。
        if todoController.progress.isFinished {
            scheduleAutoCollapse(after: 2.5)
        } else {
            cancelAutoCollapse()
        }
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
        } else if todoController.hasTodo {
            // 交互式卡片撤下后，把仍在进行中的任务进度接回来（不必等下一次 todo 事件）。
            activeCard = .todo
            animateTo(size: targetSizeForCurrentCard())
            if todoController.progress.isFinished { scheduleAutoCollapse(after: 2.5) }
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
        case .todo:
            // 高度随「有没有下一步」在 96 / 120 之间切换；全部完成时回到无下一步形态。
            let progress = todoController.progress
            let showsNext = progress.next != nil && !progress.isFinished
            return CGSize(width: NotchLayout.questionCardWidth,
                          height: geometry.safeContentTop
                            + TodoCardLayout.contentHeight(showsNext: showsNext))
        case .none:
            // 空闲状态：不应展开，返回最小尺寸
            return CGSize(width: NotchLayout.expandedWidth,
                          height: NotchLayout.expandedHeight)
        }
    }
    
    /// 提问卡片的目标高度（含刘海安全区）。
    ///
    /// 内容高度由 `QuestionCardLayout` 这个纯函数算出（与视图结构逐段对齐、可单测），
    /// 这里只负责注入运行时的度量值并补上 `safeContentTop`。
    private func questionCardHeight() -> CGFloat {
        let q = questionController.prompt
        let metrics = QuestionCardLayout.Metrics(
            cardWidth: NotchLayout.questionCardWidth,
            cardInset: NotchLayout.cardInset,
            badgeSize: IDEIconProvider.badgeSize,
            bodyFont: NotchLayout.questionBodyFont,
            optionFont: NotchLayout.optionFont,
            descFont: NotchLayout.descFont,
            optionRowMin: NotchLayout.questionOptionRowMin,
            sendHeight: NotchLayout.questionSendHeight,
            minHeight: CGFloat(Settings.shared.cardMinHeight))
        let hasProject = !(q?.host?.cwd ?? "").isEmpty
        return QuestionCardLayout.contentHeight(question: q?.question,
                                                hasProject: hasProject,
                                                metrics: metrics)
            + geometry.safeContentTop
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
    
    /// 呼吸灯该亮什么颜色；`nil` 表示熄灭。
    ///
    /// 规则只有一条：**通知卡片未被查看就自动收起**（`hasUnprocessedNotice`）时才亮，
    /// 颜色取那条通知的提供方主题色。其余任何时刻（空闲、展开中、已读）都必须熄灭——
    /// 呼吸灯是「你错过了一条通知」的提示，常亮会把它降级成装饰，反而失去提醒作用。
    ///
    /// 颜色缺失时退回强调色而不是「保持上一次的颜色」：否则会出现读取了通知、
    /// 状态已清，灯却还亮着的错觉。
    static func glowColor(hasUnprocessedNotice: Bool, noticeTint: Color?) -> Color? {
        guard hasUnprocessedNotice else { return nil }
        if let noticeTint { return noticeTint }
        let accent = NotchLayout.accentColor
        return Color(red: accent.r, green: accent.g, blue: accent.b)
    }

    /// 按当前状态更新气泡外缘呼吸辉光。
    ///
    /// 辉光由 AppKit 画布层（NotchCanvas.glowLayer：单层位图 = 轮廓填充 + 高斯模糊 + 描边芯）
    /// 绘制，而非 SwiftUI 层——因为黑色岛面轮廓由 AppKit 遮罩裁剪，SwiftUI 内容无法越出气泡外缘。
    private func updateBreathingTint() {
        let color = Self.glowColor(hasUnprocessedNotice: hasUnprocessedNotice,
                                   noticeTint: unprocessedNoticeTint)
        breathingTint = color
        // 只在亮/灭翻转时记一行：这条路径由 updatePendingTotal 频繁触发，
        // 每次都打会把日志刷满，反而看不清状态到底什么时候变的。
        if lastGlowLit != (color != nil) {
            lastGlowLit = color != nil
            Log.info("呼吸灯：\(color == nil ? "熄灭" : "点亮")（未读通知=\(hasUnprocessedNotice)）",
                     topic: "glow")
        }
        guard let color else {
            windowHost?.setGlow(color: nil, breathing: false)
            return
        }
        windowHost?.setGlow(color: NSColor(color),
                            breathing: !Settings.shared.reduceMotionResolved)
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
        // 鼠标已移出，解除「手动收起后需先移出再移入」的限制。
        manualCollapseNeedsMouseExit = false
        // 恢复自动收起截止时刻。
        if let held = autoCollapseHeld {
            autoCollapseAt = held
            autoCollapseHeld = nil
        }
        // 按需模式：鼠标移开后安排延迟收起，交互式卡片也遵循——否则「固定 / 按需」
        // 对提问卡片毫无区别，图钉看起来就是个不起作用的装饰。收起后气泡仍保留
        // 待处理圆点，点击即可恢复，不会丢掉等待回答的请求。
        Log.debug("mouseExited: pinned=\(pinned), expanded=\(expanded), activeCard=\(activeCard)", topic: "hover")
        if !pinned && expanded && activeCard != .none {
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
            } else if !hoverExpanded && !manualCollapseNeedsMouseExit {
                hoverExpanded = true
                expand(gentle: true)
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
                        // 必须显式刷新：上面的 dismiss() 已同步触发
                        // handleCardDismissal，岛在那时就收起了，collapse() 会命中
                        // `guard expanded` 提前返回，灯就永远不亮。
                        updateBreathingTint()
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

    /// 从 cwd 取项目名（末级目录）：卡片副标题用，缺省为空串。
    private static func projectName(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "" }
        return (cwd as NSString).lastPathComponent
    }

    /// 把一条 socket 消息路由到对应控制器。
    ///
    /// 提问/权限请求受各自开关门控：关掉即忽略，请求回落到 IDE 自己的弹窗。
    private func routeSocketMessage(_ message: AgentSocketMessage) {
        guard let event = SocketEvent(rawValue: message.event) else { return }
        switch event {
        case .questionRequested:
            // 门控：question_enabled 关 → 忽略，请求回落到 IDE。
            guard Settings.shared.questionEnabled || debugBypassGates else { return }
            questionController.handleEvent(event, message: message)
        case .questionAnswered, .questionTimeout:
            questionController.handleEvent(event, message: message)
        case .permissionRequested:
            // 门控：permission_enabled 关 → 忽略，请求回落到 IDE。
            guard Settings.shared.permissionEnabled || debugBypassGates else { return }
            permissionController.handleEvent(event, message: message)
        case .permissionResolved, .permissionTimeout:
            permissionController.handleEvent(event, message: message)
        case .permissionNotice:
            // 权限通知（只提醒，不拦截）：以横幅形式展示，让 Qoder 原生窗做决策。
            Log.debug("routeSocketMessage: permission_notice received, permissionEnabled=\(Settings.shared.permissionEnabled)", topic: "permission")
            guard Settings.shared.permissionEnabled || debugBypassGates else { return }
            noticeController.handlePermissionNotice(message: message)
        case .sessionEnded:
            questionController.handleEvent(.sessionEnded, message: message)
            permissionController.handleEvent(.sessionEnded, message: message)
            // 待办归属会话：会话结束后残留的进度会一直挂在岛上，必须一并清掉。
            todoController.handleSessionEnded(message.sessionID)
            if activeCard == .todo, !todoController.hasTodo { handleCardDismissal() }
        case .turnFinished:
            noticeController.handleTurnFinished(message: message)
            // 回合结束：清掉本会话的任务进度。正常完成路径靠这里立即清空，
            // 兜底超时（todoIdleTimeout）只需兜住「手动中断」这种不发事件的场景。
            todoController.handleSessionEnded(message.sessionID)
            if activeCard == .todo, !todoController.hasTodo { handleCardDismissal() }
            // 回合结束同样意味着：阻塞式提问卡（AskUserQuestion）不再有宿主在等答案。
            // 手动停止模型生成时宿主也发 Stop → turn_finished，此时应把挂在岛上的
            // 提问卡一并收掉，否则它会一直等一个永远不会来的作答。
            questionController.handleEvent(.sessionEnded, message: message)
        case .todoUpdated, .todoItemUpdated:
            // 待办不拦截任何请求，也不参与待处理计数：它只是过程可视化。
            let provider = message.resolvedProvider
            let name = AgentProvider.label(provider: provider,
                                           hostName: message.host?["name"]?.stringValue,
                                           bundleID: message.host?["bundle"]?.stringValue)
            todoController.ingest(payload: message.payload,
                                  sessionID: message.sessionID,
                                  provider: provider,
                                  providerName: name,
                                  project: Self.projectName(from: message.cwd))
            presentTodoCard()
        case .todoCleared:
            todoController.reset()
            if activeCard == .todo { handleCardDismissal() }
        case .activity:
            showHistory()  // 临时：供脚本触发打开历史，便于调试
        }
    }

    // MARK: - 调试注入

    /// 调试注入时跳过「提醒 / 提问 / 权限」三个开关。
    ///
    /// 调试面板要能在用户把提醒全关掉的情况下预览卡片——否则一按没反应，
    /// 分不清是「门控关了」还是「卡片坏了」。正常 socket 分发恒为 false。
    private var debugBypassGates = false

    /// 注入一条与 hook 完全同构的消息，走同一套分发（仅绕过功能开关）。
    func injectDebugMessage(_ message: AgentSocketMessage) {
        debugBypassGates = true
        noticeController.bypassGates = true
        defer {
            debugBypassGates = false
            noticeController.bypassGates = false
        }
        routeSocketMessage(message)
    }

    /// 清掉所有待处理的卡片与横幅：**不写应答文件、不触发跳转**。
    ///
    /// 用 `flushAll(notify: false)` 而不是正常收起：注入下一条场景时，应该直接
    /// 换内容，而不是先播一遍收起动画再播展开动画。
    func flushDebugChannels() {
        questionController.flushAll(notify: false)
        permissionController.flushAll(notify: false)
        noticeController.flushAll()
        todoController.reset()
    }

    /// 清空卡片并把灵动岛收回去（带正常收起动画）。
    func clearDebugCards() {
        flushDebugChannels()
        handleCardDismissal()
        Log.info("调试：已清空所有卡片", topic: "debug")
    }

    /// 清空历史记录与未处理标记。
    func clearDebugHistory() {
        historyController.clear()
        hasUnprocessedNotice = false
        unprocessedNoticeTint = nil
        updateBreathingTint()
        updatePendingTotal()
        Log.info("调试：已清空历史记录", topic: "debug")
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
    /// 手动偏好全局共享——在任意卡片上切换，对所有卡片生效。
    func togglePin() {
        let next = !pinned
        Log.info("togglePin called: before pinned=\(pinned), activeCard=\(activeCard)", topic: "pin")
        userPinned = next
        applyPinned(next)
        // 切换必须立刻可见。原先只改了一个布尔值，而提问 / 权限卡片从来不会
        // 自动收起，于是点图钉除了图标换色之外什么都没发生。
        if next {
            // 固定模式：正在等待回答却被收起的卡片立即展开。
            if activeCard != .none, !expanded {
                manualCollapseUntil = nil
                manualCollapseNeedsMouseExit = false
                expand()
            }
        } else if expanded, !hovering, activeCard != .none {
            // 按需模式：鼠标已离开，按悬停延迟收起（气泡保留圆点可恢复）。
            collapseAt = Date().addingTimeInterval(Self.hoverCollapseDelay)
            ensureHoverTimer()
        }
        Log.info("图钉切换 pinned=\(pinned), expanded=\(expanded)", topic: "pin")
    }

    /// 从共享偏好解析置顶状态：用户手动切换过以用户为准，否则实时跟随设置。
    private func refreshPinned() {
        applyPinned(userPinned ?? Settings.shared.pinByDefault)
    }

    /// 置顶状态的唯一落点：写 published 值并同步自动收起调度。
    /// 四类卡片共用这一份状态，切换卡片不再各自重置。
    private func applyPinned(_ newValue: Bool) {
        guard pinned != newValue else { return }
        pinned = newValue
        if newValue {
            // 钉住：取消任何待执行的自动收起，并作废手动收起的让位期。
            cancelAutoCollapse()
            collapseAt = nil
            manualCollapseUntil = nil
            manualCollapseNeedsMouseExit = false
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
        restartTodoIdleTimer()
        // 设置面板切换「卡片默认固定展示」时以设置为准：清掉进程内的手动覆盖，
        // 否则用户点过一次图钉后，这个开关就永远不起作用了。
        // 其它设置变更仍按共享偏好重解析（手动偏好优先）。
        let defaultPinned = Settings.shared.pinByDefault
        var switchedToFixed = false
        if defaultPinned != lastPinByDefault {
            lastPinByDefault = defaultPinned
            userPinned = nil
            applyPinned(defaultPinned)
            switchedToFixed = defaultPinned
        } else if activeCard != .none {
            refreshPinned()
        }
        guard windowHost != nil else { return }
        let size = expanded ? targetSizeForCurrentCard()
                            : geometry.restingSize(showsContent: true)  // 收起态也使用 bubbleWidth/bubbleHeight
        // 给 surfaceSize 赋值（哪怕是相同值）会重新发布，使 SwiftUI 内容重渲染、
        // 采纳新的字号 / 颜色。
        surfaceSize = size
        windowHost?.present(size: size, geometry: geometry, animated: false, showsContent: expanded)
        // 切回「固定」时若正有卡片等待回答却处于收起态，立即展开，保持"改动即刻生效"。
        if switchedToFixed, activeCard != .none, !expanded {
            manualCollapseUntil = nil
            manualCollapseNeedsMouseExit = false
            expand()
        }
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

    // MARK: - 任务进度无事件兜底

    /// 任务进度卡片的「无新事件」清扫定时器。
    ///
    /// 手动停止 Qoder/Claude 等宿主的 session 时，它们不触发任何 hook 事件
    /// （无 Stop / SessionEnd / PostToolUseFailure），岛侧收不到清空信号，
    /// 进度会一直挂在岛上。唯一可靠的兜底是「长时间没新事件就自动收起」。
    ///
    /// 周期取 `todoIdleTimeout` 的一半（至少 1s），保证判定滞后不超过 1~2 秒，
    /// 而不是等到几十秒一次的常规清扫才轮到。
    private var todoIdleTimer: Timer?

    private func restartTodoIdleTimer() {
        todoIdleTimer?.invalidate()
        let timeout = max(3, Settings.shared.todoIdleTimeout)
        let interval = TimeInterval(max(1, timeout / 2))
        todoIdleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sweepIdleTodo()
        }
        if let timer = todoIdleTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    /// 若任务进度已超过 `todoIdleTimeout` 秒没有新事件，则清空并收起。
    private func sweepIdleTodo() {
        guard todoController.hasTodo, activeCard == .todo else { return }
        let timeout = TimeInterval(max(3, Settings.shared.todoIdleTimeout))
        guard todoController.shouldDismissIdle(after: timeout) else { return }
        Log.info("待办 \(timeout)s 无新事件，兜底清空收起", topic: "todo")
        todoController.reset()
        handleCardDismissal()
    }
}
