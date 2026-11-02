// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

// MARK: - Permission Decision constants

enum PermissionDecisionValue: String {
    case allowOnce = "once"
    case allowAlways = "always"
    case reject = "reject"
    case timeout = "timeout"

    var label: String {
        switch self {
        case .allowOnce: return "允许"
        case .allowAlways: return "始终允许"
        case .reject: return "拒绝"
        case .timeout: return "超时"
        }
    }

    var answerIndex: Int {
        switch self {
        case .allowOnce: return 0
        case .allowAlways: return 1
        case .reject: return 2
        case .timeout: return -1
        }
    }
}

// MARK: - PermissionRequest

/// A permission request from a tool call awaiting user approval.
struct PermissionRequest: Equatable, Identifiable {
    let requestID: String
    let provider: AgentProvider
    let sessionID: String
    let action: String
    let resources: [String]
    let agent: String
    let toolName: String
    let toolInput: [String: AnyCodableValue]?
    let arrivedAt: Date
    var flavor: String = "opencode"

    var id: String { "\(provider.rawValue).\(sessionID).\(requestID)" }

    /// Human-readable title for the card header.
    var title: String {
        Self.actionLabel(action)
    }

    /// Detail line: the command / path / URL.
    var detail: String {
        if let first = resources.first { return first }
        guard let input = toolInput else { return "" }
        for key in ["command", "file_path", "path", "url", "query", "pattern"] {
            if let val = input[key]?.stringValue, !val.isEmpty { return val }
        }
        return ""
    }

    static func actionLabel(_ action: String) -> String {
        let labels: [String: String] = [
            "shell": "终端命令", "bash": "终端命令",
            "read": "读取文件", "edit": "修改文件", "write": "写入文件",
            "file": "读写文件", "patch": "修改文件",
            "glob": "查找文件", "grep": "搜索内容",
            "webfetch": "访问网页", "websearch": "联网搜索",
            "subagent": "启动智能体", "skill": "调用技能",
            "mcp": "MCP 工具", "permission": "权限审批", "tool": "权限审批",
        ]
        if let known = labels[action] { return known }
        if action.hasPrefix("mcp/") || action.contains("/") { return "MCP 工具" }
        return action.isEmpty ? "操作" : action
    }

    // MARK: Parsing from socket payload

    static func parse(payload: [String: AnyCodableValue]?, provider: AgentProvider,
                      sessionID: String) -> PermissionRequest? {
        guard let payload else { return nil }
        guard let requestID = payload["request_id"]?.stringValue, !requestID.isEmpty else {
            return nil
        }

        var resources: [String] = []
        if case .array(let arr) = payload["resources"] {
            resources = arr.compactMap { $0.stringValue }
        } else if let s = payload["resources"]?.stringValue, !s.isEmpty {
            resources = [s]
        }

        let toolInputDict: [String: AnyCodableValue]? = {
            if case .dictionary(let d) = payload["tool_input"] { return d }
            return nil
        }()

        // Infer resources from tool_input if empty
        if resources.isEmpty, let input = toolInputDict {
            for key in ["command", "file_path", "path", "url", "query", "pattern"] {
                if let val = input[key]?.stringValue, !val.isEmpty {
                    resources = [val]
                    break
                }
            }
        }

        var action = payload["action"]?.stringValue ?? ""
        let toolName = payload["tool_name"]?.stringValue ?? ""
        if action.isEmpty {
            action = actionFromToolName(toolName)
        }
        if action.isEmpty || toolName.lowercased() == "permission" || toolName.isEmpty {
            action = actionFromToolInput(toolInputDict) ?? action
            if action.isEmpty { action = "permission" }
        }

        return PermissionRequest(
            requestID: requestID,
            provider: provider,
            sessionID: sessionID,
            action: action,
            resources: resources,
            agent: payload["agent"]?.stringValue ?? "",
            toolName: toolName,
            toolInput: toolInputDict,
            arrivedAt: Date(),
            flavor: payload["flavor"]?.stringValue ?? "opencode"
        )
    }

    private static func actionFromToolName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty || trimmed == "permission" || trimmed == "tool" { return "" }
        if trimmed.hasPrefix("mcp__") {
            return "mcp/" + String(trimmed.dropFirst(5)).replacingOccurrences(of: "__", with: "/")
        }
        let mapping: [String: String] = [
            "bash": "shell", "shell": "shell", "read": "read",
            "write": "write", "edit": "edit", "multiedit": "edit",
            "patch": "edit", "glob": "glob", "grep": "grep",
            "webfetch": "webfetch", "websearch": "websearch",
            "web_search": "websearch", "task": "subagent",
            "agent": "subagent", "skill": "skill",
        ]
        return mapping[trimmed] ?? trimmed
    }

    private static func actionFromToolInput(_ input: [String: AnyCodableValue]?) -> String? {
        guard let input else { return nil }
        let keys: [(String, String)] = [
            ("command", "shell"), ("file_path", "file"),
            ("path", "file"), ("url", "webfetch"),
            ("query", "websearch"), ("pattern", "grep"),
        ]
        for (key, action) in keys {
            if let val = input[key]?.stringValue, !val.isEmpty { return action }
        }
        return nil
    }
}
