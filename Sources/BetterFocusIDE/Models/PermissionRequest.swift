// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

// MARK: - 权限决策常量

/// 权限审批的四种决策结果。
///
/// rawValue 用于写回应答文件；`answerIndex` 用于卡片按钮下标映射，
/// 超时为负值表示非用户主动点击。
enum PermissionDecisionValue: String {
    case allowOnce = "once"
    case allowAlways = "always"
    case reject = "reject"
    case timeout = "timeout"

    /// 决策的中文按钮/回显文案。
    var label: String {
        switch self {
        case .allowOnce: return "允许"
        case .allowAlways: return "始终允许"
        case .reject: return "拒绝"
        case .timeout: return "超时"
        }
    }

    /// 映射到卡片按钮的顺序下标（允许=0、始终允许=1、拒绝=2、超时=-1）。
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

/// 一次工具调用产生的、等待用户审批的权限请求。
struct PermissionRequest: Equatable, Identifiable {
    let requestID: String
    let provider: AgentProvider
    let sessionID: String
    /// 归一化后的动作标识（如 shell/read/edit），用于生成标题。
    let action: String
    /// 涉及的资源（命令、路径、URL 等），首项作为详情展示。
    let resources: [String]
    /// 发起请求的子智能体名称（可为空）。
    let agent: String
    let toolName: String
    /// 工具原始输入参数，用于在 resources 为空时反推详情。
    let toolInput: [String: AnyCodableValue]?
    let arrivedAt: Date
    /// 协议风格标记，默认 "opencode"。
    var flavor: String = "opencode"
    /// 宿主应用身份（hook 上报的 IDE 信息），用于历史来源展示与跳转。
    var host: HostInfo?

    /// 卡片唯一标识：提供方+会话+请求 id 拼接。
    var id: String { "\(provider.rawValue).\(sessionID).\(requestID)" }

    /// 卡片标题头的人类可读文案。
    var title: String {
        Self.actionLabel(action)
    }

    /// 详情行：优先取 resources 首项，否则从 toolInput 里挑首个非空的关键字段
    /// （命令 / 路径 / URL / 查询 / 模式）。
    var detail: String {
        if let first = resources.first { return first }
        guard let input = toolInput else { return "" }
        for key in ["command", "file_path", "path", "url", "query", "pattern"] {
            if let val = input[key]?.stringValue, !val.isEmpty { return val }
        }
        return ""
    }

    /// 将动作标识翻译为中文标题；未知动作含 "/" 视为 MCP 工具，全兜底为"操作"。
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

    // MARK: 从 socket 载荷解析

    /// 从 socket payload 构造权限请求；缺少 request_id 则返回 nil（无法应答）。
    ///
    /// 动作推断有三级兜底：显式 action → 由 tool_name 映射 → 由 tool_input 键反推。
    static func parse(payload: [String: AnyCodableValue]?, provider: AgentProvider,
                      sessionID: String) -> PermissionRequest? {
        guard let payload else { return nil }
        guard let requestID = payload["request_id"]?.stringValue, !requestID.isEmpty else {
            return nil
        }

        // resources 可能是数组或单字符串。
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

        // resources 为空时，尝试从 tool_input 的关键字段反推出资源。
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
        // 仍无法确定动作时，再从 tool_input 键反推，最终兜底为 permission。
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

    /// 由工具名映射出归一化动作；`mcp__a__b` 形式转换为 `mcp/a/b`。
    static func actionFromToolName(_ name: String) -> String {
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

    /// 从人类可读文案里抠出工具名。
    ///
    /// `Notification` 类权限提醒（WorkBuddy / Claude 风格，matcher=permission_prompt）
    /// 只带一句 "…needs your permission to use Bash"，没有 `tool_name` 字段，
    /// 标题就会退化成泛泛的「操作」。这里把句中的工具名取出来，复用同一套映射。
    static func toolNameHint(from text: String) -> String {
        guard let range = text.range(of: "permission to use ", options: .caseInsensitive)
        else { return "" }
        let name = text[range.upperBound...].prefix {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-"
        }
        return name.isEmpty ? "" : String(name)
    }

    /// 是否是「向人提问」类工具。
    ///
    /// 提问工具会从权限通道也冒一遍（WorkBuddy 的 Notification 只带一句
    /// `…permission to use AskUserQuestion`），但它根本不是权限申请：
    /// 问题卡片或宿主自带的问卷面板已经在问了，再弹一条「请求执行操作」
    /// 只会让人以为要审批两次。
    static func isQuestionTool(_ name: String) -> Bool {
        let lowered = name.lowercased().replacingOccurrences(of: "_", with: "")
        return lowered == "askuserquestion"
            || lowered == "question"
            || lowered == "askfollowupquestion"
    }

    /// 从 tool_input 的键存在性反推动作（有 command→shell、有 url→webfetch 等）。
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
