// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Cursor 用户级 hook（`~/.cursor/hooks.json`）。
///
/// 只注册**观测型**事件，且一律回合法空对象（`beforeSubmitPrompt` 回
/// `{"continue": true}`）。`subagentStop`、`preCompact` 只发横幅。
/// 工具调用失败不通知。权限类 hook（`preToolUse` /
/// `beforeShellExecution` 等）要求返回 `allow` / `deny`，那会替用户改变
/// 审批流程；输出非法 JSON 甚至会直接阻塞工具调用。因此 Cursor 侧不做提问与权限。
///
/// hooks.json 里其余事件、其余 hook 定义原样保留，识别自己的条目只靠
/// `command` 是否指向 `betterfocus-notify.sh`（不引入宿主可能拒绝的自定义字段）。
enum CursorHookInstaller {
    static let scriptPath = InstallerPaths.cursorScriptPath
    static let helperPath = InstallerPaths.cursorHelperPath
    static let configPath = InstallerPaths.cursorHooksConfigPath

    /// 我们注册的事件；顺序固定，便于自检比对。
    static let events = ["beforeSubmitPrompt", "stop", "sessionEnd",
                         "subagentStop", "preCompact"]

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
        var settings = HookInstallerSupport.loadJSON(configPath)
        guard !settings.isEmpty else { return }
        let merged = hooksAfterRemoval(settings["hooks"] as? [String: Any] ?? [:])
        if merged.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = merged }
        try? HookInstallerSupport.writeJSON(settings, to: configPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    /// 配置里我们注册的事件是否都还在（供 Doctor 自检）。
    static var isRegistered: Bool {
        let hooks = HookInstallerSupport.loadJSON(configPath)["hooks"] as? [String: Any] ?? [:]
        return events.allSatisfy { event in
            let list = hooks[event] as? [[String: Any]] ?? []
            return list.contains { HookInstallerSupport.isOurCommand($0["command"]) }
        }
    }

    // MARK: - hooks.json 合并

    /// 在 hooks 内新增或刷新我们自己的定义，其他事件与其他 hook 原样保留。
    static func mergedHooks(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooksAfterRemoval(hooks)
        let entry: [String: Any] = [
            "command": scriptPath,
            "timeout": 5,
        ]
        for event in events {
            var list = hooks[event] as? [[String: Any]] ?? []
            list.append(entry)
            hooks[event] = list
        }
        return hooks
    }

    /// 从所有事件中剔除指向我们脚本的定义；剔空后连键一起移除。
    static func hooksAfterRemoval(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let kept = list.filter { !HookInstallerSupport.isOurCommand($0["command"]) }
            if kept.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = kept }
        }
        return hooks
    }

    /// 读-改-写：保留 `version` 与所有其他顶层字段，原子写回并恢复权限。
    private static func mergeSettings() throws {
        var settings = HookInstallerSupport.loadJSON(configPath)
        settings["version"] = 1
        settings["hooks"] = mergedHooks(settings["hooks"] as? [String: Any] ?? [:])
        try HookInstallerSupport.writeJSON(settings, to: configPath)
    }

    // MARK: - 模板

    /// Cursor 侧：camelCase 观测型事件方言，兜底宿主身份为 Cursor。
    static var helperContent: String {
        HookInstallerSupport.helperContent(
            provider: "cursor", style: "cursor",
            hostBundle: "com.todesktop.230313mzl4w4u92", hostName: "Cursor",
            hostPath: "/Applications/Cursor.app")
    }
}
