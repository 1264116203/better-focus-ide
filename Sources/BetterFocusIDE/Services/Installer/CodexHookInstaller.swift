// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Codex CLI 的通知钩子（`~/.codex/config.toml` 的 `notify`）。
///
/// Codex 没有通用 hook，只有一个 `notify` 程序：每个事件把一段 JSON 作为
/// **单个命令行参数**传给它，当前只发 `agent-turn-complete`。
///
/// ```toml
/// notify = ["/bin/bash", "/Users/you/.codex/hooks/betterfocus-notify.sh"]
/// ```
///
/// 由此决定了 Codex 的能力边界，写在这里免得日后被当成 bug：
/// - **有**回合完成横幅（带 thread-id / cwd / 最后一条回复）；
/// - **没有**权限接管，也没有提问接管——Codex 的审批在自己的 TUI 里完成，
///   我们既拿不到事件，也不该去抢。
///
/// `notify` 是单值键，用户可能已经配了别的通知脚本。TOML 不允许重复键，
/// 贸然追加会让整份 config.toml 解析失败，所以检测到外来 `notify` 时
/// **放弃安装并如实上报**，绝不覆盖别人的通知链。
enum CodexHookInstaller {
    static let scriptPath = InstallerPaths.codexScriptPath
    static let helperPath = InstallerPaths.codexHelperPath
    static let configPath = InstallerPaths.codexConfigPath

    /// 宿主是否装在本机。
    static var isPresent: Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.codexDir)
    }

    // MARK: - 生命周期

    static func install() throws {
        let current = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        if ManagedTOML.hasKeyOutsideBlock("notify", in: current) {
            throw NSError(domain: "BetterFocusIDE", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Codex 的 config.toml 里已有自配的 notify，未覆盖；请手动合并或先移除它。",
            ])
        }
        try HookInstallerSupport.ensureFile(path: scriptPath,
                                            content: HookInstallerSupport.scriptContent(),
                                            executable: true)
        try HookInstallerSupport.ensureFile(path: helperPath,
                                            content: helperContent,
                                            executable: false)
        let merged = ManagedTOML.applying(tomlBlock, to: current)
        guard merged != current else { return }
        try FileManager.default.createDirectory(
            atPath: (configPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try merged.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: helperPath)
        guard let current = try? String(contentsOfFile: configPath, encoding: .utf8),
              ManagedTOML.hasBlock(in: current) else { return }
        let stripped = ManagedTOML.removing(from: current)
        try? stripped.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    static var isRegistered: Bool {
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return false }
        return ManagedTOML.hasBlock(in: text) && text.contains("betterfocus-notify.sh")
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
