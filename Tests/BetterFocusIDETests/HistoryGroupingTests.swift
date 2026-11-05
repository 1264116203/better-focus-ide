// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 历史面板「按会话归并」的契约测试。
///
/// 同一个会话每回复一轮都产生一条通知，只是 `body`（用户这一轮说了什么）不同。
/// 逐条铺开会把一屏五条全占满，因此同会话只保留最新一条。
final class HistoryGroupingTests: XCTestCase {

    private func entry(_ title: String, body: String = "",
                       provider: String = "workbuddy", session: String,
                       at secondsAgo: TimeInterval = 0) -> HistoryEntry {
        HistoryEntry(title: title, body: body, kind: .turn, sessionID: session,
                     state: "回复完成", source: "WorkBuddy", project: "demo",
                     provider: provider, host: nil,
                     tintRGB: (red: 0.3, green: 0.6, blue: 1.0),
                     timestamp: Date().addingTimeInterval(-secondsAgo))
    }

    // MARK: - upserting

    /// 同会话的新通知取代旧通知，且排到队首——不新增行。
    func testSameSessionReplacesPreviousEntry() {
        let first = entry("请对 wf-dev 工作流做 A", body: "先不用了", session: "s1", at: 60)
        let second = entry("请对 wf-dev 工作流做 A", body: "继续处理遗留问题", session: "s1")

        let list = HistoryController.upserting(second, into: [first])

        XCTAssertEqual(list.count, 1, "同一会话只应占一行")
        XCTAssertEqual(list[0].id, second.id, "保留的应是最新一条")
        XCTAssertEqual(list[0].body, "继续处理遗留问题")
    }

    /// 不同会话各占一行，新的排在前面。
    func testDifferentSessionsAreKeptSeparately() {
        let older = entry("会话 A", session: "s1", at: 60)
        let newer = entry("会话 B", session: "s2")

        let list = HistoryController.upserting(newer, into: [older])

        XCTAssertEqual(list.map(\.sessionID), ["s2", "s1"])
    }

    /// 同一 sessionID 但来自不同产品：不是同一个会话，不能合并。
    func testSameSessionIDAcrossProvidersStaysSeparate() {
        let qoder = entry("Qoder 回合", provider: "qoder", session: "s1", at: 60)
        let workbuddy = entry("WorkBuddy 回合", provider: "workbuddy", session: "s1")

        let list = HistoryController.upserting(workbuddy, into: [qoder])

        XCTAssertEqual(list.count, 2)
    }

    /// 升级前的旧行没有会话号：靠「产品 + 来源 + 标题 + 项目」认亲并收拢，
    /// 否则面板上会一直留着那几条同会话的重复行。
    func testLegacyEntriesWithSameIdentityAreMerged() {
        let a = entry("终端命令", provider: "qoder", session: "")
        let b = entry("终端命令", provider: "qoder", session: "")

        XCTAssertNil(a.sessionKey)
        XCTAssertEqual(a.legacyKey, b.legacyKey, "同产品同来源同标题应视为同一会话")
        XCTAssertEqual(HistoryController.upserting(b, into: [a]).count, 1)
    }

    /// 标题不同的旧行仍是不同会话，不能被近似身份误合并。
    func testLegacyEntriesWithDifferentTitlesStaySeparate() {
        let a = entry("会话 A", provider: "qoder", session: "")
        let b = entry("会话 B", provider: "qoder", session: "")

        XCTAssertEqual(HistoryController.upserting(b, into: [a]).count, 2)
    }

    /// 新一轮通知（带会话号）落进来时，应顶掉升级前那条同身份的旧行。
    func testNewSessionEntryReplacesMatchingLegacyRow() {
        let legacy = entry("请对 wf-dev 工作流做 A", body: "先不用了", provider: "qoder", session: "")
        let fresh = entry("请对 wf-dev 工作流做 A", body: "继续处理遗留问题",
                          provider: "qoder", session: "s-wf")

        let list = HistoryController.upserting(fresh, into: [legacy])

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].sessionID, "s-wf")
    }

    /// 截断按会话数计：保持 5 行，挤掉最旧的会话。
    func testLimitCountsSessionsNotNotifications() {
        var list: [HistoryEntry] = []
        for i in 0..<HistoryController.limit {
            list = HistoryController.upserting(entry("会话 \(i)", session: "s\(i)"), into: list)
        }
        // 更新最老的会话（s0）：它被移到队首，总数不变。
        list = HistoryController.upserting(entry("会话 0 第二轮", session: "s0"), into: list)
        XCTAssertEqual(list.count, HistoryController.limit)
        XCTAssertEqual(list.first?.sessionID, "s0")

        // 新会话把队尾挤掉（此时队尾是 s1：s0 刚被移到队首，s4 顺位上移）。
        list = HistoryController.upserting(entry("会话 new", session: "s-new"), into: list)
        XCTAssertEqual(list.count, HistoryController.limit)
        XCTAssertEqual(list.first?.sessionID, "s-new")
        XCTAssertFalse(list.contains { $0.sessionID == "s1" })
    }

    // MARK: - grouped（加载归并）

    /// 旧版本写进文件的重复条目在加载时被归并，保留位置最靠前（最新）的那条。
    func testGroupedKeepsNewestPerSession() {
        let newest = entry("会话 A", body: "第三轮", session: "s1")
        let middle = entry("会话 A", body: "第二轮", session: "s1", at: 30)
        let older = entry("会话 B", body: "第一轮", session: "s2", at: 60)

        let list = HistoryController.grouped([newest, middle, older])

        XCTAssertEqual(list.map(\.sessionID), ["s1", "s2"])
        XCTAssertEqual(list.first?.body, "第三轮")
    }

    /// 旧数据没有 sessionID：标题不同，两条都保留。
    func testGroupedKeepsLegacyEntriesWithDifferentTitles() {
        let one = entry("旧条目 1", provider: "qoder", session: "")
        let two = entry("旧条目 2", provider: "qoder", session: "")

        XCTAssertEqual(HistoryController.grouped([one, two]).count, 2)
    }

    // MARK: - 序列化

    /// sessionID 必须随历史文件往返，否则重启后归并失效。
    func testSessionIDRoundTripsThroughJSON() throws {
        let original = [entry("会话 A", body: "用户输入", session: "s-42")]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
        XCTAssertEqual(decoded.first?.sessionID, "s-42")
    }

    /// 旧文件没有 sessionID 字段时解码为空串，不抛错。
    func testLegacyEntryWithoutSessionIDDecodesToEmpty() throws {
        let json = """
        [{
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "未命名会话",
          "body": "用户输入",
          "kind": "turn",
          "state": "回复完成",
          "source": "WorkBuddy",
          "project": "demo",
          "provider": "workbuddy",
          "timestamp": 780000000,
          "tintRed": 0.2, "tintGreen": 0.6, "tintBlue": 1.0
        }]
        """
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.sessionID, "")
        XCTAssertNil(decoded.first?.sessionKey)
    }
}
