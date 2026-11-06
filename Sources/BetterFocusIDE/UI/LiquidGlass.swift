// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 液态玻璃（Liquid Glass，macOS 26+）在卡片控件上的统一入口。
///
/// 岛面轮廓的折光在 `NotchView` 里用 `glassEffect(in: NotchShape)` 绘制，
/// 并且落定后不能再被祖先遮罩裁切。这里只负责岛内的控件。
/// macOS 26 以下没有这些符号，回退到原来的半透明填色。
enum LiquidGlassVariant {
    /// 标准玻璃，控件和可点行用它。
    case regular
    /// 更透的玻璃，叠在岛面玻璃上的被动槽（详情、计数徽章）用它，避免两层磨砂糊成一块。
    case clear

    /// 设置里的「控件样式」优先；认不出时用调用处给的样式。
    static func configured(fallback: LiquidGlassVariant) -> LiquidGlassVariant {
        switch Settings.shared.glassControlStyle {
        case "regular": return .regular
        case "clear": return .clear
        default: return fallback
        }
    }
}

enum LiquidGlassShape {
    case rounded(CGFloat)
    case capsule
    case circle
}

private struct LiquidGlassPlate: ViewModifier {
    var shape: LiquidGlassShape
    var variant: LiquidGlassVariant
    var tint: Color?
    var interactive: Bool
    var fallback: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            glassed(content)
        } else {
            legacy(content)
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private func glassed(_ content: Content) -> some View {
        let style = LiquidGlassVariant.configured(fallback: variant)
        let glass = Self.glass(variant: style, tint: tint, interactive: interactive)
        switch shape {
        case .rounded(let radius):
            content.glassEffect(glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            content.glassEffect(glass, in: Capsule(style: .continuous))
        case .circle:
            content.glassEffect(glass, in: Circle())
        }
    }

    @ViewBuilder
    private func legacy(_ content: Content) -> some View {
        switch shape {
        case .rounded(let radius):
            content.background(fallback, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            content.background(fallback, in: Capsule(style: .continuous))
        case .circle:
            content.background(fallback, in: Circle())
        }
    }

    @available(macOS 26, *)
    private static func glass(variant: LiquidGlassVariant, tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = variant == .clear ? .clear : .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

/// 把一张卡片里的多块玻璃收成一次绘制。间距 0 只做合批，不把相邻选项行融成一块。
private struct LiquidGlassGroup: ViewModifier {
    var spacing: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    /// 给控件铺一层液态玻璃。`fallback` 是 macOS 26 以下的原有填色。
    func liquidGlass(
        _ shape: LiquidGlassShape,
        variant: LiquidGlassVariant = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: Color
    ) -> some View {
        modifier(LiquidGlassPlate(shape: shape, variant: variant, tint: tint,
                                   interactive: interactive, fallback: fallback))
    }

    /// 包住一张卡片的全部玻璃控件。
    func liquidGlassGroup(spacing: CGFloat = 0) -> some View {
        modifier(LiquidGlassGroup(spacing: spacing))
    }
}
