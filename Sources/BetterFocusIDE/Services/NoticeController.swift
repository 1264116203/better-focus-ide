// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 管理瞬态的"轮次完成"横幅：按会话去抖重复、在有卡片等待用户时跳过、超时后自动消失。
final class NoticeController: ObservableObject {
    @Published private(set) var notice: TurnNotice?

    /// 横幅应出现 / 消失时的回调（驱动灵动岛展开）。
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// 每个完成的轮次都回调一次以记入历史——即便是弹不出横幅的 CLI 会话，
    /// 也要留下痕迹供日后回顾。
    var onRemember: ((TurnNotice) -> Void)?

    /// 有交互式卡片在屏上时抑制横幅。
    var hasPendingCard: () -> Bool = { false }
    /// 为 true 时横幅被钉住展开，不得自动消失。
    var isPinned: () -> Bool = { false }

    /// 调试注入用：为 true 时跳过 `turnNotifyEnabled` / `permissionEnabled` 门控。
    ///
    /// 只有调试面板会打开它（用户可能在设置里把提醒全关掉了，但预览仍要能弹出来），
    /// 正常 socket 分发恒为 false。见 `NotchService.injectDebugMessage`。
    var bypassGates = false

    /// 每个会话上次横幅的时间，用于去抖。
    private var lastNoticeAt: [String: Date] = [:]
    /// 等待展示的通知队列；当前通知展示期间新到的通知排入此队列。
    private var queue: [TurnNotice] = []
    /// 自动收起时保存的通知，供用户点击气泡时重新展示（而非直接打开历史）。
    private var lastDismissedNotice: TurnNotice?

    var hasActiveNotice: Bool { notice != nil }
    /// 总数（当前 + 队列）——驱动收起态的待处理圆点。
    var count: Int { (notice != nil ? 1 : 0) + queue.count }
    /// 未读通知总数（含当前展示的），驱动卡片右上角的未读数字徽章。
    var queueCount: Int { (notice != nil ? 1 : 0) + queue.count }
    /// 队列中是否有等待展示的通知（不含当前展示的）。
    var hasQueuedNotices: Bool { !queue.isEmpty }
    /// 待处理圆点的提供方主题色。
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let p = notice?.provider,
              let provider = AgentProvider(rawValue: p) else { return nil }
        let rgb = provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - 事件入口

    /// 处理一条 `turn_finished` 消息：开关校验 → 去抖 → 解析 → 记历史 → 入队或展示。
    func handleTurnFinished(message: AgentSocketMessage) {
        let settings = Settings.shared
        guard settings.turnNotifyEnabled || bypassGates else { return }

        let sessionID = message.sessionID
        let now = Date()
        // 去抖：多个子会话会背靠背上报 idle。
        if let last = lastNoticeAt[sessionID],
           now.timeIntervalSince(last) < settings.notifyBannerDuration * 0.4 {
            return
        }

        guard let parsed = TurnNotice.parse(message: message) else { return }
        if lastNoticeAt.count > 32 { lastNoticeAt.removeAll() }
        lastNoticeAt[sessionID] = now

        // 每个完成的轮次先记入历史。`qodercli` 会话（无头 autocommit 式脚本）留痕
        // 但不抢占屏幕——它的"用户输入"是被管道进来的 diff，而非用户正在等待的内容。
        onRemember?(parsed)
        if parsed.fromCLI { return }

        // 已有通知在屏或有交互卡片等待用户时，入队而非替换。
        if hasActiveNotice || hasPendingCard() {
            queue.append(parsed)
            return
        }
        show(parsed)
    }

