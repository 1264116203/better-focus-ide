// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI

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
