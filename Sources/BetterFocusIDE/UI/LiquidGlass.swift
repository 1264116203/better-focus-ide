// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 液态玻璃（Liquid Glass，macOS 26）的门控入口占位。
///
/// ## 背景
///
/// Apple 在 macOS 26（Xcode 26 / SDK macOS 26.0）引入原生 Liquid Glass：
/// - SwiftUI：`.glassEffect(_:in:)`、`.glassEffect(.regular.interactive())`、
///   `.buttonStyle(.glass)` / `.glassProminent`、`.backgroundExtensionEffect()`
/// - AppKit：`NSGlassEffectView` / `NSGlassEffectContainerView`
///
/// 本项目当前构建环境是 **Xcode 16.4 / macOS SDK 15.5**，上述符号在编译期尚不存在，
/// 直接引用会编译失败。故**不在旧系统上模拟该效果**，只保留门控占位，等升级
/// Xcode 26 后在此接入真 API。
///
/// ## 接入方式（升级 Xcode 26 后）
///
/// 在卡片外壳（`NotchCanvas.makeGlass()`）与各卡片控件的修饰符处，用
/// `#available(macOS 26, *)` 分支调用对应真 API，其余无需改动：
/// ```swift
/// // 面板
/// self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
/// // 控件
/// self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
/// // 按钮
/// self.buttonStyle(.glassProminent)   // 或 .glass
/// // 背景延伸
/// self.backgroundExtensionEffect()
/// ```
enum LiquidGlass {
    /// 当前运行系统是否支持原生 Liquid Glass（macOS 26+）。
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}
