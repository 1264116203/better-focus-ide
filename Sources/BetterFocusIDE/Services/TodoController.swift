// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 待办进度卡片的状态机。
///
/// 只做两件事：把各宿主形态各异的 todo 载荷归一成 `[TodoItem]`，以及把
/// **两种写入语义**分开处理——这是接入层最容易出错的地方：
///
/// | 语义 | 宿主 | 处理 |
/// |---|---|---|
/// | 整表覆盖 | Claude/Qoder/Trae/Cursor 的 `TodoWrite`、OpenCode `todowrite`、Kimi `SetTodoList` | 直接替换 |
/// | 逐条 UPSERT | Claude Code V2 `TaskCreate`+`TaskUpdate`、WorkBuddy `Task*` | 按 id 合并 |
///
/// 若把 UPSERT 当成覆盖，每条 `TaskUpdate` 都会把列表冲成只剩一条；
/// 若把覆盖当成 UPSERT，删除掉的项会永远留在列表里。
final class TodoController: ObservableObject {
    /// 当前列表（按宿主给的顺序）。
    @Published private(set) var items: [TodoItem] = []
    /// 来源身份：用于头部徽章与「来源 · 项目」。
    @Published private(set) var provider: AgentProvider = .unknown
    @Published private(set) var providerName: String = ""
    @Published private(set) var project: String = ""
    /// 归属会话：会话结束时据此清空，避免把 A 会话的进度画到 B 会话上。
    @Published private(set) var sessionID: String = ""
    /// 本轮待办首次出现的时间（驱动「已用 2m 14s」）。
    @Published private(set) var startedAt = Date()
    /// 全部结束的时刻；非 nil 时卡片处于「全部完成」收尾态。
    @Published private(set) var finishedAt: Date?
    /// 最近一次收到 todo 事件的时间（驱动「无进展超时兜底」）。
    ///
    /// 手动停止 Qoder/Claude 等宿主的 session 时，它们**不触发任何 hook 事件**
    /// （无 Stop / SessionEnd / PostToolUseFailure），岛侧永远收不到清空信号。
    /// 唯一可靠的兜底是「长时间没新事件就自动收起」——这里记录最后一次写入时刻，
    /// 供 `NotchService` 的陈旧卡片清扫据此判定。
    @Published private(set) var lastUpdateAt = Date()

    /// 变化计数：供 `NotchService` 判断是否需要重新计算窗口尺寸。
    @Published private(set) var revision: Int = 0

    /// 派生视图模型。
    var progress: TodoProgress { TodoProgress(items: items) }

    /// 是否有可展示的待办（空列表不占卡片位）。
    var hasTodo: Bool { !items.isEmpty }

    // MARK: - 写入

    /// 整表覆盖：`TodoWrite` / `todowrite` / `SetTodoList` 的更新模式。
    ///
    /// 传空数组表示「宿主主动清空」——不清空 `items`，而是当作本轮结束，
    /// 让卡片走收尾动画；真正的清空交给 `reset()`。
    func apply(snapshot: [TodoItem], sessionID: String, provider: AgentProvider,
               providerName: String, project: String) {
        adopt(sessionID: sessionID, provider: provider,
              providerName: providerName, project: project)
        guard !snapshot.isEmpty else { return }
        items = snapshot
        refreshLifecycle()
    }

