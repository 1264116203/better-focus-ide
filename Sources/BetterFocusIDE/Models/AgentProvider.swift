// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 通过 Socket 发送事件的编码智能体提供方。
///
/// 每个值对应 hook 侧 `_identify_product()` 决策树的一种输出，或新宿主自身的
/// provider 标识：
/// - `qoder`：独立 Qoder（QODER_STANDALONE=1）
/// - `opencode`：OpenCode JS 插件
/// - `jetbrains_plugin`：JetBrains IDE 内的 Qoder 插件
/// - `qoder_ide`：Qoder IDE（通义灵码）
/// - `qoder_cli`：终端 CLI 模式（无头脚本）
/// - `cursor`：Cursor 用户级 hooks（`~/.cursor/hooks.json`）
/// - `workbuddy`：WorkBuddy 用户级 hooks（`~/.workbuddy/settings.json`）
/// - `unknown`：无法识别
enum AgentProvider: String, CaseIterable, Codable {
    case qoder
    case opencode
    case jetbrains_plugin
    case qoder_ide
    case qoder_cli
    case cursor
    case workbuddy
    case unknown

    /// 界面展示名称（用于徽章首字母、来源文案等）。
    ///
    /// 注意：JetBrains 插件模式返回空字符串，强制使用 host.name（具体 IDE 名称如
    /// "IntelliJ IDEA"、"PyCharm"）；其他提供方返回各自的展示名。
    var displayName: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
        case .jetbrains_plugin: return ""  // 必须由 host.name 提供具体 IDE 名称
        case .qoder_ide: return "Qoder"
        case .qoder_cli: return "Qoder CLI"
        case .cursor: return "Cursor"
        case .workbuddy: return "WorkBuddy"
        case .unknown: return "Unknown"
        }
    }

    /// 提供方的主题色（用于徽章着色，实时取自 Settings）。
    var tint: Color {
        let c = tintRGB
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// 原始 RGB 分量。
    ///
    /// 供无法使用 SwiftUI `Color` 的场景（视图层之前存储的历史条目、
    /// AppKit 绘制）使用。在调用时读取 Settings，因此 qoder_tint /
    /// opencode_tint 的修改可实时生效。
    var tintRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .qoder, .jetbrains_plugin, .qoder_ide, .qoder_cli:
            let c = Settings.shared.qoderTintRGB
            return (c.r, c.g, c.b)
        case .opencode:
            let c = Settings.shared.opencodeTintRGB
            return (c.r, c.g, c.b)
        case .cursor:
            let c = Settings.shared.cursorTintRGB
            return (c.r, c.g, c.b)
        case .workbuddy:
            let c = Settings.shared.workbuddyTintRGB
            return (c.r, c.g, c.b)
        case .unknown:
            return (red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    /// 归组到 IDE 跳转用的提供方键（`qoder` / `opencode` / `cursor` / `workbuddy`）。
    ///
    /// `IDELauncher.ideBundles` 按大类索引，产品细分值需映射回组键才能查到
    /// 对应的 bundle id 列表。
    var providerGroup: String {
        switch self {
        case .opencode: return "opencode"
        case .cursor: return "cursor"
        case .workbuddy: return "workbuddy"
        case .qoder, .jetbrains_plugin, .qoder_ide, .qoder_cli, .unknown:
            return "qoder"
        }
    }

    /// 获取有效的展示名称：优先使用 host.name（具体 IDE 名称），回退到 displayName。
    ///
    /// 对于 JetBrains 插件模式，displayName 为空，必须依赖 host.name 提供具体名称
    /// （如 "IntelliJ IDEA"、"PyCharm"）。如果 host.name 也为空，返回 "JetBrains"
    /// 作为最终兜底。
    static func effectiveName(provider: AgentProvider, hostName: String?) -> String {
        // 优先使用 host.name（具体 IDE 名称）
        if let name = hostName, !name.isEmpty {
            return name
        }
        // 回退到 provider.displayName
        let displayName = provider.displayName
        if !displayName.isEmpty {
            return displayName
        }
        // JetBrains 插件模式且 host.name 缺失：最终兜底
        if provider == .jetbrains_plugin {
            return "JetBrains"
        }
        return "Unknown"
    }

    /// 获取徽章文本：取有效展示名称的首字母大写。
    static func badgeText(provider: AgentProvider, hostName: String?) -> String {
        let name = effectiveName(provider: provider, hostName: hostName)
        return String(name.prefix(1)).uppercased()
    }
}
