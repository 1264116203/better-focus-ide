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
        case .turn: return "你说："
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
         state: String, source: String, project: String, provider: String?, host: HostInfo?,
         tintRGB: (red: Double, green: Double, blue: Double), timestamp: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.state = state
        self.source = source
        self.project = project
        self.provider = provider
        self.host = host
        self.tintRGB = tintRGB
        self.timestamp = timestamp
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }

    /// 历史行副文字的展示文本（含类型前缀）；为空串时整行不渲染。
    ///
    /// 三种情况不展示：
    /// - 正文为空；
    /// - 正文与标题同源（单轮会话里首条与最近一条用户提问相同，只是截断长度不同）；
    /// - 正文是「点击跳转回 X」兜底文案（旧数据会把它存进 body）。
    var bodyLine: String {
        guard !body.isEmpty else { return "" }
        // 标题截断更短且带省略号，去掉它即可判断正文是否只是标题的展开版。
        let titleCore = title.hasSuffix("…") ? String(title.dropLast()) : title
        if !titleCore.isEmpty, body.hasPrefix(titleCore) { return "" }
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
