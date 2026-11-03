// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 管理权限卡片状态：当前请求、等待队列、决策下发。
final class PermissionController: ObservableObject {
    /// 当前展示的权限请求（nil 表示无活动卡片）。
    @Published private(set) var request: PermissionRequest?
    /// 已做出的决策（非 nil 表示已应答、正待收起）。
    @Published private(set) var choice: PermissionDecisionValue?

    /// 待展示的权限请求队列。
    private var queue: [PermissionRequest] = []

    /// 卡片状态变化回调（触发灵动岛展开 / 收起）。
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var hasActiveCard: Bool { request != nil }
    var pendingCount: Int { queue.count }
    /// 总数（活动 + 队列）——驱动收起态的待处理圆点。
    var count: Int { (request != nil ? 1 : 0) + queue.count }
    /// 待处理圆点的提供方主题色（取最高优先级项）。
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let req = request else { return nil }
        let rgb = req.provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - Socket 事件入口

    /// 处理路由进来的 socket 事件。
    func handleEvent(_ event: SocketEvent, message: AgentSocketMessage) {
        switch event {
        case .permissionRequested:
            guard let provider = AgentProvider(rawValue: message.provider),
                  var req = PermissionRequest.parse(
                    payload: message.payload, provider: provider,
                    sessionID: message.sessionID) else { return }
            let host = HostInfo(from: message.host,
                                cwd: message.payload?["cwd"]?.stringValue)
            req.host = host.isEmpty ? nil : host
            present(req)

        case .permissionResolved, .permissionTimeout:
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            clearCurrent(requestID: requestID)

        case .sessionEnded:
            dropSession(sessionID: message.sessionID)

        default: break
        }
    }

    // MARK: - 展示 / 收起

    /// 展示一个新请求。
    ///
    /// 同 requestID+sessionID 在未应答时重发 → 直接替换；否则入队，超过
    /// `permissionQueueLimit` 时丢最旧的，确保最新请求不丢失。
    func present(_ newRequest: PermissionRequest) {
        // 同请求重发：替换
        if let current = request, choice == nil,
           current.requestID == newRequest.requestID,
           current.sessionID == newRequest.sessionID {
            request = newRequest
            onPresent?()
            return
        }
        if request != nil || !queue.isEmpty {
            queue.append(newRequest)
            let limit = max(1, Settings.shared.permissionQueueLimit)
            if queue.count > limit { queue.removeFirst(queue.count - limit) }
            return
        }
        request = newRequest
        onPresent?()
    }

    /// 若当前请求匹配该 requestID，则收起。
    func clearCurrent(requestID: String) {
        guard let current = request else { return }
        if current.requestID == requestID && current.sessionID == current.sessionID {
            dismiss()
        } else if !requestID.isEmpty {
            // 按 ID 匹配
            if current.requestID == requestID { dismiss() }
        }
    }

    /// 会话结束：收起该会话的当前请求并从队列移除其所有待展示项。
    func dropSession(sessionID: String) {
        if request?.sessionID == sessionID { dismiss() }
        queue.removeAll { $0.sessionID == sessionID }
    }

    /// 清理没人再等待的卡片：hook 已超时（等待上限 + 缓冲 + 宽限），请求已回落到 IDE。
    func sweepStale(olderThan deadline: TimeInterval) {
        let now = Date()
        queue.removeAll { now.timeIntervalSince($0.arrivedAt) > deadline }
        if let r = request, choice == nil, now.timeIntervalSince(r.arrivedAt) > deadline {
            dismiss()
        }
    }

    /// 收起当前请求，随后提升队列里的下一个。
    private func dismiss() {
        request = nil
        choice = nil
        onDismiss?()
        promoteNext()
    }

    /// 队首请求提升为当前卡片。
    private func promoteNext() {
        guard request == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        request = next
        onPresent?()
    }

    // MARK: - 用户决策

    /// 做出决策：下发应答文件，记录 choice，给一次反馈，短暂停留后收起。
    func decide(_ decision: PermissionDecisionValue) {
        guard let req = request, choice == nil else { return }
        AnswerDispatcher.dispatchPermissionDecision(
            sessionID: req.sessionID, requestID: req.requestID, decision: decision)
        choice = decision
        FeedbackService.onAnswer()
        // 短暂反馈后收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismiss()
        }
    }
}
