// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// `QuestionCardLayout.contentHeight` 的回归测试。
///
/// 背景：「提问卡片底部内容（发送按钮）被裁掉」的问题复发过两次，
/// 根因都是高度公式漏算了某一段（项目名行、徽章实际尺寸、选项行间距）。
/// 这里用手工推导的期望值把逐段结构锁死——改视图结构时必须同步改这里。
final class QuestionCardLayoutTests: XCTestCase {

    /// 固定的度量值：便于手算期望，不依赖本机设置。
    private let metrics = QuestionCardLayout.Metrics(
        cardWidth: 560,
        cardInset: 32,
        badgeSize: 30,
        bodyFont: 12,
        optionFont: 12,
        descFont: 10.5,
        optionRowMin: 30,
        sendHeight: 26,
        minHeight: 0)

    /// 短文本 → 单行。文字宽 12×1.3=15.6 / 10.5×1.3=13.65。
    private func oneLineH(_ font: CGFloat) -> CGFloat { font * 1.3 }

    /// 项目名行高：实现里对 9pt 行高向上取整（ceil(11.7) = 12），避免亚像素裁切。
    private var projectRowH: CGFloat { (9 * 1.3).rounded(.up) }

    // MARK: - 骨架

    /// 无问题数据时，高度 = 上下内边距 + 头部徽章。
    func testSkeletonHeightWithoutQuestion() {
        let h = QuestionCardLayout.contentHeight(question: nil, hasProject: false,
                                                 metrics: metrics)
        XCTAssertEqual(h, 20 + 30, accuracy: 0.01)
    }

    // MARK: - 逐段累加

    /// 完整结构：头部 + 项目名 + 正文 + 2 个带描述的选项 + 其他行 + 发送按钮。
    ///
    /// 期望值手工推导：
    /// - 20（上下内边距）
    /// - 30（头部徽章）
    /// - 8 + 12（项目名 9pt，行高向上取整）
    /// - 8 + 15.6（正文单行 12pt）
    /// - 8 + Σ行高 + 2×6：
    ///     每个选项 = 14 + 15.6 + 1 + 13.65 = 44.25
    ///     其他行 = max(30, 14+15.6) = 30
    /// - 8 + 26（发送按钮）
    func testFullStructureMatchesHandComputedHeight() {
        let question = AgentQuestion(
            id: "q1",
            header: "范围",
            question: "这两个改动希望一次提交，还是拆成两次提交？",
            options: [
                AgentQuestionOption(label: "一次提交", description: "改动内聚，回滚方便"),
                AgentQuestionOption(label: "拆成两次", description: "协议变更单独可回滚"),
            ])

        let rowH = 14 + oneLineH(12) + 1 + oneLineH(10.5)   // 44.25
        let expected = 20 + 30
            + 8 + projectRowH
            + 8 + oneLineH(12)
            + 8 + (rowH * 2 + 30 + 6 * 2)
            + 8 + 26

        let h = QuestionCardLayout.contentHeight(question: question, hasProject: true,
                                                 metrics: metrics)
        XCTAssertEqual(h, expected, accuracy: 0.01)
    }

    /// 项目名行必须被计入——漏算它会直接把发送按钮挤出可视区。
    func testProjectRowAddsOneLineAndSpacing() {
        let question = AgentQuestion(id: "q1", header: "h", question: "问？",
                                     options: [AgentQuestionOption(label: "A", description: "")])
        let withProject = QuestionCardLayout.contentHeight(question: question, hasProject: true,
                                                            metrics: metrics)
        let without = QuestionCardLayout.contentHeight(question: question, hasProject: false,
                                                       metrics: metrics)
        XCTAssertEqual(withProject - without, 8 + projectRowH, accuracy: 0.01)
    }

