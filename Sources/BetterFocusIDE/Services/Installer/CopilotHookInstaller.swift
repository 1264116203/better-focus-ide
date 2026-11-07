// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 GitHub Copilot CLI 的用户级 hook。
///
/// Copilot 从 `~/.copilot/hooks/*.json` 加载 hook（`COPILOT_HOME` 设了则改读
/// 那个目录）。我们只写自己的 `betterfocus.json`，不改 `settings.json`，
/// 同目录里别人的 json 一个字节不动。
///
/// 条目是扁平的（`type` / `command` / `matcher` / `timeoutSec`），不是 Claude
/// 那种 `{matcher, hooks:[...]}` 嵌套。事件名用 PascalCase，载荷就是现有
/// `claude` 方言能认的 snake_case；stdout 协议不同，由 `EVENT_STYLE=copilot`
/// 在 `emit()` 里分开。
///
/// 能做的事：
/// 1. `PreToolUse(AskUserQuestion)` —— 对应运行时工具 `ask_user`。只挂这一条：
///    Copilot 的 command `preToolUse` 失败是 fail-closed，挂上全量工具等于
///    脚本一崩就拒绝所有工具调用。
/// 2. `PermissionRequest` / `Notification(permission_prompt)` —— 只提醒。
///    空 stdout + 退出码 0 才是「交给原生对话框」；退出码 2 会被当成拒绝。
/// 3. `UserPromptSubmit` / `Stop` / `SessionEnd` —— 回合标题、完成横幅、会话结束。
/// 4. `PostToolUse` 的 todo 家族 —— 进度条，形状对得上才转发。
enum CopilotHookInstaller {
    static var scriptPath: String { InstallerPaths.copilotScriptPath }
    static var helperPath: String { InstallerPaths.copilotHelperPath }
    static var configPath: String { InstallerPaths.copilotHooksConfigPath }

    /// 配置目录或可执行文件有一个就算装过。CLI 第一次启动才会建 `~/.copilot`，
    /// 只看目录会把「刚装好还没打开」误判成没装。
    static var isPresent: Bool {
        if InstallerPaths.hostDirectoryExists(InstallerPaths.copilotDir) { return true }
        let fm = FileManager.default
        let fixed = [
            "/opt/homebrew/bin/copilot",
            "/usr/local/bin/copilot",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/copilot"),
        ]
        if fixed.contains(where: { fm.isExecutableFile(atPath: $0) }) { return true }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { dir in
            fm.isExecutableFile(atPath: (String(dir) as NSString).appendingPathComponent("copilot"))
        }
    }

    static func install() throws {
        try HookInstallerSupport.ensureFile(path: scriptPath,
                                            content: HookInstallerSupport.scriptContent(),
                                            executable: true)
        try HookInstallerSupport.ensureFile(path: helperPath,
                                            content: helperContent,
                                            executable: false)
        let document = hookDocument(scriptPath: scriptPath,
                                    questionTimeout: InstallerPaths.hookTimeoutSeconds)
        try HookInstallerSupport.writeJSON(document, to: configPath)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: helperPath)
        try? FileManager.default.removeItem(atPath: configPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    static var isRegistered: Bool {
        let config = HookInstallerSupport.loadJSON(configPath)
        guard (config["version"] as? Int) == 1,
              let hooks = config["hooks"] as? [String: Any] else { return false }
        let expected = ["PreToolUse", "PermissionRequest", "Notification",
                        "PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd",
                        "ErrorOccurred", "PostToolUseFailure", "SubagentStop", "PreCompact"]
        return expected.allSatisfy { event in
            let entries = hooks[event] as? [[String: Any]] ?? []
            return entries.contains { HookInstallerSupport.isOurCommand($0["command"]) }
        }
    }

    /// 给 Copilot 的那一份 hook 文件。`questionTimeout` 单独传入，测试不必读 Settings。
    static func hookDocument(scriptPath: String, questionTimeout: Int) -> [String: Any] {
        func entry(_ timeout: Int, matcher: String? = nil) -> [String: Any] {
            var item: [String: Any] = [
                "type": "command",
                "command": scriptPath,
                "timeoutSec": timeout,
            ]
            if let matcher { item["matcher"] = matcher }
            return item
        }
        // PostToolUse 的 matcher 是整名正则。PascalCase 会把工具名翻成
        // TodoWrite，camelCase 载荷仍是 update_todo，两边都列上。
        let todos = InstallerPaths.todoToolMatcher + "|update_todo"
        return [
            "version": 1,
            "hooks": [
                "PreToolUse": [entry(questionTimeout, matcher: "AskUserQuestion")],
                "PermissionRequest": [entry(5)],
                "Notification": [entry(5, matcher: InstallerPaths.attentionNotificationMatcher)],
                "PostToolUse": [entry(5, matcher: todos)],
                "UserPromptSubmit": [entry(5)],
                "Stop": [entry(5)],
                "SessionEnd": [entry(5)],
                "ErrorOccurred": [entry(5)],
                "PostToolUseFailure": [entry(5)],
                "SubagentStop": [entry(5)],
                "PreCompact": [entry(5)],
            ] as [String: Any],
        ]
    }

    /// 兜底身份留空：CLI 跑在终端里，父进程走查到哪个终端，卡片就标哪个。
    static var helperContent: String {
        HookInstallerSupport.helperContent(
            provider: "copilot", style: "copilot",
            hostBundle: "", hostName: "", hostPath: "")
    }
}
