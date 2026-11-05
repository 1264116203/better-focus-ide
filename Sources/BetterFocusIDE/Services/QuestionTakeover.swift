// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 「这次提问要不要接到灵动岛上」的判定。
///
/// ## 为什么默认一律接管
///
/// 有些宿主（WorkBuddy IDE 等）在模型发起 `AskUserQuestion` 的**那一刻**就把自己的
/// 问卷面板画出来了，不等 `PreToolUse` 返回。看上去「让位给宿主」更合理，但实测下来
/// 不行——面板是宿主自己画的，hook **没有任何手段阻止它出现**；让位的唯一结果就是
/// 岛上什么都不弹，而用户在 IDE 里作答的那一次选择同样会被 hook 的 deny 丢掉。
///
/// 所以策略定为**岛优先**：岛一定弹卡，工具被 deny 改写，答案以岛为准。宿主那份
/// 面板会在工具结果回来后自行收起，属于「看得见但不算数」的残影。
///
/// `deferToHostWhenFrontmost` 保留给未来的可选策略（比如某宿主原生面板体验确实更好，
/// 或做成设置项），但默认不启用：启用前请先确认该宿主的面板能在 hook 之前独立完成
/// 作答，否则只会把问题晾在超时上。
enum QuestionTakeover {
    /// 接管策略。
    enum Policy {
        /// 一律接管（默认）：岛是唯一有效入口。
        case alwaysIsland
        /// 宿主自带面板且正在前台 → 让位（需逐个宿主实测后再启用）。
        case deferToHostWhenFrontmost
    }

    /// 是否把提问接管到灵动岛。
    ///
    /// - Parameters:
    ///   - host: 事件里带的宿主信息（可能为空）。
    ///   - frontmostBundle: 当前前台应用的 bundle id，取不到时传 nil。
    ///   - policy: 接管策略，默认 `alwaysIsland`。
    static func shouldTakeOver(host: HostInfo?, frontmostBundle: String?,
                               policy: Policy = .alwaysIsland) -> Bool {
        switch policy {
        case .alwaysIsland:
            return true
        case .deferToHostWhenFrontmost:
            // 终端宿主的原生提问是一行行 TUI 表单，且 deny 先于工具执行生效，
            // 终端那边根本不会出现第二份 → 照常接管。
            guard let host, !host.bundle.isEmpty else { return true }
            if TerminalHost.isTerminal(bundle: host.bundle, name: host.name) { return true }
            // 浏览器会话（`opencode serve` + Web UI）没有可对照的应用窗口。
            if !host.url.isEmpty { return true }
            guard let frontmost = frontmostBundle, !frontmost.isEmpty else { return true }
            return frontmost != host.bundle
        }
    }

    /// 当前前台应用的 bundle id（取不到返回 nil）。
    ///
    /// 刘海窗口是 `.nonactivatingPanel`，点击不会抢焦点，所以这个值始终是用户
    /// 真正在用的那个 App。
    static func frontmostBundle() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
