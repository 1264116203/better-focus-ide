// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 智能体完成一次回复时发出的"轮次完成"通知（Qoder Stop / OpenCode session.idle）。
///
/// 以横幅形式展示，用户点击可跳回产生它的 IDE。
struct TurnNotice: Equatable, Identifiable {
    let id = UUID()
    /// 提供方标识（小写原始值）。
    let provider: String
    /// 提供方展示名。
    let providerName: String
    let sessionID: String
    /// 横幅标题（优先取会话真实标题，否则回退到通用文案）。
    let title: String
    /// 横幅正文（优先取最新一条助手消息，否则回退到跳转提示）。
    let body: String
    /// 项目叶子名（工作目录末级）。
    let project: String
    /// 宿主应用信息，用于精确跳转。
    let host: HostInfo?
    let arrivedAt: Date
    /// 点击是否跳回 IDE。
    let jumpEnabled: Bool
    /// 会话是否由 `qodercli`（无头脚本）产生：仍记入历史但不抢占屏幕——
    /// 它的"用户输入"是被管道进来的 diff，而非用户正在等待的内容。
    let fromCLI: Bool

    static func == (lhs: TurnNotice, rhs: TurnNotice) -> Bool { lhs.id == rhs.id }

    /// 将 `turn_finished` socket 消息解析为一条通知。
    ///
    /// 标题与正文读取自 hook 上报的 transcript jsonl（见 `Transcript.sessionSummary`）；
    /// 文件缺失/不可读时坍缩为空并回退到通用文案。
    static func parse(message: AgentSocketMessage) -> TurnNotice? {
        let providerEnum = message.resolvedProvider
        let provider = providerEnum.rawValue
        let sessionID = message.sessionID
        let host = HostInfo(from: message.host,
                            cwd: message.cwd)
        let project = projectLeaf(from: host)
        // 来源展示名：统一走 effectiveName——优先 hook 上报的真实 IDE 名称
        // （如 "IntelliJ IDEA"），回退到产品名，JetBrains 插件模式兜底 "JetBrains"。
        let name = AgentProvider.effectiveName(provider: providerEnum, hostName: host.name)
        // 从 hook 上报的 transcript jsonl 读取真实会话标题。
        let transcriptPath = message.payload?["transcript_path"]?.stringValue
        let summary = Transcript.sessionSummary(path: transcriptPath, provider: providerEnum.providerGroup)

        return TurnNotice(
            provider: provider,
            providerName: name,
            sessionID: sessionID,
            title: summary.title.isEmpty ? "\(name) 回复完成" : summary.title,
            body: summary.latest.isEmpty ? "点击跳转回 \(name)" : summary.latest,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: Settings.shared.turnNotifyJump,
            fromCLI: summary.fromCLI
        )
    }

    /// 项目目录的最后一个路径组件（即窗口标题）。
    private static func projectLeaf(from host: HostInfo) -> String {
        let cwd = host.cwd
        guard !cwd.isEmpty else { return "" }
        return (cwd as NSString).lastPathComponent
    }
}
