// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Qoder hook，把权限请求、AskUserQuestion 提问、轮次完成、
/// 会话结束等事件转发到 BetterFocusIDE 灵动岛。
///
/// 写入两个文件：一个极小的 shell 启动器（`betterfocus-notify.sh`）和承载协议
/// 的 Python 主体（`betterfocus-hook.py`）。所有 JSON 处理都放在 Python 侧，
/// 使 hook 无需依赖 `jq`；反正要连 socket 就已经需要 python3。hook 分组带标记
/// 合并进 `~/.qoder/settings.json`，安装/卸载只动我们自己的条目。
enum QoderHookInstaller {
    static let marker = InstallerPaths.marker

    // MARK: - 生命周期

    /// 安装：写脚本 + 写 Python 主体 + 合并 settings 注册 hook。
    static func install() throws {
        try ensureFile(path: InstallerPaths.qoderScriptPath,
                       content: scriptContent, executable: true)
        try ensureFile(path: InstallerPaths.qoderHelperPath,
                       content: helperContent, executable: false)
        try mergeSettings()
    }

    /// 卸载：删除两个文件并从 settings 移除我们的 hook 分组。
    static func uninstall() {
        try? FileManager.default.removeItem(atPath: InstallerPaths.qoderScriptPath)
        try? FileManager.default.removeItem(atPath: InstallerPaths.qoderHelperPath)
        removeHookFromSettings()
    }

    /// 通过启动脚本是否存在判断安装状态。
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: InstallerPaths.qoderScriptPath)
    }

    // MARK: - Settings 合并

    /// 在 `hooks` 内新增或刷新我们自己的 matcher 分组，其余事件与分组原样保留。
    ///
    /// 注册四个事件：
    ///   - PermissionRequest（matcher `*`）：真正的权限通道。
    ///   - PreToolUse（matcher `*`）：遗留提问入口；hook 只处理 AskUserQuestion，
    ///     其他立即退出。
    ///   - SessionEnd / Stop：发后即忘，短超时，绝不阻塞会话。
    static func mergedHooks(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooksAfterRemoval(hooks)

        func entry(matcher: String, timeout: Int) -> [String: Any] {
            [
                "_betterfocus_marker": marker,
                "matcher": matcher,
                "hooks": [[
                    "type": "command",
                    "command": InstallerPaths.qoderScriptPath,
                    "timeout": timeout,
                ]],
            ]
        }

        let specs: [(String, String, Int)] = [
            ("PreToolUse", "*", InstallerPaths.hookTimeoutSeconds),
            ("PermissionRequest", "*", InstallerPaths.hookTimeoutSeconds),
            ("SessionEnd", "*", 5),
            ("Stop", "*", 5),
        ]
        for (event, matcher, timeout) in specs {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let newEntry = entry(matcher: matcher, timeout: timeout)
            // 已有我们的分组则原地替换，否则追加。
            if let idx = groups.firstIndex(where: { isOurGroup($0) }) {
                groups[idx] = newEntry
            } else {
                groups.append(newEntry)
            }
            hooks[event] = groups
        }
        return hooks
    }

    /// 从各事件中剔除属于我们的分组；某事件剔空后连键一起移除。
    static func hooksAfterRemoval(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for event in ["PreToolUse", "PermissionRequest", "SessionEnd", "Stop"] {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isOurGroup($0) }
            if groups.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = groups }
        }
        return hooks
    }

    /// 判断某分组是否属于我们：优先看标记，兼容旧的扁平结构（command 指向我们脚本）。
    private static func isOurGroup(_ group: [String: Any]) -> Bool {
        if (group["_betterfocus_marker"] as? String) == marker { return true }
        // 遗留扁平形态：无 hooks 数组，command 直接指向我们的脚本。
        if group["hooks"] is [Any] { return false }
        if let command = group["command"] as? String,
           command.contains("betterfocus-notify.sh") { return true }
        return false
    }

    /// 把合并后的 hooks 原子写回 `~/.qoder/settings.json`。
    private static func mergeSettings() throws {
        var settings = loadSettings()
        settings["hooks"] = mergedHooks(settings["hooks"] as? [String: Any] ?? [:])
        let dir = (InstallerPaths.qoderSettingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath),
                       options: .atomic)
    }

    /// 从 settings 移除我们的 hook 分组后写回（卸载路径，容错不抛错）。
    private static func removeHookFromSettings() {
        var settings = loadSettings()
        guard !settings.isEmpty else { return }
        let merged = hooksAfterRemoval(settings["hooks"] as? [String: Any] ?? [:])
        if merged.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = merged }
        if let data = try? JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath),
                            options: .atomic)
        }
    }

    /// 读取现有 Qoder settings；缺失或畸形时返回空字典。
    private static func loadSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    // MARK: - 文件写入（幂等）

    /// 仅在内容不同时才写入，避免重复安装扰动 mtime（那会让平台误以为脚本刚变更）。
    private static func ensureFile(path: String, content: String, executable: Bool) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let existing = try? String(contentsOfFile: path, encoding: .utf8),
           existing == content {
            if executable { chmod(path, 0o755) }
            return
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        if executable { chmod(path, 0o755) }
    }

    // MARK: - 模板

    /// 极小 shell 启动器。python3 缺失时回退到 Qoder 自带对话框，
    /// 使请求绝不会卡在一张没人看见的卡片上。
    static var scriptContent: String {
        """
        #!/bin/bash
        # BetterFocusIDE ↔ Qoder hook launcher. Forwards permission requests,
        # AskUserQuestion, turn-finished and session-end to the Dynamic Island.
        # All JSON work lives in betterfocus-hook.py beside it (no `jq` needed).

        SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
        PYTHON=$(command -v python3 || echo /usr/bin/python3)

        if [ ! -x "$PYTHON" ]; then
          printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"ask","permissionDecisionReason":"python3 is not installed; ask in the Qoder dialog."}}'
          exit 0
        fi

        exec "$PYTHON" "$SELF_DIR/betterfocus-hook.py"
        """
    }

    /// Python hook 主体。占位符替换为本构建的命名空间路径，使 hook 指向
    /// BetterFocusIDE 而非 Vorssaint。
    static var helperContent: String {
        HelperTemplate.body
            .replacingOccurrences(of: "__SOCKET_PATH__", with: InstallerPaths.socketPath)
            .replacingOccurrences(of: "__ANSWER_DIR__", with: InstallerPaths.answerDir)
            .replacingOccurrences(of: "__SETTINGS_PATH__", with: InstallerPaths.settingsPath)
            .replacingOccurrences(of: "__QUESTION_TIMEOUT__", with: "\(InstallerPaths.questionTimeoutSeconds)")
            .replacingOccurrences(of: "__PERMISSION_TIMEOUT__", with: "\(InstallerPaths.permissionTimeoutSeconds)")
    }
}
