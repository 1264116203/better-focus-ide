// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 通过 Socket 发送事件的编码智能体提供方。
///
/// 每个值对应 hook 侧 `_identify_product()` 决策树的一种输出：
/// - `qoder`：独立 Qoder（QODER_STANDALONE=1）
/// - `opencode`：OpenCode JS 插件
/// - `jetbrains_plugin`：JetBrains IDE 内的 Qoder 插件
/// - `qoder_ide`：Qoder IDE（通义灵码）
/// - `qoder_cli`：终端 CLI 模式（无头脚本）
/// - `unknown`：无法识别
enum AgentProvider: String, CaseIterable, Codable {
    case qoder
    case opencode
    case jetbrains_plugin
    case qoder_ide
    case qoder_cli
    case unknown

    /// 界面展示名称（用于徽章首字母、来源文案等）。
    var displayName: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
        case .jetbrains_plugin: return "JetBrains"
        case .qoder_ide: return "Qoder"
        case .qoder_cli: return "Qoder CLI"
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
        case .unknown:
            return (red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    /// 归组到 IDE 跳转用的提供方键（`qoder` / `opencode`）。
    ///
    /// `IDELauncher.ideBundles` 按大类索引，产品细分值需映射回组键才能查到
    /// 对应的 bundle id 列表。
    var providerGroup: String {
        switch self {
        case .opencode: return "opencode"
        case .qoder, .jetbrains_plugin, .qoder_ide, .qoder_cli, .unknown:
            return "qoder"
        }
    }
}
