// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 历史条目的来源类型，决定副文字的语义前缀。
///
/// 三类通知的 `body` 含义完全不同，统一冠以「答：」会自相矛盾：
/// 提问卡片里 `body` 是**智能体问用户的正文**，权限卡片里是**命令/操作详情**，
/// 轮次完成通知里则是**用户这一轮的输入**（`Transcript.last()` 取的是最后一条
/// 用户轮次，并非助手回答）。
enum HistoryKind: String, Codable {
    /// 智能体向用户提问。
    case question
    /// 权限请求。
    case permission
    /// 轮次完成通知。
    case turn

    /// 副文字前缀（含全角冒号）。跳转兜底文案由调用方过滤，不走这里。
    var bodyLabel: String {
        switch self {
        case .question: return "问："
        case .permission: return "详情："
        case .turn: return "用户："
        }
    }

    /// 旧版本记录没有 `kind` 字段，按状态文案回退推断。
    static func legacy(from state: String) -> HistoryKind {
        state.contains("回复完成") ? .turn : .question
    }
}

/// 最近通知历史中的一条记录：发生了什么、由哪个应用产生、如何跳回。
///
/// 持久化到 `~/Library/Application Support/BetterFocusIDE/history.json`，
/// 保留最近 N 条（默认 5 条），超出时裁掉最旧的。
struct HistoryEntry: Identifiable, Equatable, Codable {
    let id: UUID
    /// 内容标题（问题头部 / 工具动作名 / 会话标题）。
    let title: String
    /// 副文字（问题正文 / 操作详情 / 用户这一轮的输入），前缀由 `kind` 决定。
    let body: String
    /// 条目来源类型，用于给副文字配上准确的前缀。
    let kind: HistoryKind
    /// 会话标识，与 `provider` 一起构成会话分组键。
    ///
    /// 同一个会话每回复一轮都会产生一条通知（标题相同、用户消息不同），
    /// 历史面板按会话归并，只保留该会话最新的一条。旧数据没有该字段，
    /// 解码为空串，届时按独立条目处理（不会被误合并）。
    let sessionID: String
    /// 结果行，如 "已回答" / "已拒绝" / "回复完成"。
    let state: String
    /// 来源展示名（宿主应用名或提供方名）。
    var source: String
    /// 作为淡色元数据显示的项目叶子名（路径末级目录）。
    let project: String
    /// 提供方可用于跳回 IDE 的标识。
    let provider: String?
    /// 宿主应用信息（bundle/name/path），用于精确跳转。
    var host: HostInfo?
    /// 徽章主题色 RGB 分量（存储为 "r,g,b" 字符串）。
    let tintRGB: (red: Double, green: Double, blue: Double)
    let timestamp: Date

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, title, body, kind, state, source, project, provider, host, timestamp
        case sessionID
        case tintRed, tintGreen, tintBlue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        state = try container.decode(String.self, forKey: .state)
        // 旧格式没有 kind：按状态文案回退，保证历史文件仍能整体解码。
        kind = try container.decodeIfPresent(HistoryKind.self, forKey: .kind)
            ?? HistoryKind.legacy(from: state)
        // 旧格式没有 sessionID：空串表示"无法归组"，各条按独立条目保留。
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        source = try container.decode(String.self, forKey: .source)
        project = try container.decode(String.self, forKey: .project)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        host = try container.decodeIfPresent(HostInfo.self, forKey: .host)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let r = try container.decode(Double.self, forKey: .tintRed)
        let g = try container.decode(Double.self, forKey: .tintGreen)
        let b = try container.decode(Double.self, forKey: .tintBlue)
        tintRGB = (red: r, green: g, blue: b)
        // 旧数据 host.name 可能为空（hook 的 CFBundleName 缺失），用 bundle ID 回退填充
        if var h = host, h.name.isEmpty && !h.bundle.isEmpty {
            h.name = HostInfo.bundleIdDisplayName[h.bundle] ?? ""
            host = h
        }
        // 旧数据 source 也可能为空，用修复后的 host.name 回填
        if source.isEmpty, let hostName = host?.name, !hostName.isEmpty {
            source = hostName
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(kind, forKey: .kind)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encode(project, forKey: .project)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(tintRGB.red, forKey: .tintRed)
        try container.encode(tintRGB.green, forKey: .tintGreen)
        try container.encode(tintRGB.blue, forKey: .tintBlue)
    }

