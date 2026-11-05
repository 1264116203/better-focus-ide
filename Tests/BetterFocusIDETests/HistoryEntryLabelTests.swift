// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 历史行副文字前缀的契约测试。
///
/// 三类通知的 `body` 语义不同，历史上统一冠以「答：」导致语义错位
/// （轮次完成通知的 body 其实是用户这一轮的输入，见 `Transcript.last()`）。
final class HistoryEntryLabelTests: XCTestCase {

    private func entry(title: String, body: String, kind: HistoryKind,
                       state: String = "回复完成") -> HistoryEntry {
        HistoryEntry(title: title, body: body, kind: kind, state: state,
                     source: "Qoder", project: "", provider: "qoder", host: nil,
                     tintRGB: (red: 0.5, green: 0.4, blue: 0.9), timestamp: Date())
    }

    // MARK: - 前缀语义

    /// 轮次完成：body 是用户这一轮的输入 → 「你说：」。
    func testTurnBodyUsesUserPrefix() {
        let e = entry(title: "实现这个 prd", body: "把登录页改成邮箱登录", kind: .turn)
        XCTAssertEqual(e.bodyLine, "你说：把登录页改成邮箱登录")
    }

    /// 提问卡片：body 是智能体问用户的正文 → 「问：」。
    func testQuestionBodyUsesAskPrefix() {
        let e = entry(title: "范围", body: "这次改动要一起提交吗？", kind: .question)
        XCTAssertEqual(e.bodyLine, "问：这次改动要一起提交吗？")
    }

    /// 权限请求：body 是命令/操作详情 → 「详情：」。
    func testPermissionBodyUsesDetailPrefix() {
        let e = entry(title: "Agent 请求执行「Bash」",
                      body: "rm -rf node_modules && npm install",
                      kind: .permission, state: "待审批")
        XCTAssertEqual(e.bodyLine, "详情：rm -rf node_modules && npm install")
    }

    // MARK: - 不展示的情况

    /// 正文与标题重复（单轮会话里两者同为用户提示词）→ 整行不渲染。
    func testDuplicateBodyIsHidden() {
        let e = entry(title: "实现这个 prd", body: "实现这个 prd", kind: .turn)
        XCTAssertTrue(e.bodyLine.isEmpty)
    }

    /// 单轮会话里标题是正文的截断版（带省略号），同样视为重复。
    func testTruncatedTitleDuplicatingBodyIsHidden() {
        let e = entry(title: "diff --git a/ruoyi-admin/src/main…",
                      body: "diff --git a/ruoyi-admin/src/main/resources/application.yml",
                      kind: .turn)
        XCTAssertTrue(e.bodyLine.isEmpty)
    }

    /// 多轮会话：正文是新一轮输入，与首条标题不同源，应正常展示。
    func testLaterTurnBodyIsShown() {
        let e = entry(title: "使用 ask question 工具推荐一个方案",
                      body: "nia", kind: .turn)
        XCTAssertEqual(e.bodyLine, "你说：nia")
    }

    func testEmptyBodyIsHidden() {
        XCTAssertTrue(entry(title: "OpenCode 回复完成", body: "", kind: .turn).bodyLine.isEmpty)
    }

    /// 读不到会话记录时的兜底跳转文案（旧数据会存进 body）→ 整行不渲染。
    func testJumpHintBodyIsHidden() {
        let e = entry(title: "WorkBuddy 回复完成",
                      body: "点击跳转回 WorkBuddy", kind: .turn)
        XCTAssertTrue(e.bodyLine.isEmpty)
    }

    // MARK: - 旧数据兼容

    /// 旧版 history.json 没有 `kind` 字段：必须能整体解码，并按状态回退推断。
    func testLegacyJSONWithoutKindStillDecodes() throws {
        let json = """
        [{
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "OpenCode 回复完成",
          "body": "点击跳转回 OpenCode",
          "state": "回复完成",
          "source": "OpenCode",
          "project": "",
          "provider": "opencode",
          "timestamp": 780000000,
          "tintRed": 0.2, "tintGreen": 0.6, "tintBlue": 1.0
        }]
        """
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].kind, .turn, "状态含「回复完成」应回退为 turn")
    }

    /// 旧数据里的提问条目按 `question` 回退（状态为「已回答」等）。
    func testLegacyQuestionStateFallsBackToQuestion() {
        XCTAssertEqual(HistoryKind.legacy(from: "已回答"), .question)
        XCTAssertEqual(HistoryKind.legacy(from: "待审批"), .question)
        XCTAssertEqual(HistoryKind.legacy(from: "回复完成"), .turn)
    }

    /// 新格式写入后必须能原样读回 kind。
    func testKindRoundTripsThroughJSON() throws {
        let original = [entry(title: "t", body: "b", kind: .permission, state: "待审批")]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
        XCTAssertEqual(decoded[0].kind, .permission)
    }
}
