// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 测试 Transcript 的会话来源判定。
///
/// 新版 Qoder 内核（1.1.75+）把 GUI 会话的 transcript 写进 `~/.qoder/projects/`，
/// 首条 user 记录带 `entrypoint: "cli"`——与真正的无头管道会话（`qodercli -p`）同形。
/// 区分判据是 `humanInput` 字段：真人 UI 输入（含粘贴）有值，程序化输入为 None。
/// 判定收紧后：`entrypoint == "cli"` 且无 `humanInput` 才视为无头会话（抑制横幅）。
final class TranscriptCLITests: XCTestCase {

    /// 把 jsonl 行写入临时文件，返回路径（测试结束自动清理）。
    private func writeFixture(_ lines: [String]) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("bf-transcript-\(UUID().uuidString).jsonl")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    // MARK: - 新版 Qoder GUI 会话（修复目标）

    /// 测试：entrypoint=cli 但 humanInput 有值（真人 UI 输入）→ 不是无头会话。
    func testHumanUIInputWithCLIEntrypointIsNotHeadless() {
        let path = writeFixture([
            #"{"type":"user","entrypoint":"cli","humanInput":{"text":"hi","mode":"prompt"},"message":{"content":[{"type":"text","text":"hi"}]},"sessionId":"s1"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.entrypoint, "cli", "应读到新版内核写入的 cli 入口标记")
        XCTAssertTrue(s.hasHumanInput, "humanInput 有值即真人输入")
        XCTAssertFalse(s.fromCLI, "真人 UI 会话必须弹横幅，不得当作无头脚本抑制")
    }

    // MARK: - 无头管道会话（回归保护）

    /// 测试：entrypoint=cli 且无 humanInput（qodercli -p 管道 diff）→ 保持抑制。
    func testPipedCLIInputStaysHeadless() {
        let path = writeFixture([
            #"{"type":"user","entrypoint":"cli","origin":{"kind":"human"},"message":{"content":[{"type":"text","text":"diff --git a/x b/x"}]},"sessionId":"s2"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.entrypoint, "cli")
        XCTAssertFalse(s.hasHumanInput)
        XCTAssertTrue(s.fromCLI, "无 humanInput 的管道会话仍要抑制横幅")
    }

    /// 测试：humanInput 显式为 null（程序化输入的另一种写法）→ 保持抑制。
    func testExplicitNullHumanInputStaysHeadless() {
        let path = writeFixture([
            #"{"type":"user","entrypoint":"cli","humanInput":null,"message":{"content":[{"type":"text","text":"piped"}]},"sessionId":"s3"}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertFalse(s.hasHumanInput)
        XCTAssertTrue(s.fromCLI)
    }

    // MARK: - 其余 transcript 形态

    /// 测试：cache conversation-history 格式（role/message，无 type/entrypoint）→ 不抑制。
    func testCacheFormatIsNotHeadless() {
        let path = writeFixture([
            #"{"role":"user","message":{"content":"你好，帮我看看这个 bug"}}"#,
            #"{"role":"assistant","message":{"content":"好的"}}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.entrypoint, "", "cache 格式无 entrypoint 字段")
        XCTAssertFalse(s.fromCLI)
    }

    /// 测试：user 记录缺 entrypoint 字段（旧式 IDE 记录）→ 不抑制（原行为）。
    func testMissingEntrypointIsNotHeadless() {
        let path = writeFixture([
            #"{"type":"user","message":{"content":"帮我修 bug"}}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.entrypoint, "")
        XCTAssertFalse(s.fromCLI)
    }

    /// 测试：标题取自首条人类发言，判定收紧后不受影响。
    func testTitleStillParsedFromFirstHumanPrompt() {
        let path = writeFixture([
            #"{"type":"user","entrypoint":"cli","humanInput":{"text":"第一个问题","mode":"prompt"},"message":{"content":[{"type":"text","text":"第一个问题"}]},"sessionId":"s4"}"#,
            #"{"type":"user","entrypoint":"cli","humanInput":{"text":"第二个问题","mode":"prompt"},"message":{"content":[{"type":"text","text":"第二个问题"}]},"sessionId":"s4"}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.title, "第一个问题")
        XCTAssertEqual(s.latest, "第二个问题")
        XCTAssertEqual(s.latestDetail, "第二个问题")
    }

    /// 单行横幅仍截到 56 字，展开用的详情保留后半段。
    func testDetailKeepsTextBeyondTheSingleLineLimit() {
        let long = String(repeating: "详细", count: 40)
        let path = writeFixture([
            #"{"type":"user","message":{"content":"标题"}}"#,
            #"{"type":"user","message":{"content":"\#(long)"}}"#,
        ])
        let s = Transcript.sessionSummary(path: path, provider: "qoder")
        XCTAssertEqual(s.latest.count, Transcript.bodyLimit)
        XCTAssertTrue(s.latest.hasSuffix("…"))
        XCTAssertEqual(s.latestDetail, long)
    }

    /// 测试：文件缺失时坍缩为空会话（不抑制、不崩溃）。
    func testMissingFileCollapsesToEmpty() {
        let s = Transcript.sessionSummary(path: "/nonexistent/x.jsonl", provider: "qoder")
        XCTAssertFalse(s.fromCLI)
        XCTAssertFalse(s.hasHumanInput)
    }
}
