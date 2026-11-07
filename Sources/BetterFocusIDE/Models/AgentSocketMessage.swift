// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Hook/Plugin 通过 Unix Socket 发来的 JSON 消息（线协议顶层结构）。
struct AgentSocketMessage: Codable {
    /// 提供方标识（qoder / opencode）。
    let provider: String
    /// 产品标识（由 hook 环境变量决策树推导，如 jetbrains_plugin / qoder_ide / qoder_cli）。
    let product: String?
    /// 事件类型，对应 `SocketEvent`。
    let event: String
    /// 会话标识。
    let sessionID: String
    /// 事件时间戳（可选）。
    let timestamp: Date?
    /// 事件载荷，字段随 event 类型而异。
    let payload: [String: AnyCodableValue]?
    /// 顶层携带的宿主应用身份（bundle/name/path）。
    let host: [String: AnyCodableValue]?
    /// 顶层携带的项目目录（二级定位用）。
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case provider, product, event, payload, host, cwd
        case sessionID = "session_id"
        case timestamp
    }

    /// 构造解码器：自定义时间戳策略，同时接受整秒与带小数秒的 ISO 8601。
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = socketDate(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: c, debugDescription: "Bad timestamp: \(text)")
            }
            return date
        }
        return d
    }

    /// 解析 ISO 8601 字符串：优先带小数秒格式，回退到整秒格式。
    static func socketDate(from text: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return withFrac.date(from: text) ?? whole.date(from: text)
    }

    /// 解析产品标识：优先用 `product`（hook 决策树输出），回退到 `provider`（旧版兼容）。
    var resolvedProvider: AgentProvider {
        if let product, let p = AgentProvider(rawValue: product) { return p }
        return AgentProvider(rawValue: provider.lowercased()) ?? .unknown
    }
}

/// Socket 协议中已识别的事件类型。
enum SocketEvent: String {
    case questionRequested = "question_requested"
    case questionAnswered = "question_answered"
    case questionTimeout = "question_timeout"
    case permissionRequested = "permission_requested"
    case permissionResolved = "permission_resolved"
    case permissionTimeout = "permission_timeout"
    /// 权限通知（只提醒，不拦截）：hook 发完即回 ask，让 Qoder 弹原生对话框。
    case permissionNotice = "permission_notice"
    case sessionEnded = "session_ended"
    case turnFinished = "turn_finished"
    /// 工具失败、回合报错、自动拒绝、额度或登录失败。
    case failureNotice = "failure_notice"
    /// 子代理结束。
    case subagentFinished = "subagent_finished"
    /// 文档待审、浏览器在等、MCP 需要人输入但题面不在工具参数里。
    case reviewNotice = "review_notice"
    /// 上下文即将或已经压缩。
    case compactNotice = "compact_notice"
    /// 待办整表覆盖：`TodoWrite` / `todowrite` / `SetTodoList` 每次重发完整列表。
    case todoUpdated = "todo_updated"
    /// 待办单条写入：Claude Code V2 / WorkBuddy 的 `TaskCreate` / `TaskUpdate`。
    case todoItemUpdated = "todo_item_updated"
    /// 待办清空：宿主主动撤销（如 `TaskUpdate` 置 deleted 后的整表收敛）。
    case todoCleared = "todo_cleared"
    case activity
}

/// 类型擦除的可解码值，用于承载结构不固定的 JSON 载荷。
///
/// 仅支持 string/int/double/bool/array/dictionary/null；颜色等复合值
/// 以 "r,g,b" 字符串形式存于 `.string`。
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    /// 按类型依次试探解码：null → string → int → double → bool → array → dictionary。
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let a = try? c.decode([AnyCodableValue].self) { self = .array(a) }
        else if let d = try? c.decode([String: AnyCodableValue].self) { self = .dictionary(d) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .dictionary(let d): try c.encode(d)
        case .null: try c.encodeNil()
        }
    }

    // MARK: - 取值访问器

    /// 以字符串读取（非字符串返回 nil）。
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// 以布尔读取：兼容真正的 bool 与字符串 "true"。
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true"
        default: return nil
        }
    }

    /// 以整数读取：兼容真正的数字与数字字符串（hook 有语言差异，两种都给）。
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    /// 以数组读取（非数组返回 nil）。
    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// 以字典读取（非字典返回 nil）。
    var dictValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
}
