// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 管理问题卡片状态：当前提问、等待队列、各项选择、应答下发。
final class QuestionController: ObservableObject {
    /// 当前展示的提问（nil 表示无活动卡片）。
    @Published private(set) var prompt: AgentQuestionPrompt?
    /// 已提交的选择（非 nil 表示已应答、正待收起）。
    @Published private(set) var choice: AgentQuestionAnswer?
    /// 每个问题 id → 用户当前勾选（未提交）。
    @Published var picks: [String: AgentQuestionAnswer] = [:]
    /// 每个问题 id → "其他…"输入框文本。
    @Published var texts: [String: String] = [:]
    /// 正处于"自己作答"（自定义文本）状态的问题 id 集合。
    @Published var writingOwn: Set<String> = []
    /// 自增计数，通知 SwiftUI 卡片把焦点移入"其他…"输入框（Tab 键触发）。
    @Published private(set) var focusOtherTick = 0

    /// 待展示的提问队列。
    private var queue: [AgentQuestionPrompt] = []

    /// 卡片状态变化回调（触发灵动岛展开 / 收起）。
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var hasActiveCard: Bool { prompt != nil }
    var pendingCount: Int { queue.count }
    /// 总数（活动 + 队列）——驱动收起态的待处理圆点。
    var count: Int { (prompt != nil ? 1 : 0) + queue.count }
    /// 待处理圆点的提供方主题色（取最高优先级项）。
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let p = prompt else { return nil }
        let rgb = p.provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - Socket 事件入口

    /// 处理路由进来的 socket 事件。
    func handleEvent(_ event: SocketEvent, message: AgentSocketMessage) {
        switch event {
        case .questionRequested:
            let questions = AgentQuestionPrompt.parseQuestions(from: message.payload)
            guard !questions.isEmpty else { return }
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            let channel = message.payload?["channel"]?.stringValue ?? "-"
            Log.info("question: 收到提问 channel=\(channel) session=\(message.sessionID)", topic: "question")
            let provider = message.resolvedProvider
            let host = HostInfo(from: message.host,
                                cwd: message.cwd)
            // 岛优先：宿主自己会画提问面板，但那是它在 hook 返回前自绘的，
            // 拦不住；让位的唯一结果是岛上不弹、用户在 IDE 里那次作答被 deny 丢掉。
            // 所以这里默认一律接管（见 QuestionTakeover.Policy）。
            if !QuestionTakeover.shouldTakeOver(
                host: host.isEmpty ? nil : host,
                frontmostBundle: QuestionTakeover.frontmostBundle()) {
                AnswerDispatcher.dispatchDefer(
                    sessionID: message.sessionID,
                    questionIDs: questions.map(\.id),
                    requestID: requestID)
                Log.info("question: 让位给宿主自带的提问面板"
                         + "（\(host.name.isEmpty ? host.bundle : host.name) 正在前台，"
                         + "session=\(message.sessionID)）", topic: "question")
                return
            }

            let newPrompt = AgentQuestionPrompt(
                provider: provider, sessionID: message.sessionID,
                questions: questions, arrivedAt: Date(), requestID: requestID,
                host: host.isEmpty ? nil : host)
            present(newPrompt)

        case .questionAnswered, .questionTimeout:
            let questionID = message.payload?["question_id"]?.stringValue ?? "q1"
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            clearCurrent(questionID: questionID, requestID: requestID)

        case .sessionEnded:
            dropSession(sessionID: message.sessionID)

        default: break
        }
    }

    // MARK: - 展示 / 收起

    /// 展示一个新提问。
    ///
    /// 三种情形：
    /// 1. 同会话在未应答时重发 → 直接替换当前卡片；
    /// 2. 已有卡片或队列非空 → 入队，超过 `question_queue_limit` 时丢最旧的，
    ///    确保最新请求绝不丢失；
    /// 3. 空闲 → 直接展示。
    func present(_ newPrompt: AgentQuestionPrompt) {
        // 同会话重发：替换当前
        if let current = prompt, choice == nil,
           current.provider == newPrompt.provider,
           current.sessionID == newPrompt.sessionID {
            prompt = newPrompt
            picks = [:]
            texts = [:]
            writingOwn = []
            onPresent?()
            return
        }
        // 已在展示：入队，超限时丢最旧的（question_queue_limit），保证最新请求不丢。
        if prompt != nil || !queue.isEmpty {
            queue.append(newPrompt)
            let limit = max(1, Settings.shared.questionQueueLimit)
            if queue.count > limit { queue.removeFirst(queue.count - limit) }
            return
        }
        prompt = newPrompt
        picks = [:]
        texts = [:]
        writingOwn = []
        onPresent?()
    }

    /// 若当前卡片匹配该 questionID/requestID，则收起。
    func clearCurrent(questionID: String, requestID: String) {
        guard let current = prompt else { return }
        if current.matches(questionID: questionID, requestID: requestID) {
            dismiss()
        }
    }

    /// 会话结束：收起该会话的当前卡片并从队列移除其所有待展示项。
    func dropSession(sessionID: String) {
        if prompt?.sessionID == sessionID { dismiss() }
        queue.removeAll { $0.sessionID == sessionID }
    }

