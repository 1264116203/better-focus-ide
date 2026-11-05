// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 Qoder CN（通义灵码）的 hook（`~/.qoder-cn/settings.json`）。
///
/// 与 Qoder 英文版**完全同构**：同一份 Python 正文、同一套 matcher 分组、
/// 同一组事件（PreToolUse / PermissionRequest / Stop / SessionEnd）。
/// 唯一的区别是根目录（`~/.qoder-cn`）与产品名——启动器里多一行
/// `export BETTERFOCUS_VARIANT=cn`，识别结果就从 `qoder_cli` 变成 `qoder_cn_cli`，
/// 卡片上才不会把国内版记成国际版。
enum QoderCnHookInstaller {
    static let scriptPath = InstallerPaths.qoderCnScriptPath
    static let helperPath = InstallerPaths.qoderCnHelperPath
    static let configPath = InstallerPaths.qoderCnSettingsPath

    /// 宿主是否装在本机。
    ///
    /// `~/.qoder-cn` 常被链到 `~/.qoder`（同一安装的两个入口名），那种情况
    /// 算装了英文版，不算装了 CN 版——否则 CN 的安装器会覆盖英文版的注册。
    static var isPresent: Bool {
        InstallerPaths.hostDirectoryIsDistinct(InstallerPaths.qoderCnDir,
                                               from: InstallerPaths.qoderDir)
    }

    /// 事件与 Qoder 一致：权限是真正通道，PreToolUse 兜提问，
    /// Stop / SessionEnd 发后即忘所以给 5s。
    static var specs: [HookGroupSpec] {
        [
            HookGroupSpec("PreToolUse", matcher: "*", timeout: InstallerPaths.hookTimeoutSeconds),
            HookGroupSpec("PermissionRequest", matcher: "*", timeout: InstallerPaths.hookTimeoutSeconds),
            HookGroupSpec("SessionEnd", matcher: "*", timeout: 5),
            HookGroupSpec("Stop", matcher: "*", timeout: 5),
        ]
    }

    static var installer: HookGroupInstaller {
        HookGroupInstaller(configPath: configPath,
                           scriptPath: scriptPath,
                           helperPath: helperPath,
                           scriptContent: scriptContent,
                           // 正文与英文版逐字节相同：路径走的是应用自己的
                           // Application Support 命名空间，与宿主无关。
                           helperContent: QoderHookInstaller.helperContent,
                           specs: specs,
                           requiresVersionOne: false)
    }

    static func install() throws { try installer.install() }
    static func uninstall() { installer.uninstall() }
    static var isInstalled: Bool { installer.isInstalled }
    static var isRegistered: Bool { installer.isRegistered }

    /// 启动器：与 Qoder 相同，多 export 一个发行版标记。
    ///
    /// python3 缺失时回 `ask`，让 Qoder CN 自己的对话框接手——绝不把请求
    /// 卡在一张没人看得见的卡片上。
    static var scriptContent: String {
        """
        #!/bin/bash
        # BetterFocusIDE <-> Qoder CN hook launcher. Same protocol as the Qoder
        # installer; BETTERFOCUS_VARIANT=cn switches the reported product name
        # to the qoder_cn_* namespace.

        export BETTERFOCUS_VARIANT=cn

        SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
        PYTHON=$(command -v python3 || echo /usr/bin/python3)

        if [ ! -x "$PYTHON" ]; then
          printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"ask","permissionDecisionReason":"python3 is not installed; ask in the Qoder CN dialog."}}'
          exit 0
        fi

        exec "$PYTHON" "$SELF_DIR/betterfocus-hook.py" "$@"
        """
    }
}
