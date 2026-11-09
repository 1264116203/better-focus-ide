// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// 状态栏图标：与 app 图标同构的「刘海里滑出一张便签」，仅保留线条轮廓。
///
/// 之所以用代码绘制而不是位图：
/// - 菜单栏图标必须是 **template image**，由系统按菜单栏明暗自动着色。位图带颜色
///   在深色菜单栏下会发灰，纯黑 + isTemplate 才能两者都清晰。
/// - 18pt 的显示尺寸在不同缩放/外接屏下 backing scale 不同，矢量绘制按需光栅化，
///   比预渲染的 @1x/@2x 位图更锐利。
///
/// 造型取自选定的 app 图标（沙色底 + 黑刘海 + 米白便签）：上方一枚胶囊代表刘海，
/// 下方一张圆角便签，中间留 1.4pt 缝隙避免两条轮廓在 18pt 下糊成一块；便签中央
/// 一颗实心点代表「有一条通知」。
enum StatusBarIcon {

    /// 生成状态栏图标。
    ///
    /// - Parameter style: `notch` 用自绘刘海；其余取同名 SF Symbol。认不出时回退刘海。
    /// - Parameter size: 画布边长（pt）。菜单栏惯用 18pt。
    static func make(style: String = "notch", size: CGFloat = 18) -> NSImage {
        if style != "notch", let symbol = symbol(style, size: size) {
            return symbol
        }
        return notch(size: size)
    }

    /// 菜单栏用的模板符号。点尺寸略小于画布，避免贴边被裁。
    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        let symbolName: String
        switch name {
        case "bell": symbolName = "bell"
        case "sparkle": symbolName = "sparkle"
        case "circle": symbolName = "circle.fill"
        default: return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.78, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BetterFocusIDE")?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = true
        return image
    }

    /// 自绘刘海 + 便签。
    private static func notch(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let s = rect.width
            let lineWidth = max(1.2, s * 0.075)

            // 上方：刘海胶囊——压扁拉宽，贴合真实刘海的宽薄比例
            let notchHeight = s * 0.155
            let notchRect = NSRect(x: s * 0.07,
                                   y: s * 0.71,
                                   width: s * 0.86,
                                   height: notchHeight)
            let notch = NSBezierPath(roundedRect: notchRect,
                                     xRadius: notchHeight / 2,
                                     yRadius: notchHeight / 2)
            notch.lineWidth = lineWidth
            notch.stroke()

            // 下方：滑出的便签（与刘海间留 2.7pt 呼吸缝）
            let cardRect = NSRect(x: s * 0.20,
                                  y: s * 0.12,
                                  width: s * 0.60,
                                  height: s * 0.43)
            let card = NSBezierPath(roundedRect: cardRect,
                                    xRadius: s * 0.105,
                                    yRadius: s * 0.105)
            card.lineWidth = lineWidth
            card.stroke()

            // 便签中央的通知点
            let dotRadius = s * 0.058
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.midX - dotRadius,
                                                  y: cardRect.midY - dotRadius,
                                                  width: dotRadius * 2,
                                                  height: dotRadius * 2))
            dot.fill()

            return true
        }
        // 模板图：系统按菜单栏明暗自适应（深色菜单栏自动反白）。
        image.isTemplate = true
        image.accessibilityDescription = "BetterFocusIDE"
        return image
    }
}
