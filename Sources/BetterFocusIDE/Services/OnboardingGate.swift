// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 首次成功启动后的引导是否还要出现。
///
/// 记在 UserDefaults 里，不进 settings.json，避免「恢复默认设置」把引导再弹一次。
enum OnboardingGate {
    static let windowTitle = "欢迎使用 BetterFocusIDE"
    static let defaultsKey = "BetterFocusIDE.didCompleteOnboarding"

    /// 引导页。最后一页是 hook 安装。
    enum Page: Int, CaseIterable {
        case welcome
        case features
        case notes
        case install
    }

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: defaultsKey)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }
}
