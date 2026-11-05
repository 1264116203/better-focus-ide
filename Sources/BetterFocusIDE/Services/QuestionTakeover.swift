// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 「这次提问要不要接到灵动岛上」的判定。
///
/// 有些宿主（WorkBuddy IDE、GPT 类 IDE 面板）在模型发起 `AskUserQuestion` 的**那一刻**
/// 就把自己的提问面板画出来了，不等 `PreToolUse` hook 返回。于是同一道题会出现两份：
/// IDE 里一份、岛上再一份，用户得答两次，而且第一次的选择会被 hook 的 deny 丢掉。
///
/// 判定规则：**GUI 宿主正在前台 → 让位**。用户眼前就是宿主自己的面板，岛上再弹一份
/// 纯属添乱；用户不在宿主前面时（在浏览器、在别的 App），岛才是那个更好的入口。
///
/// 三条例外：
/// - 终端宿主：原生提问是一行行 TUI 表单，岛上卡片明显更好，且 hook 的 deny 会**先于**
///   工具执行生效，终端那边根本不会出现第二份 → 照常接管。
/// - 浏览器会话（`opencode serve` + Web UI）：没有可对照的应用窗口，照常接管。
/// - 宿主身份未知：无从判断，保持旧行为照常接管。
enum QuestionTakeover {
    /// 是否把提问接管到灵动岛。
    ///
    /// - Parameters:
    ///   - host: 事件里带的宿主信息（可能为空）。
    ///   - frontmostBundle: 当前前台应用的 bundle id，取不到时传 nil。
    static func shouldTakeOver(host: HostInfo?, frontmostBundle: String?) -> Bool {
        guard let host, !host.bundle.isEmpty else { return true }
        if TerminalHost.isTerminal(bundle: host.bundle, name: host.name) { return true }
        if !host.url.isEmpty { return true }
        guard let frontmost = frontmostBundle, !frontmost.isEmpty else { return true }
        return frontmost != host.bundle
    }

    /// 当前前台应用的 bundle id（取不到返回 nil）。
    ///
    /// 刘海窗口是 `.nonactivatingPanel`，点击不会抢焦点，所以这个值始终是用户
    /// 真正在用的那个 App。
    static func frontmostBundle() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
