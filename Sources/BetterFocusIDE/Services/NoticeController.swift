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

    /// 每个会话上次横幅的时间，用于去抖。
    private var lastNoticeAt: [String: Date] = [:]

    var hasActiveNotice: Bool { notice != nil }
    /// 总数——驱动收起态的待处理圆点。
    var count: Int { notice != nil ? 1 : 0 }
    /// 待处理圆点的提供方主题色。
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let p = notice?.provider,
              let provider = AgentProvider(rawValue: p) else { return nil }
        let rgb = provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - 事件入口

    /// 处理一条 `turn_finished` 消息：开关校验 → 去抖 → 让位卡片 → 解析 → 记历史 → 展示。
    func handleTurnFinished(message: AgentSocketMessage) {
        let settings = Settings.shared
        guard settings.turnNotifyEnabled else { return }

        let sessionID = message.sessionID
        let now = Date()
        // 去抖：多个子会话会背靠背上报 idle。
        if let last = lastNoticeAt[sessionID],
           now.timeIntervalSince(last) < settings.notifyBannerDuration * 0.4 {
            return
        }
        // 不要盖住正在等用户的卡片。
        if hasPendingCard() { return }

        guard let parsed = TurnNotice.parse(message: message) else { return }
        if lastNoticeAt.count > 32 { lastNoticeAt.removeAll() }
        lastNoticeAt[sessionID] = now

        // 每个完成的轮次先记入历史。`qodercli` 会话（无头 autocommit 式脚本）留痕
        // 但不抢占屏幕——它的"用户输入"是被管道进来的 diff，而非用户正在等待的内容。
        onRemember?(parsed)
        if parsed.fromCLI { return }

        show(parsed)
    }

    /// 处理一条 `permission_notice` 消息：权限申请只通知不拦截，以横幅形式展示。
    func handlePermissionNotice(message: AgentSocketMessage) {
        let settings = Settings.shared
        Log.debug("handlePermissionNotice: entry, permissionEnabled=\(settings.permissionEnabled), session=\(message.sessionID)", topic: "permission")
        guard settings.permissionEnabled else {
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
            Log.debug("handlePermissionNotice: skipped, hasPendingCard=true", topic: "permission")
            return
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
        let action = PermissionRequest.actionFromToolName(toolName)
        let title = "Agent 请求执行「\(PermissionRequest.actionLabel(action))」"
        let body = detail.isEmpty ? "请在 Qoder 对话框中做出决策" : detail
        let project = host.cwd.isEmpty ? "" : (host.cwd as NSString).lastPathComponent

        Log.info("handlePermissionNotice: showing notice title='\(title)', host=\(host.name), tool=\(toolName)", topic: "permission")

        let notice = TurnNotice(
            provider: provider,
            providerName: host.name.isEmpty ? name : host.name,
            sessionID: sessionID,
            title: title,
            body: body,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: Settings.shared.permissionNoticeJump,
            fromCLI: false
        )

        if lastNoticeAt.count > 32 { lastNoticeAt.removeAll() }
        lastNoticeAt[sessionID] = now

        onRemember?(notice)
        show(notice)
    }

    // MARK: - 展示 / 消失

    private func show(_ newNotice: TurnNotice) {
        notice = newNotice
        onPresent?()
        FeedbackService.onArrive()
        // 自动收起由 NotchService 的悬停计时器统一管理。
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
    }

    /// 用户点击横幅：先按需跳回 IDE，再消失。
    func tapped() {
        guard let notice = notice else { return }
        if notice.jumpEnabled {
            IDELauncher.activateAsync(provider: notice.provider, host: notice.host)
        }
        dismiss()
    }
}