    /// 逐条 UPSERT：`TaskCreate` / `TaskUpdate`（Claude Code V2、WorkBuddy）。
    ///
    /// - 新 id：追加到末尾。
    /// - 已有 id：原地更新正文与状态（保持位置不变，避免行在列表里乱跳）。
    /// - `deleted` 状态：直接从列表移除。
    ///
    /// **id 不稳定的兜底**：V2 的 `TaskCreate` 入参没有 id（服务端才分配），
    /// 我们只能用正文哈希当 id；而紧随其后的 `TaskUpdate` 用的是服务端分配的
    /// `taskId`——两者不同，若只按 id 匹配就会把同一条任务追加成两条。所以
    /// 当 id 匹配不上时，退而按**正文**匹配（同一句话视为同一任务），命中则
    /// 原地更新并回填真实 id。
    func upsert(_ item: TodoItem, sessionID: String, provider: AgentProvider,
                providerName: String, project: String) {
        adopt(sessionID: sessionID, provider: provider,
              providerName: providerName, project: project)
        if item.status == .cancelled {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items.remove(at: index)
            } else if let index = items.firstIndex(where: { $0.content == item.content }) {
                items.remove(at: index)
            }
        } else if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else if let index = items.firstIndex(where: { $0.content == item.content }) {
            // id 对不上但正文相同：回填宿主这次给的真实 id，下次就能精确匹配。
            items[index] = item
        } else {
            items.append(item)
        }
        refreshLifecycle()
    }

    /// 全量校正（宿主偶尔会回一条完整列表，例如 `TaskList`）。
    func replaceAll(_ list: [TodoItem]) {
        guard !list.isEmpty else { return }
        items = list
        refreshLifecycle()
    }

    /// socket 载荷统一入口：按载荷形状自动选择覆盖或 UPSERT。
    ///
    /// 判定顺序是「先列表后单项」：`{ "todos": [...] }` 一定走覆盖；裸对象或
    /// `{ "task": {...} }` 走 UPSERT。判不出来就整条忽略——绝不用空列表去覆盖，
    /// 否则一次畸形事件就会把进度清零并把卡片推进「全部完成」。
    func ingest(payload: [String: AnyCodableValue]?, sessionID: String, provider: AgentProvider,
                providerName: String, project: String) {
        let value = payload.map { AnyCodableValue.dictionary($0) }
        if let list = TodoPayloadParser.list(from: value) {
            Log.info("ingest 覆盖 count=\(list.count)", topic: "todo")
            apply(snapshot: list, sessionID: sessionID, provider: provider,
                  providerName: providerName, project: project)
        } else if let item = TodoPayloadParser.single(from: value) {
            Log.info("ingest 单条 id=\(item.id) content=\(item.content) status=\(item.status.rawValue) 当前items=\(items.count)", topic: "todo")
            upsert(item, sessionID: sessionID, provider: provider,
                   providerName: providerName, project: project)
        } else {
            Log.debug("TodoController.ingest: 载荷无法识别，已忽略", topic: "todo")
        }
    }

    /// 会话切换：来源变了就整体重置，不把两个会话的任务混在一张卡片里。
    private func adopt(sessionID: String, provider: AgentProvider,
                       providerName: String, project: String) {
        if !self.sessionID.isEmpty, self.sessionID != sessionID {
            items = []
            finishedAt = nil
            startedAt = Date()
        }
        if self.sessionID != sessionID {
            startedAt = Date()
            finishedAt = nil
        }
        self.sessionID = sessionID
        self.provider = provider
        self.providerName = providerName
        self.project = project
    }

    /// 依据当前列表刷新「是否已收尾」。
    private func refreshLifecycle() {
        revision &+= 1
        lastUpdateAt = Date()
        if items.isEmpty {
            finishedAt = nil
        } else if progress.isFinished {
            if finishedAt == nil { finishedAt = Date() }
        } else {
            finishedAt = nil
        }
    }

    // MARK: - 清理

    func reset() {
        guard !items.isEmpty || !sessionID.isEmpty else { return }
        items = []
        sessionID = ""
        project = ""
        provider = .unknown
        providerName = ""
        finishedAt = nil
        revision &+= 1
        lastUpdateAt = Date()
    }

    /// 会话结束：仅当结束的是本卡片所属会话时才清空。
    func handleSessionEnded(_ endedSessionID: String) {
        guard !endedSessionID.isEmpty, endedSessionID == sessionID else { return }
        reset()
    }

    /// 「全部完成」状态已展示了足够久，可以收卡片了。
    func shouldDismissFinished(after interval: TimeInterval = 2.5) -> Bool {
        guard let finishedAt else { return false }
        return Date().timeIntervalSince(finishedAt) >= interval
    }

    /// 「长时间没有新事件」判定：手动停止宿主 session 后不会再有 hook 事件，
    /// 靠这条兜底把残留进度自动收掉，避免卡片永远挂在岛上。
    ///
    /// 只有非空列表才判定（空列表本来就 `hasTodo == false`，无需兜底）。
    func shouldDismissIdle(after interval: TimeInterval) -> Bool {
        guard hasTodo else { return false }
        return Date().timeIntervalSince(lastUpdateAt) >= interval
    }
}
