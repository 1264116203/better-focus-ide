// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 管理瞬态的"轮次完成"横幅：按会话去抖重复、在有卡片等待用户时跳过、超时后自动消失。
///
/// 同一会话只留最新一条未读。更新的通知到达时，这条会话里更早的（正在展示、
/// 排在后面、以及收起后还能点开的）都视为已读，不再要求逐条点掉。
final class NoticeController: ObservableObject {
    @Published private(set) var notice: TurnNotice?

    /// 横幅应出现 / 消失时的回调（驱动灵动岛展开）。
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// 每个完成的轮次都回调一次以记入历史——即便是弹不出横幅的 CLI 会话，
    /// 也要留下痕迹供日后回顾。
    var onRemember: ((TurnNotice) -> Void)?
    /// 队列条数变了、但没有换上屏通知时刷新待处理计数。
    var onQueueChanged: (() -> Void)?
    /// 收起后待恢复的那条被同一会话的更新顶掉，呼吸灯应熄灭。
    var onSupersededResting: (() -> Void)?

    /// 有交互式卡片在屏上时抑制横幅。
    var hasPendingCard: () -> Bool = { false }
    /// 为 true 时横幅被钉住展开，不得自动消失。
    var isPinned: () -> Bool = { false }

    /// 调试注入用：为 true 时跳过 `turnNotifyEnabled` / `permissionEnabled` 门控。
    ///
    /// 只有调试面板会打开它（用户可能在设置里把提醒全关掉了，但预览仍要能弹出来），
    /// 正常 socket 分发恒为 false。见 `NotchService.injectDebugMessage`。
    var bypassGates = false

    /// 每个去抖键上次横幅的时间与内容指纹，用于丢掉背靠背的重复上报。
    private var lastNoticeAt: [String: Date] = [:]
    private var lastFingerprint: [String: String] = [:]
    /// 等待展示的通知队列。同一会话在队列里至多一条，后来的顶掉更早的。
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

        guard let parsed = TurnNotice.parse(message: message) else { return }
        // 去抖只丢掉内容相同的背靠背上报。同一会话内容变了，是更新的一轮，要留下。
        if isRepeat(parsed, key: message.sessionID, now: Date()) { return }

        // 每个完成的轮次先记入历史。`qodercli` 会话（无头 autocommit 式脚本）留痕
        // 但不抢占屏幕——它的"用户输入"是被管道进来的 diff，而非用户正在等待的内容。
        onRemember?(parsed)
        if parsed.fromCLI { return }

