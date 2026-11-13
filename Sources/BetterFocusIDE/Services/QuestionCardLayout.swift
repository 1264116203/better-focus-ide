// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 提问卡片的高度计算（纯函数，便于单测）。
///
/// **必须与 `NotchAgentQuestionView` 的视图结构逐段对齐**——这里漏算任何一段，
/// 底部内容（尤其是「发送」按钮）都会被窗口裁掉。视图结构（外层 VStack spacing: 8）：
///
/// ```
/// padding(.vertical, 10)                     20
/// header（徽章 badgeSize 为行内最高）        30
/// [项目名 9pt 单行]                          8 + 11.7
/// [正文 bodyFont 可换行]                     8 + 行数 × (font × 1.3)
/// VStack(spacing: 6) { 选项…; 其他… }        8 + Σ各行高 + 选项数 × 6
/// 发送按钮                                  8 + 26
/// ```
///
/// 之所以抽成纯函数：这个「高度算少了」的 bug 已经复发过两次，用单测把逐段结构锁住。
enum QuestionCardLayout {

    /// 视图侧度量。生产环境由 `NotchLayout` / `Settings` 填充，测试可传固定值。
    struct Metrics {
        var cardWidth: CGFloat
        var cardInset: CGFloat
        var badgeSize: CGFloat
        var bodyFont: CGFloat
        var optionFont: CGFloat
        var descFont: CGFloat
        var optionRowMin: CGFloat
        var sendHeight: CGFloat
        var minHeight: CGFloat
        /// 项目名行字号
        var projectFont: CGFloat = 9
    }

    /// 外层 `.padding(.vertical, 10)` 合计。
    static let outerVerticalPadding: CGFloat = 20
    /// 段落之间的 `VStack(spacing: 8)`。
    static let sectionSpacing: CGFloat = 8
    /// 选项区内部的 `VStack(spacing: 6)`。
    static let rowSpacing: CGFloat = 6
    /// 选项行 / 其他行的上下 `.padding(.vertical, 7)` 合计。
    static let rowVerticalPadding: CGFloat = 14
    /// 行内可用文本宽的扣减：图标列 16 + 图标与文本间距 8 + 行内水平 padding 9×2。
    static let rowTextInset: CGFloat = 16 + 8 + 18
    /// 「其他…」行的标签文本。
    static let otherLabel = "其他…"

    /// 计算卡片内容高度（不含 `safeContentTop`）。
    ///
    /// - Parameters:
    ///   - question: 当前展示的问题；`nil` 时只算「内边距 + 头部」的骨架高度。
    ///   - hasProject: 是否有项目名行（视图里由 `host.cwd` 末级目录名决定）。
    ///   - detail: 正文和选项说明的折叠行数。默认不折叠，既有高度测试保持原值。
    static func contentHeight(question: AgentQuestion?,
                              hasProject: Bool,
                              metrics: Metrics,
                              detail: DetailText.Style = .showAll) -> CGFloat {
        let textW = max(80, metrics.cardWidth - metrics.cardInset * 2)

        var height = outerVerticalPadding + metrics.badgeSize

        guard let question else {
            return max(height, metrics.minHeight)
        }

        if hasProject {
            height += sectionSpacing + ceil(metrics.projectFont * 1.3)
        }

        if !question.question.isEmpty {
            let body = DetailText.measure(question.question, width: textW,
                                          font: metrics.bodyFont,
                                          collapsedLines: detail.bodyCollapsedLines,
                                          expanded: detail.expanded)
            height += sectionSpacing + body.textHeight
        }

        let optionTextW = max(40, textW - rowTextInset)
        var rowsH: CGFloat = 0
        for option in question.options {
            let labelH = textHeight(option.label, width: optionTextW, font: metrics.optionFont)
            let descH = option.description.isEmpty
                ? 0
                : DetailText.measure(option.description, width: optionTextW,
                                     font: metrics.descFont,
                                     collapsedLines: detail.descriptionCollapsedLines,
                                     expanded: detail.expanded).textHeight
            // label 与 description 之间 `VStack(spacing: 1)`。
            rowsH += max(metrics.optionRowMin,
                         rowVerticalPadding + labelH + (descH > 0 ? 1 + descH : 0))
        }
        // 「其他…」行：与选项同款内边距，单行。
        rowsH += max(metrics.optionRowMin,
                     rowVerticalPadding + textHeight(otherLabel, width: optionTextW,
                                                     font: metrics.optionFont))
        // 间隔数 = 行数 - 1 = (选项数 + 1) - 1 = 选项数
        rowsH += rowSpacing * CGFloat(question.options.count)
        height += sectionSpacing + rowsH

        height += sectionSpacing + metrics.sendHeight
        return max(height, metrics.minHeight)
    }

    /// 精确文本高度：按字符类型累计宽度（全角 ≈ 1.0×font，半角 ≈ 0.55×font），
    /// 逐字符折行后乘以行高（font × 1.3）。
    static func textHeight(_ text: String, width: CGFloat, font: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return font * 1.3 }
        let lineHeight = font * 1.3
        var lineWidth: CGFloat = 0
        var lines: CGFloat = 1
        for ch in text {
            if ch == "\n" || ch == "\r" {
                lines += 1
                lineWidth = 0
                continue
            }
            let w: CGFloat = isFullWidth(ch) ? font : font * 0.55
            if lineWidth + w > width {
                lines += 1
                lineWidth = w
            } else {
                lineWidth += w
            }
        }
        return lines * lineHeight
    }

    /// 粗略判断全角字符：CJK 统一表意文字、中文标点、全角字符区。
    private static func isFullWidth(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { s in
            let v = s.value
            return (v >= 0x2E80 && v <= 0x9FFF)      // CJK 部首扩展 ~ 统一表意文字
                || (v >= 0xF900 && v <= 0xFAFF)      // CJK 兼容表意文字
                || (v >= 0xFE30 && v <= 0xFE4F)      // CJK 兼容形式
                || (v >= 0xFF00 && v <= 0xFF60)      // 全角 ASCII / 全角标点
                || (v >= 0xFFE0 && v <= 0xFFE6)
        }
    }
}
