// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// The coding agents that send events via Socket.
enum AgentProvider: String, CaseIterable, Codable {
    case qoder
    case opencode

    var displayName: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
        }
    }

    /// Theme tint color for the provider badge (live from Settings).
    var tint: Color {
        let c = tintRGB
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// Raw RGB components, for contexts that can't use SwiftUI `Color`
    /// (history entries stored before the view layer, AppKit drawing).
    /// Reads Settings at call time so qoder_tint / opencode_tint edits apply live.
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
