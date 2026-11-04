// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Trae 系列的用户级 hook（`~/.trae/hooks.json`、`~/.trae-cn/hooks.json`）。
///
/// Trae 的 hooks 结构与 Claude Code 同构（`version: 1` + 按事件分组的 matcher 组），
/// 事件名也是 PascalCase，因此复用 `claude` 方言的 Python 正文。
///
/// 差异点只有两个，都直接影响能不能用：
/// 1. **没有 `SessionEnd`**。Trae 只有六类事件（SessionStart / UserPromptSubmit /
///    PreToolUse / PostToolUse / Stop / Notification），会话结束不会通知我们，
///    待答卡片只能靠自己的超时收场。
/// 2. **`Notification` 的 matcher 匹配的是 `notification_type`**，不是工具名。
///    所以这里写字面量 `permission_prompt`，否则权限提醒永远不触发。
enum TraeHookInstaller {
    /// Trae 的两个发行版。国内版在 `~/.trae-cn`，国际版在 `~/.trae`。
    enum Flavor {
        case cn
        case international

        var dir: String {
            switch self {
            case .cn: return InstallerPaths.traeCnDir
            case .international: return InstallerPaths.traeDir
            }
        }

        var displayName: String {
            switch self {
            case .cn: return "Trae CN"
            case .international: return "Trae"
            }
        }

        /// hook 侧 provider 标识。
        var provider: String {
            switch self {
            case .cn: return "trae_cn"
            case .international: return "trae"
            }
        }

        /// 父进程走查失败时的兜底宿主身份。
        var hostBundle: String {
            switch self {
            case .cn: return "cn.trae.app"
            case .international: return "com.trae.app"
            }
        }

        var hostPath: String {
            switch self {
            case .cn: return "/Applications/Trae CN.app"
            case .international: return "/Applications/Trae.app"
            }
        }

        /// 宿主是否装在本机：目录存在（跑过一次）或应用在 /Applications 里。
        var isPresent: Bool {
            InstallerPaths.hostDirectoryExists(dir)
                || FileManager.default.fileExists(atPath: hostPath)
        }
    }

    static var specs: [HookGroupSpec] {
        [
            HookGroupSpec("PreToolUse", matcher: "AskUserQuestion",
                          timeout: InstallerPaths.hookTimeoutSeconds),
            HookGroupSpec("Notification", matcher: "permission_prompt", timeout: 5),
            HookGroupSpec("Stop", matcher: "", timeout: 5),
        ]
    }

    static func installer(_ flavor: Flavor) -> HookGroupInstaller {
        HookGroupInstaller(configPath: InstallerPaths.traeHooksConfigPath(flavor.dir),
                           scriptPath: InstallerPaths.traeScriptPath(flavor.dir),
                           helperPath: InstallerPaths.traeHelperPath(flavor.dir),
                           scriptContent: HookInstallerSupport.scriptContent(),
                           helperContent: helperContent(flavor),
                           specs: specs,
                           requiresVersionOne: true)
    }

    static func install(_ flavor: Flavor) throws {
        try installer(flavor).install()
    }

    static func uninstall(_ flavor: Flavor) {
        installer(flavor).uninstall()
    }

    static func isInstalled(_ flavor: Flavor) -> Bool {
        installer(flavor).isInstalled
    }

    static func isRegistered(_ flavor: Flavor) -> Bool {
        installer(flavor).isRegistered
    }

    /// Trae 侧正文：`claude` 方言，兜底身份指向对应的 Trae 应用。
    static func helperContent(_ flavor: Flavor) -> String {
        HookInstallerSupport.helperContent(provider: flavor.provider, style: "claude",
                                           hostBundle: flavor.hostBundle,
                                           hostName: flavor.displayName,
                                           hostPath: flavor.hostPath)
    }
}
