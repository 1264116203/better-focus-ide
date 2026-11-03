// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Hook / Plugin 集成的路径命名空间中枢。
///
/// BetterFocusIDE 使用独立目录，从而可与 Vorssaint 并存运行，二者不会争抢
/// 同一个 socket / 应答目录 / hook 分组。
///
///   - Socket : ~/Library/Application Support/BetterFocusIDE/agent-events.sock
///   - Answers: ~/Library/Application Support/BetterFocusIDE/answers
///   - Hook   : ~/.qoder/hooks/betterfocus-notify.sh (+ betterfocus-hook.py)
///   - Plugin : ~/.config/opencode/plugins/betterfocus-notify.js
enum InstallerPaths {
    /// 数据目录命名空间（决定 Application Support 下的子目录名）。
    static let namespace = "BetterFocusIDE"
    /// 写入已安装 Qoder hook 分组的标记，确保安装/卸载只动我们自己的条目，
    /// 绝不触碰同事的 hooks。
    static let marker = "betterfocus"

    /// 当前用户主目录。
    static let home = NSHomeDirectory()

    // MARK: 本应用数据目录

    static var appSupport: String {
        (home as NSString).appendingPathComponent("Library/Application Support/\(namespace)")
    }
    static var socketPath: String {
        (appSupport as NSString).appendingPathComponent("agent-events.sock")
    }
    static var answerDir: String {
        (appSupport as NSString).appendingPathComponent("answers")
    }
    static var settingsPath: String {
        (appSupport as NSString).appendingPathComponent("settings.json")
    }

    // MARK: Qoder

    static var qoderDir: String { (home as NSString).appendingPathComponent(".qoder") }
    static var qoderSettingsPath: String { (qoderDir as NSString).appendingPathComponent("settings.json") }
    static var qoderHooksDir: String { (qoderDir as NSString).appendingPathComponent("hooks") }
    static var qoderScriptPath: String { (qoderHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh") }
    static var qoderHelperPath: String { (qoderHooksDir as NSString).appendingPathComponent("betterfocus-hook.py") }

    // MARK: OpenCode

    static var opencodePluginsDir: String {
        (home as NSString).appendingPathComponent(".config/opencode/plugins")
    }
    static var opencodePluginPath: String {
        (opencodePluginsDir as NSString).appendingPathComponent("betterfocus-notify.js")
    }

    // MARK: 超时参数

    /// 卡片侧等待上限；Hook / Plugin 的轮询超时跟随它，确保卡片总是先于平台过期。
    /// Qoder 额外给脚本 +60s 缓冲，之后才杀死 hook。修改 `agentWaitLimit`
    /// （needs=reinstall）会重新运行安装器，用这些值重新生成 hook。
    static var questionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var permissionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var hookTimeoutSeconds: Int { Settings.shared.agentWaitLimit + 60 }
}
