// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// A JSON message received from a Hook/Plugin through the Unix Socket.
struct AgentSocketMessage: Codable {
    let provider: String
    let event: String
    let sessionID: String
    let timestamp: Date?
    let payload: [String: AnyCodableValue]?
    /// Host app identity (bundle/name/path) sent at the top level.
    let host: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case provider, event, payload, host
        case sessionID = "session_id"
        case timestamp
    }

    /// Decoder accepting both whole-second and fractional-second ISO 8601.
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

    static func socketDate(from text: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return withFrac.date(from: text) ?? whole.date(from: text)
    }
}

/// Recognized event types in the socket protocol.
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

/// Type-erased Codable value for flexible JSON payloads.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

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

    // MARK: - Accessors

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true"
        default: return nil
        }
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var dictValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
}
