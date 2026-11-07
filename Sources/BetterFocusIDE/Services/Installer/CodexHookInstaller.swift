// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 安装 / 卸载 ChatGPT（原 Codex）的 hook。
///
/// 桌面应用已改名为 ChatGPT.app，`CFBundleIdentifier` 仍是 `com.openai.codex`，
/// 配置目录也还在 `~/.codex`。
///
/// 官方有两条互不覆盖的入口（https://learn.chatgpt.com/docs/hooks）：
///
/// 1. `~/.codex/hooks.json`：生命周期 hook，stdin 收 JSON，事件名 PascalCase。
///    这是我们实际登记的地方。`notify` 被别的程序占着也不影响它。
/// 2. `config.toml` 的 `notify`：单值 argv 数组，只发 `agent-turn-complete`。
///    用户（或 Computer Use）已经写过时**整段跳过**，绝不覆盖。
///
/// 登记的事件，以及对应卡片：
/// - `PermissionRequest`：权限提醒。空 stdout 表示不拍板，原生审批继续。
/// - `UserPromptSubmit` / `Stop`：回合标题与完成横幅。
/// - `SessionEnd`：会话结束。官方把这条的超时上限写成 3 秒，超过去的值不能写。
///
/// 不登记 `PreToolUse`：官方工具名是 `Bash`、`apply_patch` 和 MCP，
/// 没有 `AskUserQuestion`。挂上只会空等一个永远不来的工具。
///
/// 不登记 `PostToolUse`：官方待办工具是 `update_plan`，参数形状和
/// `TodoWrite` 对不上，挂上去只会空转。也不登记 `Notification`：事件表里没有它。
/// `SubagentStop` / `PostCompact` 有文档，只发横幅。
enum CodexHookInstaller {
    static let scriptPath = InstallerPaths.codexScriptPath
    static let helperPath = InstallerPaths.codexHelperPath
    static let configPath = InstallerPaths.codexConfigPath
    static let hooksConfigPath = InstallerPaths.codexHooksConfigPath

    /// `SessionEnd` 的超时官方上限是 3 秒。其余事件只发通知、不等人回答，5 秒足够。
    static var specs: [HookGroupSpec] {
        return [
            HookGroupSpec("PermissionRequest", matcher: "", timeout: 5),
            HookGroupSpec("UserPromptSubmit", matcher: "", timeout: 5),
            HookGroupSpec("Stop", matcher: "", timeout: 5),
            HookGroupSpec("SessionEnd", matcher: "", timeout: 3),
            HookGroupSpec("SubagentStop", matcher: "", timeout: 5),
            HookGroupSpec("PostCompact", matcher: "", timeout: 5),
        ]
    }

    static var groupInstaller: HookGroupInstaller {
        HookGroupInstaller(configPath: hooksConfigPath,
                           scriptPath: scriptPath,
                           helperPath: helperPath,
                           scriptContent: HookInstallerSupport.scriptContent(),
                           helperContent: helperContent,
                           specs: specs,
                           requiresVersionOne: false)
    }

    /// 桌面应用的 bundle id。显示名已是 ChatGPT，标识没有跟着改。
    static let appBundleID = "com.openai.codex"

    /// 宿主是否装在本机：配置目录或 ChatGPT.app 任一存在即可。
    static var isPresent: Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.codexDir)
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) != nil
    }

    // MARK: - 生命周期

    static func install() throws {
        try groupInstaller.install()
        // notify 是单值键。Computer Use 等程序已经占用时跳过，hooks.json 照常生效。
        let current = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        if ManagedTOML.hasKeyOutsideBlock("notify", in: current) { return }
        let merged = ManagedTOML.applying(tomlBlock, to: current)
        guard merged != current else { return }
        try FileManager.default.createDirectory(
            atPath: (configPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try merged.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static func uninstall() {
        groupInstaller.uninstall()
        guard let current = try? String(contentsOfFile: configPath, encoding: .utf8),
              ManagedTOML.hasBlock(in: current) else { return }
        let stripped = ManagedTOML.removing(from: current)
        try? stripped.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static var isInstalled: Bool {
        groupInstaller.isInstalled
    }

    /// 自检看 hooks.json。notify 被别人占用时仍然可以算登记成功。
    static var isRegistered: Bool {
        groupInstaller.isRegistered
    }

    // MARK: - TOML 片段

    /// notify 走 `/bin/bash` 显式启动：不依赖脚本的执行位与 shebang 解析。
    static var tomlBlock: String {
        ManagedTOML.block(["notify = [\"/bin/bash\", \"\(scriptPath)\"]"])
    }

    /// Codex 侧正文：`codex` 方言（payload 走 argv），兜底身份留空——
    /// 真正的宿主是跑着 codex 的那个终端，由父进程走查拿到。
    static var helperContent: String {
        HookInstallerSupport.helperContent(provider: "codex", style: "codex",
                                           hostBundle: "", hostName: "", hostPath: "")
    }
}