        deliver(parsed)
    }

    /// 处理一条 `permission_notice` 消息：权限申请只通知不拦截，以横幅形式展示。
    func handlePermissionNotice(message: AgentSocketMessage) {
        let settings = Settings.shared
        Log.debug("handlePermissionNotice: entry, permissionEnabled=\(settings.permissionEnabled), session=\(message.sessionID)", topic: "permission")
        guard settings.permissionEnabled || bypassGates else {
            Log.debug("handlePermissionNotice: blocked by permissionEnabled=false", topic: "permission")
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
            sessionID: message.sessionID,
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

        if isRepeat(notice, key: message.sessionID, now: Date()) {
            Log.debug("handlePermissionNotice: 内容相同，去抖丢弃", topic: "permission")
            return
        }

        onRemember?(notice)
        deliver(notice)
    }

    /// WorkBuddy 提问：不接管作答，只留一张可点的通知，点一下跳回宿主。
    func handleQuestionNotice(message: AgentSocketMessage) {
        guard Settings.shared.questionEnabled || bypassGates else { return }
        let sessionID = message.sessionID
        let providerEnum = message.resolvedProvider
        let host = HostInfo(from: message.host, cwd: message.cwd)
        let name = AgentProvider.label(provider: providerEnum,
                                       hostName: host.name,
                                       bundleID: host.bundle)
        let title = message.payload?["title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = message.payload?["body"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = (title?.isEmpty == false) ? title! : "需要你的回答"
        let detail = (body?.isEmpty == false) ? body! : "请在 \(name) 里回答"
        let project = host.cwd.isEmpty ? "" : (host.cwd as NSString).lastPathComponent
        let notice = TurnNotice(
            provider: providerEnum.rawValue,
            providerName: name,
            sessionID: sessionID,
            title: headline,
            body: detail,
            bodyIsFallback: body?.isEmpty != false,
            kind: .question,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: true,
            fromCLI: false
        )
        if isRepeat(notice, key: sessionID + ":question", now: Date()) { return }
        onRemember?(notice)
        deliver(notice)
    }

    /// 失败、子任务、待审阅、上下文压缩。都是横幅，不拦截宿主。
    ///
    /// 跟着回合提醒开关走：关掉「回合完成」时，这几张状态卡也不响。
    func handleStatusNotice(message: AgentSocketMessage, kind: HistoryKind) {
        guard Settings.shared.turnNotifyEnabled || bypassGates else { return }
        let sessionID = message.sessionID
        let now = Date()
        let providerEnum = message.resolvedProvider
        let host = HostInfo(from: message.host, cwd: message.cwd)
        let name = AgentProvider.label(provider: providerEnum,
                                       hostName: host.name,
                                       bundleID: host.bundle)
        let title = message.payload?["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = message.payload?["body"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let headline: String
        if let title, !title.isEmpty {
            headline = title
        } else {
            switch kind {
            case .failure: headline = "这一轮没有完成"
            case .subagent: headline = "子任务完成"
            case .review: headline = "需要你看一眼"
            case .compact: headline = "上下文已压缩"
            case .question, .permission, .turn: headline = name
            }
        }
        let detail = (body?.isEmpty == false) ? body! : name
        let project = host.cwd.isEmpty ? "" : (host.cwd as NSString).lastPathComponent
        let notice = TurnNotice(
            provider: providerEnum.rawValue,
            providerName: name,
            sessionID: sessionID,
            title: headline,
            body: detail,
            bodyIsFallback: body?.isEmpty != false,
            kind: kind,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: now,
            jumpEnabled: Settings.shared.turnNotifyJump,
            fromCLI: false
        )
        if isRepeat(notice, key: sessionID + ":" + kind.rawValue, now: now) { return }
        onRemember?(notice)
        deliver(notice)
    }

    // MARK: - 同一会话只留最新

    /// 一条通知在未读队列里的位置。
    struct Slot {
        var current: TurnNotice?
        var queued: [TurnNotice]
        var resting: TurnNotice?
    }

    /// `admit` 对屏上内容做的事。
    enum AdmitEffect: Equatable {
        /// 没有别的通知挡着，这条直接上屏。
        case present
        /// 屏上就是同一会话的旧通知，就地换成这条，不收起再展开。
        case replace
        /// 屏上是别的会话，或提问/权限卡还在等用户。这条只排队。
        /// `retiredResting`：收起后还能点开的那条属于本会话，已经被顶掉。
        case enqueue(retiredResting: Bool)
    }

    /// 收下一条通知。同一会话只留最新一条：正在展示、排队、以及收起待恢复的旧通知都视为已读。
    ///
    /// 提问或权限卡还占着岛时（`blocked`），不把横幅抢到前台。同会话正在垫着的那条
    /// 也清掉，只把最新的留在队列里，等卡片撤下再弹出。
    static func admit(_ incoming: TurnNotice, into slot: Slot, blocked: Bool) -> (slot: Slot, effect: AdmitEffect) {
        var slot = slot
        let session = incoming.sessionID
        var retiredResting = false
        if !session.isEmpty {
            slot.queued.removeAll { $0.sessionID == session }
            if slot.resting?.sessionID == session {
                slot.resting = nil
                retiredResting = true
            }
        }
        if !session.isEmpty, slot.current?.sessionID == session {
            if blocked {
                slot.current = nil
                slot.queued.append(incoming)
                return (slot, .enqueue(retiredResting: retiredResting))
            }
            slot.current = incoming
            slot.resting = nil
            return (slot, .replace)
        }
        if slot.current != nil || blocked {
            slot.queued.append(incoming)
            return (slot, .enqueue(retiredResting: retiredResting))
        }
        slot.current = incoming
        slot.resting = nil
        return (slot, .present)
    }

    /// 内容相同且间隔太短：子会话会把同一轮 idle 连报两次，丢掉后到的那次。
    private func isRepeat(_ notice: TurnNotice, key: String, now: Date) -> Bool {
        let fingerprint = "\(notice.kind.rawValue)\u{1f}\(notice.title)\u{1f}\(notice.body)"
        let window = Settings.shared.notifyBannerDuration * 0.4
        if let last = lastNoticeAt[key],
           now.timeIntervalSince(last) < window,
           lastFingerprint[key] == fingerprint {
            return true
        }
        if lastNoticeAt.count > 32 {
            lastNoticeAt.removeAll()
            lastFingerprint.removeAll()
        }
        lastNoticeAt[key] = now
        lastFingerprint[key] = fingerprint
        return false
    }

    /// 把一条通知放进未读集合，并按 `admit` 的结果上屏或排队。
    private func deliver(_ incoming: TurnNotice) {
        let before = Slot(current: notice, queued: queue, resting: lastDismissedNotice)
        let result = Self.admit(incoming, into: before, blocked: hasPendingCard())
        if !incoming.sessionID.isEmpty,
           before.current?.sessionID == incoming.sessionID
            || before.queued.contains(where: { $0.sessionID == incoming.sessionID })
            || before.resting?.sessionID == incoming.sessionID {
            Log.info("会话 \(incoming.sessionID) 有更新的通知，更早的未读已自动标为已读", topic: "notice")
        }
        objectWillChange.send()
        notice = result.slot.current
        queue = result.slot.queued
        lastDismissedNotice = result.slot.resting
        switch result.effect {
        case .present, .replace:
            onPresent?()
            FeedbackService.onArrive()
        case .enqueue(let retiredResting):
            onQueueChanged?()
            if retiredResting { onSupersededResting?() }
        }
    }

    // MARK: - 展示 / 消失

    /// 把一条已经决定要看的通知放到屏上。收起后点气泡恢复走这里。
    func show(_ newNotice: TurnNotice) {
        objectWillChange.send()
        notice = newNotice
        lastDismissedNotice = nil
        onPresent?()
        FeedbackService.onArrive()
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
            IDELauncher.activateAsync(provider: notice.provider, host: notice.host, sessionID: notice.sessionID)
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
