// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 WorkBuddy 用户级 hook（`~/.workbuddy/settings.json` 的 `hooks`）。
///
/// WorkBuddy 的 hook 协议与 Claude Code / Qoder 同构：PascalCase 事件名、
/// `hookSpecificOutput.permissionDecision` 决策、stdin 携带
/// `session_id` / `cwd` / `transcript_path` / `tool_input`。因此可以完整复用
/// 灵动岛的提问与应答文件通道。
///
/// 事件选择依据（WorkBuddy / CodeBuddy 官方 Hooks 文档）：
/// - `PreToolUse` + `AskUserQuestion`：用户已在宿主里答完后才到。不再开提问卡，
///   stdout 保持静默，避免答完后又弹第二次。
/// - `Notification` + `permission_prompt`：官方推荐的权限提醒入口，纯观测、不返回决策。
/// - `PermissionRequest`：新版 27+ 事件族中的权限事件，带 tool_name / tool_input，
///   信息更全；与 Notification 同时触发时由岛侧 `NoticeController` 去抖。
/// - `Stop` / `SessionEnd`：回合完成与会话结束；这两类事件不使用 matcher。
///
/// `settings.json` 同时存放账号、插件等敏感配置，安装器只增删 command 指向
/// `betterfocus-notify.sh` 的分组，其余键原样保留，并保留原文件权限（通常为 0600）。
enum WorkBuddyHookInstaller {
    static let scriptPath = InstallerPaths.workbuddyScriptPath
    static let helperPath = InstallerPaths.workbuddyHelperPath
    static let settingsPath = InstallerPaths.workbuddySettingsPath

    /// 注册的事件与 matcher。`nil` 表示该事件不使用 matcher（Stop / SessionEnd）。
    ///
    /// `PostToolUse` 匹配 todo 家族：WorkBuddy 现行工具集是 `TaskCreate` /
    /// `TaskUpdate`（V2 家族，单条 UPSERT），旧版 `TodoWrite` 整表覆盖也一并
    /// 兼容——脚本按工具名分流到 todo_item_updated / todo_updated。
    static let specs: [(event: String, matcher: String?, timeout: Int)] = [
        ("PreToolUse", "AskUserQuestion", InstallerPaths.hookTimeoutSeconds),
        ("Notification", InstallerPaths.attentionNotificationMatcher, 5),
        ("PermissionRequest", nil, 5),
        ("PostToolUse", InstallerPaths.todoToolMatcher, 5),
        ("UserPromptSubmit", nil, 5),
        ("Stop", nil, 5),
        ("SessionEnd", nil, 5),
        ("StopFailure", nil, 5),
        ("PermissionDenied", nil, 5),
        ("SubagentStop", nil, 5),
        ("PostCompact", nil, 5),
        ("Elicitation", nil, 5),
    ]

    // MARK: - 生命周期

    static func install() throws {
        try HookInstallerSupport.ensureFile(path: scriptPath,
                                            content: HookInstallerSupport.scriptContent(),
                                            executable: true)
        try HookInstallerSupport.ensureFile(path: helperPath,
                                            content: helperContent, executable: false)
        try mergeSettings()
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: helperPath)
        var settings = HookInstallerSupport.loadJSON(settingsPath)
        guard !settings.isEmpty else { return }
        let merged = hooksAfterRemoval(settings["hooks"] as? [String: Any] ?? [:])
        if merged.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = merged }
        try? HookInstallerSupport.writeJSON(settings, to: settingsPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    /// 配置里我们注册的事件是否都还在（供 Doctor 自检）。
    static var isRegistered: Bool {
        let hooks = HookInstallerSupport.loadJSON(settingsPath)["hooks"] as? [String: Any] ?? [:]
        return specs.allSatisfy { spec in
            let groups = hooks[spec.event] as? [[String: Any]] ?? []
            return groups.contains { HookInstallerSupport.isOurGroup($0) }
        }
    }

    // MARK: - settings.json 合并

    /// 在 hooks 内新增或刷新我们自己的 matcher 分组，其余事件与分组原样保留。
    static func mergedHooks(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooksAfterRemoval(hooks)

        func group(matcher: String?, timeout: Int) -> [String: Any] {
            var result: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": scriptPath,
                    "timeout": timeout,
                ]],
            ]
            // Stop / SessionEnd 不使用 matcher：官方文档建议直接省略该字段。
            if let matcher { result["matcher"] = matcher }
            return result
        }

        for spec in specs {
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            let newGroup = group(matcher: spec.matcher, timeout: spec.timeout)
            if let idx = groups.firstIndex(where: { HookInstallerSupport.isOurGroup($0) }) {
                groups[idx] = newGroup
            } else {
                groups.append(newGroup)
            }
            hooks[spec.event] = groups
        }
        return hooks
    }

    /// 从**所有**事件中剔除属于我们的分组；某事件剔空后连键一起移除。
    /// 扫描全表而非只看 specs，避免升级后旧版注册的事件残留。
    static func hooksAfterRemoval(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { HookInstallerSupport.isOurGroup($0) }
            if groups.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = groups }
        }
        return hooks
    }

    /// 读-改-写：保留其他所有设置键，原子写回并恢复权限。
    private static func mergeSettings() throws {
        var settings = HookInstallerSupport.loadJSON(settingsPath)
        settings["hooks"] = mergedHooks(settings["hooks"] as? [String: Any] ?? [:])
        try HookInstallerSupport.writeJSON(settings, to: settingsPath)
    }

    // MARK: - 模板

    /// WorkBuddy 侧：Claude 风格事件方言，兜底宿主身份为本机实测 bundle id。
    static var helperContent: String {
        HookInstallerSupport.helperContent(
            provider: "workbuddy", style: "claude",
            hostBundle: "com.tencent.workbuddy.mac", hostName: "WorkBuddy",
            hostPath: "/Applications/WorkBuddy.app")
    }
}