    // MARK: - 构造器

    init(id: UUID = UUID(), title: String, body: String, kind: HistoryKind = .question,
         sessionID: String = "", state: String, source: String, project: String,
         provider: String?, host: HostInfo?,
         tintRGB: (red: Double, green: Double, blue: Double), timestamp: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.sessionID = sessionID
        self.state = state
        self.source = source
        self.project = project
        self.provider = provider
        self.host = host
        self.tintRGB = tintRGB
        self.timestamp = timestamp
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }

    /// 会话分组键：`provider|sessionID`。
    ///
    /// 缺任一项时返回 nil——无从判断归属的条目（旧数据、某些 hook 不上报会话号）
    /// 走下面的 `legacyKey` 兜底。
    var sessionKey: String? {
        guard !sessionID.isEmpty else { return nil }
        let providerKey = (provider ?? "").lowercased()
        return providerKey.isEmpty ? sessionID : "\(providerKey)|\(sessionID)"
    }

    /// 近似身份：`provider|source|title|project`（标题为空时为 nil）。
    ///
    /// 升级前的历史文件没有 `sessionID`，直接扔了可惜，留着又会在面板里重复成
    /// 两三行（同一会话每轮一条）。同一会话的多轮通知标题是同一个（会话标题），
    /// 只有正文里的用户输入不同，所以用「产品 + 来源 + 标题 + 项目」足以把它们收拢。
    ///
    /// 代价：同一产品下两个同名会话（都叫「未命名会话」且同项目）会被并成一行。
    /// 这个近似只在**缺少会话号的旧行**上生效，新行一律有 `sessionKey`，误合并
    /// 的窗口最多持续到旧行被新通知挤出 5 条为止。
    var heuristicKey: String? {
        guard !title.isEmpty else { return nil }
        let providerKey = (provider ?? "").lowercased()
        return "\(providerKey)|\(source.lowercased())|\(title)|\(project)"
    }

    /// 旧行（无会话号）的分组键：退化为近似身份。
    var legacyKey: String? { sessionKey == nil ? heuristicKey : nil }

    /// 归并时实际使用的键：真实会话号优先，旧数据退化为近似身份。
    /// 两者都没有（标题为空）时返回 nil，按独立条目处理。
    var groupKey: String? { sessionKey ?? legacyKey }

    /// 历史行副文字的展示文本（含类型前缀）；为空串时整行不渲染。
    ///
    /// 两种情况下不展示：
    /// - 正文为空；
    /// - 正文是「点击跳转回 X」兜底文案（旧数据会把它存进 body）。
    ///
    /// 新 session 第一条对话里，标题与正文都取自首条提问（内容同源），
    /// 但「用户：prompt」这一行仍有独立信息量（带类型前缀、展示完整输入），
    /// 故不再做「同源前缀去重」，与第二条及之后的行为保持一致。
    var bodyLine: String {
        guard !body.isEmpty else { return "" }
        if body.hasPrefix(TurnNotice.jumpHintPrefix) { return "" }
        return kind.bodyLabel + body
    }

    /// 格式化后的时间文本（HH:mm）。
    var clockText: String {
        HistoryEntry.formatter.string(from: timestamp)
    }

    /// 24 小时制时:分格式化器（英文区域，避免中文数字干扰）。
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 来源首字母大写——徽章上显示的字符。
    var badgeText: String {
        let base = source.isEmpty ? "?" : source
        return String(base.prefix(1)).uppercased()
    }
}