    /// 清理没人再等待的卡片：hook 已超时（等待上限 + 缓冲 + 宽限），请求已回落到 IDE。
    func sweepStale(olderThan deadline: TimeInterval) {
        let now = Date()
        queue.removeAll { now.timeIntervalSince($0.arrivedAt) > deadline }
        if let p = prompt, choice == nil, now.timeIntervalSince(p.arrivedAt) > deadline {
            dismiss()
        }
    }

    /// 清空当前提问与排队项（**不写应答文件**，仅用于调试面板）。
    ///
    /// - Parameter notify: `true` 走正常收起流程（灵动岛随之收拢）；`false` 只清状态，
    ///   供「先清同类再注入」使用——避免同一帧内先播收起动画再播展开动画。
    func flushAll(notify: Bool = true) {
        queue.removeAll()
        guard prompt != nil else { return }
        if notify {
            dismiss()
        } else {
            prompt = nil
            choice = nil
            picks = [:]
            texts = [:]
            writingOwn = []
        }
    }

    /// 收起当前卡片并清空其临时状态，随后提升队列里的下一个。
    private func dismiss() {
        prompt = nil
        choice = nil
        picks = [:]
        texts = [:]
        writingOwn = []
        onDismiss?()
        promoteNext()
    }

    /// 队首提问提升为当前卡片。
    private func promoteNext() {
        guard prompt == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        prompt = next
        picks = [:]
        texts = [:]
        writingOwn = []
        onPresent?()
    }

    // MARK: - 用户交互

    /// 多问翻页：把当前 index 钳制到合法范围后跳转。
    func navigate(to index: Int) {
        guard var p = prompt else { return }
        p.index = max(0, min(index, p.questions.count - 1))
        prompt = p
    }

    /// 勾选某个答案。多选走切换语义，单选记录后尝试自动翻页。
    func pick(_ answer: AgentQuestionAnswer, for questionID: String) {
        guard prompt != nil else { return }
        if let current = prompt, current.question.multiSelect {
            // 多选：切换该下标的选中状态
            var indices = Set(picks[questionID]?.answerIndices ?? [])
            switch answer {
            case .option(let idx):
                if indices.contains(idx) { indices.remove(idx) }
                else { indices.insert(idx) }
                picks[questionID] = indices.isEmpty ? nil : .options(Array(indices))
            default: picks[questionID] = answer
            }
        } else {
            picks[questionID] = answer
            // 单选：自动前进到下一问
            advanceIfNeeded()
        }
    }

    /// 进入"自己作答"（自定义文本）模式。
    func beginOwnAnswer(for questionID: String) {
        writingOwn.insert(questionID)
        picks[questionID] = .custom(texts[questionID] ?? "")
    }

    /// Tab / `.other`：开始自定义作答，并请求视图把焦点移入输入框。
    func requestFocusOther(for questionID: String) {
        beginOwnAnswer(for: questionID)
        focusOtherTick += 1
    }

    /// 更新某问题的"其他…"文本；若处于自定义模式则同步到 picks。
    func setText(_ text: String, for questionID: String) {
        texts[questionID] = text
        if writingOwn.contains(questionID) {
            picks[questionID] = .custom(text)
        }
    }

    /// 是否可提交：所有问题都已有效作答（自定义文本非空白、多选非空）。
    var canSend: Bool {
        guard let p = prompt else { return false }
        return p.questions.allSatisfy { q in
            switch picks[q.id] {
            case .option: return true
            case .options(let indices): return !indices.isEmpty
            case .custom(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case nil: return false
            }
        }
    }

    /// 提交：逐问下发应答文件，记录 choice，给一次反馈，短暂停留后收起。
    func submit() {
        guard canSend, let p = prompt, choice == nil else { return }
        let ordered = p.questions.map { picks[$0.id] ?? .option(-1) }
        // 下发各问题的应答
        for (i, q) in p.questions.enumerated() {
            AnswerDispatcher.dispatchAnswer(
                sessionID: p.sessionID, questionID: q.id,
                requestID: p.requestID, answer: ordered[i], question: q)
        }
        choice = ordered.first
        FeedbackService.onAnswer()
        // 短暂反馈后收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismiss()
        }
    }

    /// 单选作答后若还有下一问则自动翻页。
    private func advanceIfNeeded() {
        guard let p = prompt, p.index + 1 < p.questions.count else { return }
        navigate(to: p.index + 1)
    }
}

// MARK: - 提问匹配扩展

private extension AgentQuestionPrompt {
    /// 判断本提问是否匹配给定的 questionID/requestID。
    ///
    /// 双方 requestID 都非空时以 requestID 为准（精确对齐一次请求）；
    /// 否则回退到按 questionID 在问题列表里查找。
    func matches(questionID: String, requestID: String) -> Bool {
        if !requestID.isEmpty && !self.requestID.isEmpty {
            return self.requestID == requestID
        }
        return questions.contains { $0.id == questionID }
    }
}
