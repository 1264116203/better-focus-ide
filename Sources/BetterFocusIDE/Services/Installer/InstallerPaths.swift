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
///   - Qoder  : ~/.qoder/hooks/betterfocus-notify.sh (+ betterfocus-hook.py)
///   - Plugin : ~/.config/opencode/plugins/betterfocus-notify.js
///   - Cursor : ~/.cursor/hooks.json + ~/.cursor/hooks/betterfocus-notify.sh (+ .py)
///   - WorkBuddy: ~/.workbuddy/settings.json + ~/.workbuddy/hooks/betterfocus-notify.sh (+ .py)
///   - Claude Code: ~/.claude/settings.json + ~/.claude/hooks/betterfocus-notify.sh (+ .py)
///   - Trae / Trae CN: ~/.trae{,-cn}/hooks.json + ~/.trae{,-cn}/hooks/betterfocus-notify.sh
///   - Kimi Code CLI: ~/.kimi-code/config.toml（`[[hooks]]` 数组）+ hooks/
///   - Codex CLI: ~/.codex/hooks.json（生命周期）+ config.toml 的 notify（单值，可被占用）
///   - GitHub Copilot CLI: ~/.copilot/hooks/betterfocus.json（独立文件，不改 settings.json）
///   - Qoder CN: ~/.qoder-cn/settings.json + ~/.qoder-cn/hooks/（与 Qoder 同构）
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

    // MARK: Cursor（用户级 hooks.json，camelCase 事件）

    static var cursorDir: String { (home as NSString).appendingPathComponent(".cursor") }
    static var cursorHooksConfigPath: String {
        (cursorDir as NSString).appendingPathComponent("hooks.json")
    }
    static var cursorHooksDir: String { (cursorDir as NSString).appendingPathComponent("hooks") }
    static var cursorScriptPath: String {
        (cursorHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var cursorHelperPath: String {
        (cursorHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: WorkBuddy（用户级 settings.json 的 hooks 字段，Claude Code 风格事件）

    static var workbuddyDir: String { (home as NSString).appendingPathComponent(".workbuddy") }
    static var workbuddySettingsPath: String {
        (workbuddyDir as NSString).appendingPathComponent("settings.json")
    }
    static var workbuddyHooksDir: String {
        (workbuddyDir as NSString).appendingPathComponent("hooks")
    }
    static var workbuddyScriptPath: String {
        (workbuddyHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var workbuddyHelperPath: String {
        (workbuddyHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: Claude Code（用户级 settings.json，Claude Code 事件方言）

    static var claudeDir: String { (home as NSString).appendingPathComponent(".claude") }
    static var claudeSettingsPath: String {
        (claudeDir as NSString).appendingPathComponent("settings.json")
    }
    static var claudeHooksDir: String { (claudeDir as NSString).appendingPathComponent("hooks") }
    static var claudeScriptPath: String {
        (claudeHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var claudeHelperPath: String {
        (claudeHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: Trae / Trae CN（用户级 hooks.json，Claude Code 同构）

    /// Trae（国际版）：`~/.trae/hooks.json`。
    static var traeDir: String { (home as NSString).appendingPathComponent(".trae") }
    /// Trae CN（国内版）：`~/.trae-cn/hooks.json`。
    static var traeCnDir: String { (home as NSString).appendingPathComponent(".trae-cn") }

    static func traeHooksConfigPath(_ dir: String) -> String {
        (dir as NSString).appendingPathComponent("hooks.json")
    }
    static func traeHooksDir(_ dir: String) -> String {
        (dir as NSString).appendingPathComponent("hooks")
    }
    static func traeScriptPath(_ dir: String) -> String {
        (traeHooksDir(dir) as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static func traeHelperPath(_ dir: String) -> String {
        (traeHooksDir(dir) as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: Kimi Code CLI（config.toml 的 `[[hooks]]` 数组）

    /// 新旧两个产品目录：Kimi Code CLI 用 `~/.kimi-code`，早期 kimi-cli 用 `~/.kimi`。
    /// 安装时优先写已存在的那个；都不存在才新建 `~/.kimi-code`。
    static var kimiCodeDir: String { (home as NSString).appendingPathComponent(".kimi-code") }
    static var kimiLegacyDir: String { (home as NSString).appendingPathComponent(".kimi") }

    static func kimiConfigPath(_ dir: String) -> String {
        (dir as NSString).appendingPathComponent("config.toml")
    }
    static func kimiHooksDir(_ dir: String) -> String {
        (dir as NSString).appendingPathComponent("hooks")
    }
    static func kimiScriptPath(_ dir: String) -> String {
        (kimiHooksDir(dir) as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static func kimiHelperPath(_ dir: String) -> String {
        (kimiHooksDir(dir) as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: Codex CLI（config.toml 的 notify 数组）

    static var codexDir: String { (home as NSString).appendingPathComponent(".codex") }
    static var codexConfigPath: String {
        (codexDir as NSString).appendingPathComponent("config.toml")
    }
    static var codexHooksDir: String { (codexDir as NSString).appendingPathComponent("hooks") }
    static var codexScriptPath: String {
        (codexHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var codexHelperPath: String {
        (codexHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }
    /// 生命周期 hook。和 `config.toml` 的 `notify` 不是同一个槽，两边可以并存。
    static var codexHooksConfigPath: String {
        (codexDir as NSString).appendingPathComponent("hooks.json")
    }

    // MARK: GitHub Copilot CLI（用户级 ~/.copilot/hooks/*.json）

    /// Copilot CLI 从 `~/.copilot/hooks/` 按文件名加载 hook。`COPILOT_HOME` 设了
    /// 就改读 `$COPILOT_HOME/hooks/`，否则用默认目录。
    static var copilotDir: String {
        if let home = ProcessInfo.processInfo.environment["COPILOT_HOME"], !home.isEmpty {
            return (home as NSString).expandingTildeInPath
        }
        return (self.home as NSString).appendingPathComponent(".copilot")
    }
    static var copilotHooksDir: String { (copilotDir as NSString).appendingPathComponent("hooks") }
    /// 整份文件归我们所有：别的 `*.json` 是用户或插件的，卸载时不能碰。
    static var copilotHooksConfigPath: String {
        (copilotHooksDir as NSString).appendingPathComponent("betterfocus.json")
    }
    static var copilotScriptPath: String {
        (copilotHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var copilotHelperPath: String {
        (copilotHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    // MARK: Qoder CN（与 Qoder 完全同构，只是根目录不同）

    static var qoderCnDir: String { (home as NSString).appendingPathComponent(".qoder-cn") }
    static var qoderCnSettingsPath: String {
        (qoderCnDir as NSString).appendingPathComponent("settings.json")
    }
    static var qoderCnHooksDir: String {
        (qoderCnDir as NSString).appendingPathComponent("hooks")
    }
    static var qoderCnScriptPath: String {
        (qoderCnHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh")
    }
    static var qoderCnHelperPath: String {
        (qoderCnHooksDir as NSString).appendingPathComponent("betterfocus-hook.py")
    }

    /// 宿主是否已在本机留下配置目录（自检时用于区分「未装宿主」与「未装集成」）。
    static func hostDirectoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// 宿主目录是不是一个**独立**安装，而不是指向另一个宿主的软链。
    ///
    /// 常见情形：`~/.qoder-cn` 被链到 `~/.qoder`，两个入口名指同一个安装。
    /// 这时不该认为「装了 CN 版」——否则 CN 安装器会把英文版的 hook 注册
    /// 改写成 CN 脚本（多一行 `BETTERFOCUS_VARIANT=cn`），此后英文版的每条
    /// 通知都被记成「Qoder CN」，同一个事件也会被注册两遍。
    static func hostDirectoryIsDistinct(_ path: String, from other: String) -> Bool {
        guard hostDirectoryExists(path) else { return false }
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
        else { return true }  // 不是软链 → 独立目录
        let sibling = (path as NSString).deletingLastPathComponent
        let resolved = (target as NSString).isAbsolutePath
            ? target
            : (sibling as NSString).appendingPathComponent(target)
        return (resolved as NSString).standardizingPath
            != (other as NSString).standardizingPath
    }

    // MARK: 超时参数

    /// 各宿主 todo 工具名的统一 matcher 正则（Claude Code 系 hook 的 matcher
    /// 是 JavaScript 正则，`|` 表示逻辑或）：
    ///   - 整表覆盖：TodoWrite / todo_write / todowrite / SetTodoList
    ///   - 单条写入：TaskCreate / TaskUpdate（V2 家族）
    /// 脚本按工具名分流到 todo_updated / todo_item_updated，这里只负责把它们
    /// 全接进来。
    static let todoToolMatcher = "TodoWrite|todo_write|todowrite|SetTodoList|TaskCreate|TaskUpdate"

    /// `Notification` 的 matcher 匹配 `notification_type`，不是工具名。
    /// 权限提醒、提问预览、待审阅、浏览器等待、MCP 追问、登录和额度失败都从这里进。
    static let attentionNotificationMatcher =
        "permission_prompt|ask_user_question|elicitation_dialog|elicitation_url_dialog|document_review|browser_interaction|agent_needs_input|auth_storage_failure|quota_"

    /// 卡片侧等待上限；Hook / Plugin 的轮询超时跟随它，确保卡片总是先于平台过期。
    /// Qoder 额外给脚本 +60s 缓冲，之后才杀死 hook。修改 `agentWaitLimit`
    /// （needs=reinstall）会重新运行安装器，用这些值重新生成 hook。
    static var questionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var permissionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var hookTimeoutSeconds: Int { Settings.shared.agentWaitLimit + 60 }
}
