// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// 保留最近若干条通知（提问、权限、轮次完成），
/// 让用户点击空闲灵动岛时能回顾"哪些应用找过自己"。
final class HistoryController: ObservableObject {
    /// 最多保留的条目数。
    static let limit = 5

    @Published private(set) var entries: [HistoryEntry] = []

    /// 记录一条新通知：新条目插到最前，超出 `limit` 时裁掉最旧的。
    func remember(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    /// 清空全部历史。
    func clear() {
        entries.removeAll()
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
        return HistoryEntry(
            title: prompt.question.header,
            body: prompt.question.question,
            state: state,
            source: prompt.provider.displayName,
            project: "",
            provider: prompt.provider.rawValue,
            host: nil,
            tintRGB: tint,
            timestamp: Date())
    }

    /// 由一次权限请求构造历史条目。
    static func permission(request: PermissionRequest, state: String) -> HistoryEntry {
        let tint = request.provider.tintRGB
        return HistoryEntry(
            title: request.title,
            body: request.detail,
            state: state,
            source: request.provider.displayName,
            project: "",
            provider: request.provider.rawValue,
            host: nil,
            tintRGB: tint,
            timestamp: Date())
    }

    /// 由一次轮次完成通知构造历史条目；无对应提供方时回退到默认蓝色调。
    static func turn(notice: TurnNotice, state: String) -> HistoryEntry {
        let tint = AgentProvider(rawValue: notice.provider)?.tintRGB
            ?? (red: 0.29, green: 0.62, blue: 1.0)
        let source = notice.host?.name.isEmpty == false ? notice.host!.name : notice.providerName
        return HistoryEntry(
            title: notice.title,
            body: notice.body,
            state: state,
            source: source,
            project: notice.project,
            provider: notice.provider,
            host: notice.host,
            tintRGB: tint,
            timestamp: notice.arrivedAt)
    }
}