    /// 处理一条 `permission_notice` 消息：权限申请只通知不拦截，以横幅形式展示。
    func handlePermissionNotice(message: AgentSocketMessage) {
        let settings = Settings.shared
        Log.debug("handlePermissionNotice: entry, permissionEnabled=\(settings.permissionEnabled), session=\(message.sessionID)", topic: "permission")
        guard settings.permissionEnabled || bypassGates else {
            Log.debug("handlePermissionNotice: blocked by permissionEnabled=false", topic: "permission")
            return
        }

        let sessionID = message.sessionID
        let now = Date()
        // 去抖
        if let last = lastNoticeAt[sessionID],
           now.timeIntervalSince(last) < settings.notifyBannerDuration * 0.4 {
            Log.debug("handlePermissionNotice: debounced (interval=\(now.timeIntervalSince(last))s)", topic: "permission")
            return
        }
        if hasPendingCard() {
            Log.debug("handlePermissionNotice: queuing (hasPendingCard=true)", topic: "permission")
        }

        // 从 permission_notice 构造一条通知
        let providerEnum = message.resolvedProvider
        let provider = providerEnum.rawValue
        let name = providerEnum.displayName
        let host = HostInfo(from: message.host,
                            cwd: message.cwd)
        let toolName = message.payload?["tool_name"]?.stringValue ?? ""
        let resources = message.payload?["resources"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        let detail = resources.first ?? ""
        // Notification 类权限提醒只带文案、没有 tool_name；从「permission to use Bash」
        // 里抠出工具名，标题才不会一律退化成「操作」。
        let resolvedToolName = toolName.isEmpty ? PermissionRequest.toolNameHint(from: detail) : toolName
        // 提问工具从权限通道冒出来时不弹横幅：它不是权限申请，问题卡片或宿主
        // 自带的问卷面板已经在问了（见 QuestionTakeover）。
        if PermissionRequest.isQuestionTool(resolvedToolName) {
            Log.info("handlePermissionNotice: 跳过提问工具的权限横幅 tool=\(resolvedToolName)", topic: "permission")
            return
        }
        let action = PermissionRequest.actionFromToolName(resolvedToolName)
        let title = "Agent 请求执行「\(PermissionRequest.actionLabel(action))」"
        let hostLabel = AgentProvider.label(provider: providerEnum,
                                            hostName: host.name,
                                            bundleID: host.bundle)
        let body = detail.isEmpty ? "请在 \(hostLabel) 对话框中做出决策" : detail
        let project = host.cwd.isEmpty ? "" : (host.cwd as NSString).lastPathComponent

        Log.info("handlePermissionNotice: notice title='\(title)', host=\(host.name), tool=\(resolvedToolName)", topic: "permission")

        let notice = TurnNotice(
            provider: provider,
            providerName: host.name.isEmpty ? name : host.name,
            sessionID: sessionID,
            title: title,
            body: body,
            bodyIsFallback: false,
            kind: .permission,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: Settings.shared.permissionNoticeJump,
            fromCLI: false
        )

        if lastNoticeAt.count > 32 { lastNoticeAt.removeAll() }
        lastNoticeAt[sessionID] = now

        onRemember?(notice)
        // 已有通知在屏或有交互卡片时，入队而非替换。
        if hasActiveNotice || hasPendingCard() {
            queue.append(notice)
            return
        }
        show(notice)
    }

    // MARK: - 展示 / 消失

    /// 展示一条通知：设置 notice 并触发 onPresent 回调。
    func show(_ newNotice: TurnNotice) {
        // 已有通知在屏时，新通知入队等待。
        if notice != nil {
            queue.append(newNotice)
            return
        }
        notice = newNotice
        lastDismissedNotice = nil  // 新通知取代旧的未恢复通知
        onPresent?()
        FeedbackService.onArrive()
        // 自动收起由 NotchService 的悬停计时器统一管理。
    }

    /// 当前通知被处理（点击/自动收起）后，从队列中弹出下一条。
    private func promoteNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        notice = next
        onPresent?()
        FeedbackService.onArrive()
    }

    /// 外部（NotchService）在交互卡片移除后调用：若队列有排队通知则弹出下一条。
    func promoteNextFromQueue() {
        promoteNext()
    }

    /// 钉住状态在横幅展示期间翻转时调用。
    /// NotchService 管理自动收起计时器，这里只标记状态变化。
    func applyPinChange() {
        // 空实现：自动收起由外部 NotchService 管理。
    }

    func dismiss() {
        guard notice != nil else { return }
        notice = nil
        onDismiss?()
        // promoteNext 由 NotchService.handleCardDismissal 统一处理，避免双重弹出。
    }

    /// 清空横幅、排队项与「收起后可恢复」的缓存（**不写应答、不播放动画**）。
    ///
    /// 只给调试面板用：注入下一条场景前先清场，避免同一帧里先收起再展开。
    func flushAll() {
        queue.removeAll()
        lastDismissedNotice = nil
        notice = nil
    }

    /// 用户点击"已读"按钮：不跳转 IDE，直接标记已读并关闭当前通知。
    func markRead() {
        dismiss()
    }

    /// 用户点击横幅：先按需跳回 IDE，再消失（并弹出队列中下一条）。
    func tapped() {
        guard let notice = notice else { return }
        if notice.jumpEnabled {
            IDELauncher.activateAsync(provider: notice.provider, host: notice.host)
        }
        dismiss()
    }

    // MARK: - 自动收起恢复

    /// 保存当前通知供后续恢复展示（收起前调用，在 dismiss 之前）。
    /// 返回 true 表示实际保存了通知（当前有活动通知时）。
    @discardableResult
    func saveForRestore() -> Bool {
        guard let n = notice else { return false }
        lastDismissedNotice = n
        return true
    }

    /// 恢复上次自动收起的通知：取出并清除缓存。
    func restoreLastDismissed() -> TurnNotice? {
        let n = lastDismissedNotice
        lastDismissedNotice = nil
        return n
    }
}
