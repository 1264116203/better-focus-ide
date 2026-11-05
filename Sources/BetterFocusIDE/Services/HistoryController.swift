// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 保留最近若干条通知（提问、权限、轮次完成），
/// 让用户点击空闲灵动岛时能回顾"哪些应用找过自己"。
///
/// **按会话归并**：同一个会话每回复一轮都会产生一条通知（标题相同、用户消息不同），
/// 列表里逐条铺开会让一屏五条全被同一会话占满。因此以 `provider + sessionID`
/// 为键去重，每个会话只保留最新的一条——`limit` 计的是会话数，不是通知数。
///
/// 持久化到 `~/Library/Application Support/BetterFocusIDE/history.json`，
/// 启动时加载，每次变更后原子写盘。
final class HistoryController: ObservableObject {
    /// 最多保留的条目数（会话数）。
    static let limit = 5

    @Published private(set) var entries: [HistoryEntry] = []

    /// 历史文件路径。
    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("BetterFocusIDE/history.json", isDirectory: false)
    }

    init() {
        load()
    }

    // MARK: - 持久化

    /// 从 history.json 加载；文件缺失或解码失败时保留空列表。
    private func load() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let stored = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            entries = []
            return
        }
        // 旧版本可能把同一会话的多条通知都写进了文件，先归并再截断，
        // 否则一个新会话的重复条目会把别的会话挤掉。
        entries = Array(Self.grouped(stored).prefix(Self.limit))
    }

    /// 原子写盘；失败时静默忽略（历史记录非关键数据）。
    private func save() {
        let dir = Self.historyURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.historyURL, options: .atomic)
        }
    }

    // MARK: - 公开接口

    /// 记录一条新通知：新条目插到最前，同一会话的旧条目被它取代。
    /// 超出 `limit`（会话数）时裁掉最旧的会话。
    func remember(_ entry: HistoryEntry) {
        entries = Self.upserting(entry, into: entries)
        save()
    }

    /// 把一条通知并入列表：同会话的旧条目被摘掉，新条目插到队首，
    /// 再按 `limit` 截断。纯函数便于测试（不触碰磁盘）。
    static func upserting(_ entry: HistoryEntry, into list: [HistoryEntry]) -> [HistoryEntry] {
        // 同会话只留最新的一条：先摘掉旧条目，新条目再插到队首。
        // 这样"用户消息不同"的多轮通知不会在列表里各占一行。
        let sessionKey = entry.sessionKey
        let heuristicKey = entry.heuristicKey
        var next = list.filter { existing in
            if let sessionKey, existing.sessionKey == sessionKey { return false }
            // 升级前遗留的行没有会话号，只能靠近似身份认亲——否则新一轮通知只是
            // 换了个新行，旧行还赖在面板上，看起来仍像重复。
            if existing.sessionKey == nil, let heuristicKey,
               existing.heuristicKey == heuristicKey { return false }
            return true
        }
        next.insert(entry, at: 0)
        if next.count > limit {
            next.removeLast(next.count - limit)
        }
        return next
    }

    /// 按会话归并（保持原有先后顺序，同会话只保留位置最靠前的最新条目）。
    ///
    /// 分组键优先用真实会话号，旧数据退化为「产品 + 来源 + 标题 + 项目」，
    /// 两者都没有时（标题为空）按独立条目保留。
    static func grouped(_ list: [HistoryEntry]) -> [HistoryEntry] {
        var seen = Set<String>()
        return list.filter { entry in
            guard let key = entry.groupKey else { return true }
            return seen.insert(key).inserted
        }
    }

    /// 清空全部历史（同时删除文件）。
    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: Self.historyURL)
    }

    /// 点击某行：跳回该条目的来源应用。
    func tapped(_ entry: HistoryEntry) {
        if let provider = entry.provider {
            IDELauncher.activateAsync(provider: provider, host: entry.host)
        }
    }

    // MARK: - 构造器

    /// 由一次提问构造历史条目。
    static func question(prompt: AgentQuestionPrompt, state: String) -> HistoryEntry {
        let tint = prompt.provider.tintRGB
        let source = prompt.host?.name.isEmpty == false ? prompt.host!.name : prompt.provider.displayName
        return HistoryEntry(
            title: prompt.question.header,
            body: prompt.question.question,
            kind: .question,
            sessionID: prompt.sessionID,
            state: state,
            source: source,
            project: "",
            provider: prompt.provider.rawValue,
            host: prompt.host,
            tintRGB: tint,
            timestamp: Date())
    }

    /// 由一次权限请求构造历史条目。
    static func permission(request: PermissionRequest, state: String) -> HistoryEntry {
        let tint = request.provider.tintRGB
        let source = request.host?.name.isEmpty == false ? request.host!.name : request.provider.displayName
        return HistoryEntry(
            title: request.title,
            body: request.detail,
            kind: .permission,
            sessionID: request.sessionID,
            state: state,
            source: source,
            project: "",
            provider: request.provider.rawValue,
            host: request.host,
            tintRGB: tint,
            timestamp: Date())
    }

    /// 由一次轮次完成通知构造历史条目；无对应提供方时回退到默认蓝色调。
    static func turn(notice: TurnNotice, state: String) -> HistoryEntry {
        let providerEnum = AgentProvider(rawValue: notice.provider)
        let tint = providerEnum?.tintRGB
            ?? (red: 0.29, green: 0.62, blue: 1.0)
        // 来源名与卡片保持同一套规则：CLI 宿主标成「产品（终端）」，
        // 直接取 host.name 会把 "Qoder CLI（Warp）" 压成 "Warp"，历史里就看不出
        // 是哪个 CLI 了。
        let source = providerEnum.map {
            AgentProvider.label(provider: $0,
                                hostName: notice.host?.name,
                                bundleID: notice.host?.bundle)
        } ?? notice.providerName
        return HistoryEntry(
            title: notice.title,
            // 兜底文案「点击跳转回 X」不含实质内容，历史行留空更清爽。
            body: notice.bodyIsFallback ? "" : notice.body,
            kind: notice.kind,
            sessionID: notice.sessionID,
            state: state,
            source: source,
            project: notice.project,
            provider: notice.provider,
            host: notice.host,
            tintRGB: tint,
            timestamp: notice.arrivedAt)
    }
}
