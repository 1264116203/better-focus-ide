// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Hook/Plugin 通过 Unix Socket 发来的 JSON 消息（线协议顶层结构）。
struct AgentSocketMessage: Codable {
    /// 提供方标识（qoder / opencode）。
    let provider: String
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

    enum CodingKeys: String, CodingKey {
        case provider, event, payload, host
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
}

/// Socket 协议中已识别的事件类型。
enum SocketEvent: String {
    case questionRequested = "question_requested"
    case questionAnswered = "question_answered"
    case questionTimeout = "question_timeout"
    case permissionRequested = "permission_requested"
    case permissionResolved = "permission_resolved"
    case permissionTimeout = "permission_timeout"
    case sessionEnded = "session_ended"
    case turnFinished = "turn_finished"
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
