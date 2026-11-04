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
/// `settings.json` 同时存放账号、插件等敏感配置，安装器只增删带
/// `_betterfocus_marker` 的分组，其余键原样保留，并保留原文件权限（0600）。
enum WorkBuddyHookInstaller {
    static let scriptPath = InstallerPaths.workbuddyScriptPath
    static let helperPath = InstallerPaths.workbuddyHelperPath
    static let settingsPath = InstallerPaths.workbuddySettingsPath

    /// 注册的事件与 matcher：提问走精确匹配，避免每个工具调用都拉起 Python。
    static let specs: [(event: String, matcher: String, timeout: Int)] = [
        ("PreToolUse", "AskUserQuestion", InstallerPaths.hookTimeoutSeconds),
        ("PermissionRequest", "*", 5),
        ("Stop", "", 5),
        ("SessionEnd", "", 5),
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

        func group(matcher: String, timeout: Int) -> [String: Any] {
            [
                "_betterfocus_marker": InstallerPaths.marker,
                "matcher": matcher,
                "hooks": [[
                    "type": "command",
                    "command": scriptPath,
                    "timeout": timeout,
                ]],
            ]
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

    /// 从各事件中剔除属于我们的分组；某事件剔空后连键一起移除。
    static func hooksAfterRemoval(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for spec in specs {
            guard var groups = hooks[spec.event] as? [[String: Any]] else { continue }
            groups.removeAll { HookInstallerSupport.isOurGroup($0) }
            if groups.isEmpty { hooks.removeValue(forKey: spec.event) }
            else { hooks[spec.event] = groups }
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
