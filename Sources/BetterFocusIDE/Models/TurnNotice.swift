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
    /// 正文是否为「点击跳转回 X」兜底文案（读不到会话记录时）。
    /// 历史面板据此隐藏该行——没有实质内容，冠任何前缀都别扭。
    let bodyIsFallback: Bool
    /// 条目来源类型：轮次完成走 `.turn`，权限兜底通知走 `.permission`。
    let kind: HistoryKind
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

    /// 读不到会话记录时的兜底正文前缀（如「点击跳转回 OpenCode」）。
    /// 这类文案不含实质内容，历史行据此隐藏副文字。
    static let jumpHintPrefix = "点击跳转回"

    /// 将 `turn_finished` socket 消息解析为一条通知。
    ///
    /// 标题与正文读取自 hook 上报的 transcript jsonl（见 `Transcript.sessionSummary`）；
    /// 文件缺失/不可读时坍缩为空并回退到通用文案。
    static func parse(message: AgentSocketMessage,
                     terminalHost: (String) -> HostInfo? = {
                         OpenCodeHostProbe.currentTerminalHost(directory: $0)
                     },
                     webHost: (String, Int?) -> HostInfo? = {
                         OpenCodeHostProbe.currentWebHost(pid: $1, directory: $0)
                     }) -> TurnNotice? {
        let providerEnum = message.resolvedProvider
        let provider = providerEnum.rawValue
        let sessionID = message.sessionID
        // OpenCode 的插件拿不到客户端类型，改由事件流缓存会话目录一起上报。
        let directory = message.payload?["directory"]?.stringValue ?? ""
        // 插件自报的进程号：用来确定这一轮到底是浏览器里的 serve、终端 TUI
        // 还是桌面端服务——三者的事件长得完全一样。
        let pluginPID = message.payload?["pid"]?.intValue
        // OpenCode 的插件跑在 serve 进程里，事件流里没有客户端类型：
        // 桌面端、终端、浏览器会话上报的 host 都为空。从进程表反推真实宿主，
        // 否则点通知只会把 OpenCode 桌面端叫到前台，而不是用户等待的地方。
        let host = OpenCodeHostProbe.resolveHost(
            provider: providerEnum,
            host: HostInfo(from: message.host, cwd: message.cwd),
            directory: directory,
            pid: pluginPID,
            terminalHost: terminalHost,
            webHost: webHost)
        let project = projectLeaf(from: host)
        // 来源展示名：统一走 label——GUI 宿主用 hook 上报的真实应用名
        // （如 "IntelliJ IDEA"），CLI 宿主标成「产品（终端）」如
        // "Qoder CLI（Warp）"，JetBrains 插件模式兜底 "JetBrains"。
        let name = AgentProvider.label(provider: providerEnum,
                                       hostName: host.name,
                                       bundleID: host.bundle)
        // 从 hook 上报的 transcript jsonl 读取真实会话标题。
        let transcriptPath = message.payload?["transcript_path"]?.stringValue
        let summary = Transcript.sessionSummary(path: transcriptPath, provider: providerEnum.providerGroup)
        // OpenCode 插件拿不到 transcript 路径，改由事件流缓存会话标题与
        // 最近一次用户输入，随 payload 一起上报（`title` / `prompt`）。
        let payloadTitle = Transcript.shorten(
            message.payload?["title"]?.stringValue ?? "", limit: Transcript.titleLimit)
        let payloadPrompt = Transcript.shorten(
            message.payload?["prompt"]?.stringValue ?? "", limit: Transcript.bodyLimit)

        // 标题优先级：会话真实标题 → hook 直报的标题 → 用户这一轮的输入 →
        // 中性兜底。第三档很重要：WorkBuddy 这类宿主不给 transcript 路径时，
        // 「他这一轮问了什么」仍比「WorkBuddy 回复完成」有信息量——而且左列
        // 已经有 IDE 图标，再把产品名写成标题是纯粹的重复。
        let resolvedTitle: String
        if !summary.title.isEmpty {
            resolvedTitle = summary.title
        } else if !payloadTitle.isEmpty {
            resolvedTitle = payloadTitle
        } else if !summary.latest.isEmpty {
            resolvedTitle = summary.latest
        } else if !payloadPrompt.isEmpty {
            resolvedTitle = payloadPrompt
        } else {
            resolvedTitle = "未命名会话"
        }

        let resolvedBody: String
        let bodyIsFallback: Bool
        if !summary.latest.isEmpty {
            resolvedBody = summary.latest
            bodyIsFallback = false
        } else if !payloadPrompt.isEmpty {
            resolvedBody = payloadPrompt
            bodyIsFallback = false
        } else {
            resolvedBody = "\(Self.jumpHintPrefix) \(name)"
            bodyIsFallback = true
        }

        return TurnNotice(
            provider: provider,
            providerName: name,
            sessionID: sessionID,
            title: resolvedTitle,
            body: resolvedBody,
            bodyIsFallback: bodyIsFallback,
            kind: .turn,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: Settings.shared.turnNotifyJump,
            fromCLI: summary.fromCLI
        )
    }

    /// 项目目录的最后一个路径组件（即窗口标题）。
    ///
    /// 工作目录就是家目录时返回空：那会把用户名（`yujie.xu`）当成项目名，
    /// 既不是项目、也不提供任何定位信息。
    private static func projectLeaf(from host: HostInfo) -> String {
        let cwd = (host.cwd as NSString).standardizingPath
        guard !cwd.isEmpty, cwd != "/" else { return "" }
        if cwd == (NSHomeDirectory() as NSString).standardizingPath { return "" }
        return (cwd as NSString).lastPathComponent
    }
}