    /// 每个选项都带描述时，高度必须随选项数线性增长（含 6pt 行间距）。
    func testEachOptionAddsRowPlusSpacing() {
        let one = AgentQuestion(id: "q1", header: "h", question: "问？",
                                options: [AgentQuestionOption(label: "A", description: "说明")])
        let two = AgentQuestion(id: "q1", header: "h", question: "问？",
                                options: [AgentQuestionOption(label: "A", description: "说明"),
                                          AgentQuestionOption(label: "B", description: "说明")])
        let h1 = QuestionCardLayout.contentHeight(question: one, hasProject: false, metrics: metrics)
        let h2 = QuestionCardLayout.contentHeight(question: two, hasProject: false, metrics: metrics)

        let rowH = 14 + oneLineH(12) + 1 + oneLineH(10.5)
        XCTAssertEqual(h2 - h1, rowH + 6, accuracy: 0.01)
    }

    /// 发送按钮高度必须被计入：去掉它等于少 34pt（8 + 26）。
    func testSendButtonHeightIsIncluded() {
        let question = AgentQuestion(id: "q1", header: "h", question: "", options: [])
        let h = QuestionCardLayout.contentHeight(question: question, hasProject: false,
                                                 metrics: metrics)
        // 20 + 30 + 8 + 30（其他行） + 8 + 26
        XCTAssertEqual(h, 20 + 30 + 8 + 30 + 8 + 26, accuracy: 0.01)
    }

    /// `minHeight` 作为下限生效。
    func testMinHeightFloorApplies() {
        var m = metrics
        m.minHeight = 400
        let question = AgentQuestion(id: "q1", header: "h", question: "", options: [])
        let h = QuestionCardLayout.contentHeight(question: question, hasProject: false, metrics: m)
        XCTAssertEqual(h, 400, accuracy: 0.01)
    }

    // MARK: - 文本测量

    /// 全角字符按 1.0×font 计宽：12pt 下 10 个汉字 = 120pt，超过 100pt 宽 → 2 行。
    func testFullWidthCharsWrapAtFontWidth() {
        let h = QuestionCardLayout.textHeight(String(repeating: "中", count: 10),
                                             width: 100, font: 12)
        XCTAssertEqual(h, 2 * 12 * 1.3, accuracy: 0.01)
    }

    /// 半角字符按 0.55×font 计宽：12pt 下 10 个字母 ≈ 66pt，100pt 宽内 → 1 行。
    func testHalfWidthCharsFitOneLine() {
        let h = QuestionCardLayout.textHeight(String(repeating: "a", count: 10),
                                             width: 100, font: 12)
        XCTAssertEqual(h, 12 * 1.3, accuracy: 0.01)
    }

    /// 正文超过两行时，折叠高度只留两行，不再为展开按钮加高；展开后按全文加高。
    func testCollapsedDetailOmitsExpandButton() {
        // 文字宽 560 - 32×2 = 496。全角 12pt，一行 41 字，82 字正好两行，83 字折到第三行。
        let fitted = AgentQuestion(
            id: "q1", header: "h",
            question: String(repeating: "中", count: 82),
            options: [AgentQuestionOption(label: "继续", description: "")])
        let longer = AgentQuestion(
            id: "q1", header: "h",
            question: String(repeating: "中", count: 83),
            options: [AgentQuestionOption(label: "继续", description: "")])
        let twoLines = QuestionCardLayout.contentHeight(
            question: fitted, hasProject: false, metrics: metrics,
            detail: .question(expanded: false))
        let collapsed = QuestionCardLayout.contentHeight(
            question: longer, hasProject: false, metrics: metrics,
            detail: .question(expanded: false))
        let expanded = QuestionCardLayout.contentHeight(
            question: longer, hasProject: false, metrics: metrics,
            detail: .question(expanded: true))
        XCTAssertEqual(collapsed, twoLines, accuracy: 0.01)
        XCTAssertGreaterThan(expanded, collapsed)
        let textW = metrics.cardWidth - metrics.cardInset * 2
        let full = QuestionCardLayout.textHeight(longer.question, width: textW, font: 12)
        let folded = DetailText.measure(fullHeight: full, font: 12, collapsedLines: 2, expanded: false)
        XCTAssertTrue(folded.showsControl)
        XCTAssertEqual(folded.shownLines, 2)
    }

    /// 空文本按单行处理（避免 0 高度让布局塌陷）。
    func testEmptyTextCountsAsOneLine() {
        let h = QuestionCardLayout.textHeight("", width: 100, font: 12)
        XCTAssertEqual(h, 12 * 1.3, accuracy: 0.01)
    }
}
