// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 进度卡和通知抢屏、收起后还能否点回来，这两条规则以前写在 NotchService 的分支里，
/// 改一处就容易把另一处打掉。这里把纯判定锁住。
final class TodoPresentationTests: XCTestCase {

    func testInProgressTodoYieldsNoticeQuestionAndPermission() {
        XCTAssertTrue(NotchService.todoYieldsCard(to: .question))
        XCTAssertTrue(NotchService.todoYieldsCard(to: .permission))
        XCTAssertTrue(NotchService.todoYieldsCard(to: .notice))
        // 历史是只读面板，进度卡可以换掉它。空闲和进度卡自己也不算让位。
        XCTAssertFalse(NotchService.todoYieldsCard(to: .history))
        XCTAssertFalse(NotchService.todoYieldsCard(to: .todo))
        XCTAssertFalse(NotchService.todoYieldsCard(to: .none))
    }

    func testCollapseKeepsOnlyInProgressTodo() {
        XCTAssertFalse(NotchService.clearsTodoOnCollapse(hasTodo: true, isFinished: false))
        XCTAssertTrue(NotchService.clearsTodoOnCollapse(hasTodo: true, isFinished: true))
        XCTAssertTrue(NotchService.clearsTodoOnCollapse(hasTodo: false, isFinished: false))
    }

    func testCollapsedInProgressTodoDropsBelowTheNotch() {
        let base = CGSize(width: 170, height: 27.5)
        let grown = NotchService.collapsedSize(base: base, inProgress: true)
        XCTAssertEqual(grown.width, base.width)
        XCTAssertEqual(grown.height, base.height + NotchLayout.progressLineChin)
        XCTAssertGreaterThan(NotchLayout.progressLineChin,
                             NotchLayout.progressLineBottomPadding + NotchLayout.progressLineHeight)
        XCTAssertEqual(NotchService.collapsedSize(base: base, inProgress: false), base)
    }

    func testProgressLineDoesNotDoubleUp() {
        // 收起态：只在气泡下沿。
        XCTAssertEqual(
            NotchService.progressLineSlot(expanded: false, closing: false, card: .none, inProgress: true),
            .bubble)
        // 通知 / 提问 / 权限占主体：改贴卡片底边，气泡上那条让开。
        for card in [NotchService.ActiveCard.notice, .question, .permission] {
            XCTAssertEqual(
                NotchService.progressLineSlot(expanded: true, closing: false, card: card, inProgress: true),
                .cardEdge)
            XCTAssertEqual(
                NotchService.progressLineSlot(expanded: false, closing: true, card: card, inProgress: true),
                .cardEdge)
        }
        // 进度卡自己在屏时，底边不再加一条；线留在顶部气泡。
        XCTAssertEqual(
            NotchService.progressLineSlot(expanded: true, closing: false, card: .todo, inProgress: true),
            .bubble)
        // 全部完成或没有待办：两处都不画。
        XCTAssertEqual(
            NotchService.progressLineSlot(expanded: true, closing: false, card: .notice, inProgress: false),
            .hidden)
        XCTAssertEqual(
            NotchService.progressLineSlot(expanded: false, closing: false, card: .todo, inProgress: false),
            .hidden)
    }

    /// 卡片底边的内收必须大于气泡那条 12pt，并且落在底角圆角的内侧。
    func testCardEdgeInsetClearsBottomCorner() {
        let height: CGFloat = 106
        let inset = NotchLayout.progressLineInset(cardHeight: height)
        let shoulder = NotchLayout.shoulder(height: height)
        let bottom = min(NotchLayout.surfaceRadius(height: height), height / 2)
        let centerFromBottom = NotchLayout.progressLineBottomPadding + NotchLayout.progressLineHeight / 2
        let dy = bottom - centerFromBottom
        let chord = sqrt(bottom * bottom - dy * dy)
        let wall = shoulder + (bottom - chord)
        XCTAssertGreaterThan(inset, wall)
        XCTAssertGreaterThan(inset, NotchLayout.progressLineBubbleInset)

        let tiny = NotchLayout.progressLineInset(cardHeight: 0)
        XCTAssertTrue(tiny.isFinite)
        XCTAssertGreaterThanOrEqual(tiny, 0)
    }

    func testRunningTodoNoteMatchesKeptProgressLine() {
        let scene = DebugCatalog.scenes.first { $0.id == "todo.running" }
        XCTAssertEqual(scene?.note, "3 项已完成、1 项进行中、2 项待开始；收起后气泡下沿仍有进度线，再点可展开")
    }
}
