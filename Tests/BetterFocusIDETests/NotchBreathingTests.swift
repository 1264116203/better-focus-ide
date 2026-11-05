// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import XCTest
@testable import BetterFocusIDE

/// 呼吸灯的显示时机。
///
/// 呼吸灯是「你错过了一条通知」的提示，不是装饰：只有通知卡片**未被查看就自动收起**
/// （`hasUnprocessedNotice`）时才亮，其余时刻一律熄灭。这里把这条规则锁住，
/// 防止调试期「常亮验证渲染」的写法被遗留到正式逻辑里。
final class NotchBreathingTests: XCTestCase {

    /// 未读标记为 false 时，任何主题色都不该点亮呼吸灯。
    func testGlowOffWhenNoUnreadNotice() {
        XCTAssertNil(NotchService.glowColor(hasUnprocessedNotice: false, noticeTint: .pink))
        XCTAssertNil(NotchService.glowColor(hasUnprocessedNotice: false, noticeTint: nil))
    }

    /// 未读标记为 true 时亮，且用那条通知的提供方主题色。
    func testGlowUsesNoticeTint() {
        guard let color = NotchService.glowColor(hasUnprocessedNotice: true,
                                                 noticeTint: .pink) else {
            return XCTFail("有未读通知时应当点亮呼吸灯")
        }
        let rgb = components(of: color)
        let pink = components(of: .pink)
        XCTAssertEqual(rgb.r, pink.r, accuracy: 0.01)
        XCTAssertEqual(rgb.g, pink.g, accuracy: 0.01)
        XCTAssertEqual(rgb.b, pink.b, accuracy: 0.01)
    }

    /// 主题色缺失（提供方认不出）时退回强调色，而不是「保持上一次的颜色」——
    /// 否则会出现「通知已读、状态已清，灯却还亮着」的错觉。
    func testGlowFallsBackToAccentWhenTintMissing() {
        guard let color = NotchService.glowColor(hasUnprocessedNotice: true,
                                                 noticeTint: nil) else {
            return XCTFail("有未读通知但缺主题色时，应当用强调色兜底点亮")
        }
        let rgb = components(of: color)
        let accent = NotchLayout.accentColor
        XCTAssertEqual(rgb.r, accent.r, accuracy: 0.01)
        XCTAssertEqual(rgb.g, accent.g, accuracy: 0.01)
        XCTAssertEqual(rgb.b, accent.b, accuracy: 0.01)
    }

    // MARK: - 工具

    private func components(of color: Color) -> (r: Double, g: Double, b: Double) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return (-1, -1, -1)
        }
        return (Double(srgb.redComponent),
                Double(srgb.greenComponent),
                Double(srgb.blueComponent))
    }
}
