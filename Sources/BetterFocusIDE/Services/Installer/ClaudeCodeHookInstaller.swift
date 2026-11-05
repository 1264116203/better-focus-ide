// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Claude Code 用户级 hook（`~/.claude/settings.json`）。
///
/// Claude Code 是这套 hook 协议的事实标准，WorkBuddy / Trae / Qoder 都向它对齐，
/// 因此直接复用 `claude` 方言（PascalCase 事件 + `hookSpecificOutput.permissionDecision`）。
///
/// 只做三件事：
/// 1. `PreToolUse(AskUserQuestion)` —— 把提问接管到灵动岛，用 deny + reason 把答案回灌；
/// 2. `Notification(permission_prompt)` / `PermissionRequest` —— 权限只提醒不拦截，
///    stdout 保持静默，Claude Code 自己的对话框继续负责审批；
/// 3. `Stop` / `SessionEnd` —— 回合完成与会话结束横幅。
///
/// 不接管 `permissionDecision: allow` 是有意的：替用户放行等于绕过审批。
enum ClaudeCodeHookInstaller {
    static let scriptPath = InstallerPaths.claudeScriptPath
    static let helperPath = InstallerPaths.claudeHelperPath
    static let configPath = InstallerPaths.claudeSettingsPath

    /// 注册的事件顺序固定，便于自检比对。
    ///
    /// `PostToolUse` 匹配 todo 家族工具名：Claude Code 旧版是 `TodoWrite`，
    /// 新版 V2 换成 `TaskCreate` / `TaskUpdate`（一条任务一次调用，脚本按单条
    /// UPSERT 转发）。matcher 是 JavaScript 正则，`|` 表示逻辑或。
    static var specs: [HookGroupSpec] {
        [
            HookGroupSpec("PreToolUse", matcher: "AskUserQuestion",
                          timeout: InstallerPaths.hookTimeoutSeconds),
            HookGroupSpec("PermissionRequest", matcher: "", timeout: 5),
            HookGroupSpec("Notification", matcher: "permission_prompt", timeout: 5),
            HookGroupSpec("PostToolUse", matcher: InstallerPaths.todoToolMatcher, timeout: 5),
            HookGroupSpec("Stop", matcher: "", timeout: 5),
            HookGroupSpec("SessionEnd", matcher: "", timeout: 5),
        ]
    }

    static var installer: HookGroupInstaller {
        HookGroupInstaller(configPath: configPath,
                           scriptPath: scriptPath,
                           helperPath: helperPath,
                           scriptContent: HookInstallerSupport.scriptContent(),
                           helperContent: helperContent,
                           specs: specs,
                           requiresVersionOne: false)
    }

    static func install() throws { try installer.install() }
    static func uninstall() { installer.uninstall() }
    static var isInstalled: Bool { installer.isInstalled }
    static var isRegistered: Bool { installer.isRegistered }

    /// Claude Code 侧：`claude` 方言。宿主兜底身份留空——CLI 一定跑在某个终端里，
    /// 让 hook 顺着父进程走找到那个终端（Warp / iTerm / Terminal），
    /// 卡片上才会显示「Claude Code（Warp）」并用终端图标。
    static var helperContent: String {
        HookInstallerSupport.helperContent(
            provider: "claude_code", style: "claude",
            hostBundle: "", hostName: "", hostPath: "")
    }
}
