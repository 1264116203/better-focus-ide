// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Kimi Code CLI 的用户级 hook（`~/.kimi-code/config.toml`）。
///
/// 与 Claude 系的 JSON 不同，Kimi 把 hook 写成 TOML 的数组表：
///
/// ```toml
/// [[hooks]]
/// event = "Stop"
/// command = "/Users/you/.kimi-code/hooks/betterfocus-notify.sh"
/// timeout = 30
/// ```
///
/// 而且 `[[hooks]]` **只允许这 4 个字段**，多写一个字符整份配置都加载失败——
/// 所以这里不能用「加个 marker 字段方便识别」的常见套路，只能靠
/// `command` 里是否含 `betterfocus-notify.sh` 来认自己的条目，并且整段用
/// 注释界标包起来（见 `ManagedTOML`）。
///
/// 事件方言与 Claude 一致（PascalCase + `permissionDecision` 回灌），
/// 但 Kimi 的 `PermissionRequest` / `Notification` 都是**不可阻断**的观测事件，
/// 正好符合「权限只提醒不拦截」的定位。
enum KimiHookInstaller {
    /// 新旧两个产品目录：Kimi Code CLI 用 `~/.kimi-code`，早期 kimi-cli 用 `~/.kimi`。
    /// 写已存在的那个；两个都没有时新建 `~/.kimi-code`（较新的产品线）。
    static var targetDir: String {
        if InstallerPaths.hostDirectoryExists(InstallerPaths.kimiCodeDir) {
            return InstallerPaths.kimiCodeDir
        }
        if InstallerPaths.hostDirectoryExists(InstallerPaths.kimiLegacyDir) {
            return InstallerPaths.kimiLegacyDir
        }
        return InstallerPaths.kimiCodeDir
    }

    static var configPath: String { InstallerPaths.kimiConfigPath(targetDir) }
    static var scriptPath: String { InstallerPaths.kimiScriptPath(targetDir) }
    static var helperPath: String { InstallerPaths.kimiHelperPath(targetDir) }

    /// 宿主是否装在本机：配置目录存在，或 Kimi 应用在 /Applications 里。
    static var isPresent: Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.kimiCodeDir)
            || InstallerPaths.hostDirectoryExists(InstallerPaths.kimiLegacyDir)
            || FileManager.default.fileExists(atPath: "/Applications/Kimi.app")
    }

    /// 事件与超时。Kimi 的 `timeout` 上限是 600s，超了会让配置加载失败。
    ///
    /// `PostToolUse` 匹配 todo 家族：Kimi 原生的 `SetTodoList` 是整表覆盖，
    /// 其余（TodoWrite / TaskCreate / TaskUpdate）兼容 Claude 血统的旧入口。
    static var specs: [HookGroupSpec] {
        let wait = min(600, InstallerPaths.hookTimeoutSeconds)
        return [
            HookGroupSpec("PreToolUse", matcher: "AskUserQuestion", timeout: wait),
            HookGroupSpec("PermissionRequest", matcher: "", timeout: 5),
            // Notification 的官方 matcher 是 `task.completed` 这类任务状态，
            // 不是权限提醒。权限走 PermissionRequest，这条不再登记。
            HookGroupSpec("PostToolUse", matcher: InstallerPaths.todoToolMatcher, timeout: 5),
            HookGroupSpec("PostToolUseFailure", matcher: "", timeout: 5),
            HookGroupSpec("Stop", matcher: "", timeout: 5),
            HookGroupSpec("SessionEnd", matcher: "", timeout: 5),
        ]
    }

    // MARK: - 生命周期

    static func install() throws {
        try HookInstallerSupport.ensureFile(path: scriptPath,
                                            content: HookInstallerSupport.scriptContent(),
                                            executable: true)
        try HookInstallerSupport.ensureFile(path: helperPath,
                                            content: helperContent,
                                            executable: false)
        let current = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
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

    /// 受管区块正文：每条事件一个 `[[hooks]]` 表。
    static var tomlBlock: String {
        var lines: [String] = []
        for (index, spec) in specs.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("[[hooks]]")
            lines.append("event = \"\(spec.event)\"")
            if !spec.matcher.isEmpty {
                lines.append("matcher = \"\(spec.matcher)\"")
            }
            lines.append("command = \"\(scriptPath)\"")
            lines.append("timeout = \(spec.timeout)")
        }
        return ManagedTOML.block(lines)
    }

    /// Kimi 侧正文：`claude` 方言；兜底身份留空，让父进程走查找到真正的终端。
    static var helperContent: String {
        HookInstallerSupport.helperContent(provider: "kimi", style: "claude",
                                           hostBundle: "", hostName: "", hostPath: "")
    }
}
