// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 终端宿主识别。
///
/// CLI 类产品（Claude Code / Codex / Kimi / Qoder CLI / Qoder CN CLI）本身没有窗口，
/// 它们跑在某个终端里。hook 顺父进程走查找到的最外层 `.app` 就是那个终端
/// （Warp / iTerm / Terminal / Ghostty…），所以：
///
/// - **图标**用终端的（`IDEIconProvider` 按 host.name 命中 warp / iterm 图标）；
/// - **跳转**激活终端应用窗口，而不是去猜一个不存在的 IDE 窗口；
/// - **名称**标成「产品（终端）」，例如 `Qoder CLI（Warp）`——只看名字
///   分不清是哪个终端里的会话，加上括号里的宿主才不用猜。
enum TerminalHost {
    /// bundle ID → 展示名。展示名同时用于括号标注与图标匹配的输入。
    static let bundles: [String: String] = [
        "dev.warp.Warp-Stable": "Warp",
        "com.googlecode.iterm2": "iTerm",
        "com.apple.Terminal": "Terminal",
        "com.mitchellh.ghostty": "Ghostty",
        "net.kovidgoyal.kitty": "Kitty",
        "org.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        "com.microsoft.VSCode": "VS Code",
        "com.visualstudio.code": "VS Code",
    ]

    /// 名称侧的同义词表：`CFBundleName` 常与品牌名不同（iTerm2 / Terminal…），
    /// 用「包含即命中」的宽松匹配，匹配顺序按 key 长度降序。
    static let names: [(key: String, display: String)] = [
        ("warp", "Warp"),
        ("iterm", "iTerm"),
        ("terminal", "Terminal"),
        ("ghostty", "Ghostty"),
        ("kitty", "Kitty"),
        ("alacritty", "Alacritty"),
        ("wezterm", "WezTerm"),
        ("visual studio code", "VS Code"),
        ("vscode", "VS Code"),
    ]

    /// 终端应用名（用于括号标注）；bundle 优先，缺失时退回名称匹配。
    static func displayName(bundle: String?, name: String?) -> String? {
        if let bundle, let hit = bundles[bundle] { return hit }
        guard let lowered = name?.lowercased(), !lowered.isEmpty else { return nil }
        for entry in names.sorted(by: { $0.key.count > $1.key.count }) where lowered.contains(entry.key) {
            return entry.display
        }
        return nil
    }

    /// 是否是终端宿主。
    static func isTerminal(bundle: String?, name: String?) -> Bool {
        displayName(bundle: bundle, name: name) != nil
    }
}
