// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI

/// 详情被省略时出现的小按钮：展开全文，或把卡片收回默认行数。
struct DetailDisclosure: View {
    var expanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(expanded ? "收起" : "展开")
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 7)
            .frame(height: DetailText.controlHeight)
            // 交互玻璃只把文字算进命中区，箭头和左右留白会点穿到卡片。
            // 盖一层同形的点击面，整颗胶囊都交给这个按钮。
            .liquidGlass(.capsule, variant: .clear, interactive: false,
                         fallback: Color.white.opacity(0.12))
            .overlay {
                Capsule().fill(Color.white.opacity(0.001))
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .help(expanded ? "收起详情" : "展开详情")
        .accessibilityLabel(expanded ? "收起详情" : "展开详情")
    }
}

/// 按折叠状态显示一段详情。超长时在上限内滚动，高度与 `DetailText.measure` 一致。
///
/// `onToggle` 有值时，这段文字自己承担展开 / 收起，不再另放一枚按钮。
/// 滚动区域内用轻点，拖动仍交给滚动视图。
struct DetailTextBlock: View {
    let text: String
    let fontSize: CGFloat
    var monospaced = false
    var color: Color = .white.opacity(0.92)
    var collapsedLines: Int
    var expanded: Bool
    var measure: DetailText.Measure
    var onToggle: (() -> Void)? = nil
    @State private var handCursor = false

    var body: some View {
        let content = textBody
        if let onToggle {
            tappable(content, action: onToggle)
        } else {
            content
        }
    }

    private var textBody: some View {
        let font: Font = monospaced
            ? .system(size: fontSize, design: .monospaced)
            : .system(size: fontSize)
        let limited = Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(measure.scrolls ? nil : measure.shownLines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if measure.scrolls {
                ScrollView {
                    limited
                }
                .frame(height: measure.textHeight)
            } else {
                limited
            }
        }
    }

    private func tappable<V: View>(_ content: V, action: @escaping () -> Void) -> some View {
        let label = expanded ? "收起详情" : "展开详情"
        let shaped = content
            .contentShape(Rectangle())
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .onHover { inside in
                if inside, !handCursor {
                    NSCursor.pointingHand.push()
                    handCursor = true
                } else if !inside, handCursor {
                    NSCursor.pop()
                    handCursor = false
                }
            }
            .onDisappear {
                if handCursor {
                    NSCursor.pop()
                    handCursor = false
                }
            }
        return Group {
            if measure.scrolls {
                shaped.simultaneousGesture(TapGesture().onEnded { action() })
            } else {
                Button(action: action) { shaped }
                    .buttonStyle(.plain)
            }
        }
    }
}
