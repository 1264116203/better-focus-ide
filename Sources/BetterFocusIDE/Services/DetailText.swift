// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import CoreGraphics

/// 卡片详情的折叠与展开。
///
/// 放不下的正文默认只留有限几行，末尾省略；展开后按全文行数加高，
/// 最多铺开 `expandedLineCap` 行，再长的部分在这块区域里滚动。
enum DetailText {
    /// 折叠行数。`showAll` 不折叠，给还没接这套开关的高度计算用。
    struct Style: Equatable {
        var expanded: Bool
        var bodyCollapsedLines: Int
        var descriptionCollapsedLines: Int

        static let showAll = Style(expanded: true,
                                   bodyCollapsedLines: .max,
                                   descriptionCollapsedLines: .max)

        static func question(expanded: Bool) -> Style {
            Style(expanded: expanded, bodyCollapsedLines: 2, descriptionCollapsedLines: 2)
        }
    }

    /// 展开后单块详情最多铺开的行数，避免一条超长命令把岛拉出屏幕。
    static let expandedLineCap = 12

    struct Measure {
        /// 正文本身的高度。
        var textHeight: CGFloat
        /// 实际画出来的行数。
        var shownLines: Int
        /// 全文比折叠行数长。点这段文字展开，再点一次收回。
        var showsControl: Bool
        /// 展开后仍超过行数上限，正文区域内部滚动。
        var scrolls: Bool
    }

    /// 按已经量好的全文高度决定折叠行数，以及点文字能否展开。
    static func measure(fullHeight: CGFloat, font: CGFloat,
                        collapsedLines: Int, expanded: Bool) -> Measure {
        let line = max(font * 1.3, 1)
        let fullLines = max(1, Int((fullHeight / line).rounded()))
        let showsControl = collapsedLines < .max && fullLines > max(collapsedLines, 1)
        let shown: Int
        if !showsControl {
            shown = fullLines
        } else if expanded {
            shown = min(fullLines, expandedLineCap)
        } else {
            shown = max(collapsedLines, 1)
        }
        return Measure(textHeight: CGFloat(shown) * line,
                       shownLines: shown,
                       showsControl: showsControl,
                       scrolls: expanded && fullLines > expandedLineCap)
    }

    /// 用 `QuestionCardLayout` 的折行规则量一段文字。
    static func measure(_ text: String, width: CGFloat, font: CGFloat,
                        collapsedLines: Int, expanded: Bool) -> Measure {
        let full = QuestionCardLayout.textHeight(text, width: width, font: font)
        return measure(fullHeight: full, font: font,
                       collapsedLines: collapsedLines, expanded: expanded)
    }
}
