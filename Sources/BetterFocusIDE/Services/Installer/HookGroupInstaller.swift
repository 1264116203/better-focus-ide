// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 一条 hook 事件的注册规格。
struct HookGroupSpec {
    /// 宿主事件名（PascalCase，Claude Code 系方言）。
    let event: String
    /// matcher：Claude Code / Trae 用正则匹配工具名（`Notification` 匹配的是
    /// notification_type）。传空串表示「匹配全部」。
    let matcher: String
    /// 该事件允许我们脚本占用多久。发后即忘的事件给 5s 就够，
    /// 需要等用户作答的事件必须 ≥ 卡片侧的等待上限。
    let timeout: Int

    init(_ event: String, matcher: String = "", timeout: Int) {
        self.event = event
        self.matcher = matcher
        self.timeout = timeout
    }
}

/// 「JSON 里挂 matcher 分组」这一类宿主的通用安装器。
///
/// 覆盖 Claude Code（`~/.claude/settings.json`）、Trae / Trae CN
/// （`~/.trae{,-cn}/hooks.json`）。两家的 hooks 结构同构：
///
/// ```json
/// { "version": 1,
///   "hooks": { "PreToolUse": [
///       { "matcher": "AskUserQuestion",
///         "hooks": [ { "type": "command", "command": "/path/x.sh", "timeout": 60 } ] } ] } }
/// ```
///
/// 不变量（与 Qoder / WorkBuddy 安装器一致）：
/// 1. **只动自己的分组**——识别依据是 command 是否指向 `betterfocus-notify.sh`，
///    不往宿主的配置里塞自定义字段（Trae 的 schema 校验很严，多余字段可能整份失效）。
/// 2. **原地替换**——重复安装不会追加第二份分组。
/// 3. **保留其余一切**——其他事件、其他人的 hook、以及宿主自己的版本号/鉴权字段。
struct HookGroupInstaller {
    let configPath: String
    let scriptPath: String
    let helperPath: String
    let scriptContent: String
    let helperContent: String
    let specs: [HookGroupSpec]
    /// Trae 的 hooks.json 顶层需要 `"version": 1`；Claude Code 的 settings.json 不需要。
    let requiresVersionOne: Bool

    // MARK: - 生命周期

    func install() throws {
        try HookInstallerSupport.ensureFile(path: scriptPath,
                                            content: scriptContent,
                                            executable: true)
        try HookInstallerSupport.ensureFile(path: helperPath,
                                            content: helperContent,
                                            executable: false)
        var config = HookInstallerSupport.loadJSON(configPath)
        if requiresVersionOne { config["version"] = 1 }
        config["hooks"] = Self.mergedHooks(config["hooks"] as? [String: Any] ?? [:],
                                           specs: specs,
                                           scriptPath: scriptPath)
        try HookInstallerSupport.writeJSON(config, to: configPath)
    }

    func uninstall() {
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: helperPath)
        var config = HookInstallerSupport.loadJSON(configPath)
        guard !config.isEmpty else { return }
        let remaining = Self.hooksAfterRemoval(config["hooks"] as? [String: Any] ?? [:],
                                               scriptPath: scriptPath)
        if remaining.isEmpty { config.removeValue(forKey: "hooks") }
        else { config["hooks"] = remaining }
        try? HookInstallerSupport.writeJSON(config, to: configPath)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    /// 事件是否都还在（供 Doctor 自检；用户手动删了某条也能被发现）。
    var isRegistered: Bool {
        let config = HookInstallerSupport.loadJSON(configPath)
        let hooks = config["hooks"] as? [String: Any] ?? [:]
        return specs.allSatisfy { spec in
            let groups = hooks[spec.event] as? [[String: Any]] ?? []
            return groups.contains { Self.isOurGroup($0, scriptPath: scriptPath) }
        }
    }

    // MARK: - 合并

    static func mergedHooks(_ hooks: [String: Any],
                            specs: [HookGroupSpec],
                            scriptPath: String) -> [String: Any] {
        var hooks = hooksAfterRemoval(hooks, scriptPath: scriptPath)
        for spec in specs {
            let group: [String: Any] = [
                "matcher": spec.matcher,
                "hooks": [[
                    "type": "command",
                    "command": scriptPath,
                    "timeout": spec.timeout,
                ]],
            ]
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            if let idx = groups.firstIndex(where: { isOurGroup($0, scriptPath: scriptPath) }) {
                groups[idx] = group
            } else {
                groups.append(group)
            }
            hooks[spec.event] = groups
        }
        return hooks
    }

    static func hooksAfterRemoval(_ hooks: [String: Any],
                                  scriptPath: String) -> [String: Any] {
        var hooks = hooks
        for (event, value) in hooks {
            // 非数组的 hooks 值（畸形配置）原样放过，绝不清空别人的数据。
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurGroup($0, scriptPath: scriptPath) }
            if kept.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = kept }
        }
        return hooks
    }

    /// 分组是否属于我们：优先认 command 里的脚本名（不写自定义标记字段）。
    static func isOurGroup(_ group: [String: Any], scriptPath: String) -> Bool {
        if let nested = group["hooks"] as? [[String: Any]] {
            return nested.contains { HookInstallerSupport.isOurCommand($0["command"]) }
        }
        // 扁平形态：command 直接挂在分组上（早期 Qoder 写法）。
        if HookInstallerSupport.isOurCommand(group["command"]) { return true }
        return false
    }
}
