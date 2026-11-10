// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 同一会话的未读通知只留最新一条。更新的一到，更早的视为已读。
final class NoticeQueueTests: XCTestCase {

    private func notice(_ session: String, title: String, kind: HistoryKind = .turn) -> TurnNotice {
        TurnNotice(provider: "cursor", providerName: "Cursor", sessionID: session,
                   title: title, body: title, bodyIsFallback: false, kind: kind,
                   project: "demo", host: nil, arrivedAt: Date(),
                   jumpEnabled: true, fromCLI: false)
    }

    /// 屏上就是这条会话的旧通知：直接换成新的，队列里不再留旧的。
    func testSameSessionReplacesTheVisibleNotice() {
        let older = notice("s1", title: "第一轮")
        let newer = notice("s1", title: "第二轮")
        let other = notice("s2", title: "另一个 IDE")

        let result = NoticeController.admit(
            newer,
            into: .init(current: older, queued: [other, notice("s1", title: "还在排队")], resting: nil),
            blocked: false)

        XCTAssertEqual(result.effect, .replace)
        XCTAssertEqual(result.slot.current?.title, "第二轮")
        XCTAssertEqual(result.slot.queued.map(\.title), ["另一个 IDE"])
    }

    /// 屏上是别的会话：不打断它。本会话队列里的旧通知丢掉，只排进最新的。
    func testSameSessionInQueueKeepsOnlyTheLatest() {
        let showing = notice("s2", title: "正在看")
        let newer = notice("s1", title: "最新")

        let result = NoticeController.admit(
            newer,
            into: .init(current: showing,
                        queued: [notice("s1", title: "旧的"), notice("s1", title: "更旧")],
                        resting: notice("s1", title: "收起的")),
            blocked: false)

        XCTAssertEqual(result.effect, .enqueue(retiredResting: true))
        XCTAssertEqual(result.slot.current?.title, "正在看")
        XCTAssertEqual(result.slot.queued.map(\.title), ["最新"])
        XCTAssertNil(result.slot.resting)
    }

    /// 提问或权限卡还在时，不把横幅抢上来。同会话垫在底下的旧通知清掉。
    func testBlockedCardDropsTheOlderNoticeUnderneath() {
        let underneath = notice("s1", title: "垫着的")
        let newer = notice("s1", title: "更新的")

        let result = NoticeController.admit(
            newer,
            into: .init(current: underneath, queued: [], resting: nil),
            blocked: true)

        XCTAssertEqual(result.effect, .enqueue(retiredResting: false))
        XCTAssertNil(result.slot.current)
        XCTAssertEqual(result.slot.queued.map(\.title), ["更新的"])
    }

    /// 没有会话号就无从判断是不是同一条，两条都留着。
    func testEmptySessionDoesNotCollapse() {
        let first = notice("", title: "甲")
        let second = notice("", title: "乙")

        let result = NoticeController.admit(
            second,
            into: .init(current: first, queued: [], resting: nil),
            blocked: false)

        XCTAssertEqual(result.effect, .enqueue(retiredResting: false))
        XCTAssertEqual(result.slot.current?.title, "甲")
        XCTAssertEqual(result.slot.queued.map(\.title), ["乙"])
    }

    /// 别的会话的回合横幅还在时，权限提醒直接顶上来。被顶下的横幅留在队首。
    func testPermissionNoticePreemptsAnotherSessionsBanner() {
        let banner = notice("s2", title: "回合完成")
        let permission = notice("s1", title: "需要授权", kind: .permission)

        let result = NoticeController.admit(
            permission,
            into: .init(current: banner, queued: [], resting: nil),
            blocked: false)

        XCTAssertEqual(result.effect, .replace)
        XCTAssertEqual(result.slot.current?.title, "需要授权")
        XCTAssertEqual(result.slot.queued.map(\.title), ["回合完成"])
    }

    /// 提问或权限卡占着岛时，权限横幅继续排队，不抢前台。
    func testPermissionNoticeWaitsWhileACardIsUp() {
        let permission = notice("s1", title: "需要授权", kind: .permission)

        let result = NoticeController.admit(
            permission,
            into: .init(current: notice("s2", title: "回合完成"), queued: [], resting: nil),
            blocked: true)

        XCTAssertEqual(result.effect, .enqueue(retiredResting: false))
        XCTAssertEqual(result.slot.current?.title, "回合完成")
        XCTAssertEqual(result.slot.queued.map(\.title), ["需要授权"])
    }

    /// 岛空着时，新通知直接上屏，并清掉同一会话收起后还没点开的那条。
    func testIdlePresentsAndRetiresTheCollapsedOne() {
        let newer = notice("s1", title: "最新")

        let result = NoticeController.admit(
            newer,
            into: .init(current: nil, queued: [], resting: notice("s1", title: "收起的")),
            blocked: false)

        XCTAssertEqual(result.effect, .present)
        XCTAssertEqual(result.slot.current?.title, "最新")
        XCTAssertNil(result.slot.resting)
        XCTAssertTrue(result.slot.queued.isEmpty)
    }
}
