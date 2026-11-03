// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 通过 Socket 发送事件的编码智能体提供方。
///
/// 目前支持两个来源：Qoder（Python hook）与 OpenCode（JS plugin）。
/// 每个提供方有独立的展示名与主题色，主题色实时读取自 Settings。
enum AgentProvider: String, CaseIterable, Codable {
    case qoder
    case opencode

    /// 界面展示名称（用于徽章首字母、来源文案等）。
    var displayName: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
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
        case .qoder:
            let c = Settings.shared.qoderTintRGB
            return (c.r, c.g, c.b)
        case .opencode:
            let c = Settings.shared.opencodeTintRGB
            return (c.r, c.g, c.b)
        }
    }
}
