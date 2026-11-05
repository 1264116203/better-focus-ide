// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 浏览器标签页定位的契约测试。
///
/// 判定分两半：地址怎么认（`Target`）、脚本怎么写（`script`）。两半都不依赖
/// 真跑浏览器——脚本拼错一个属性名不会报错，只会静默变成「每次新开 tab」，
/// 所以这里把关键片段钉住。
final class BrowserTabFocusTests: XCTestCase {

    // MARK: - 地址解析

    func testTargetParsesLoopbackPort() throws {
        let target = try XCTUnwrap(BrowserTabFocus.Target(url: "http://127.0.0.1:4096/"))
        XCTAssertEqual(target.host, "127.0.0.1")
        XCTAssertEqual(target.port, 4096)
        // 用户手敲的 localhost 与插件上报的 127.0.0.1 是同一个人。
        XCTAssertTrue(target.needles.contains("127.0.0.1:4096"))
        XCTAssertTrue(target.needles.contains("localhost:4096"))
    }

    func testTargetRequiresPort() {
        XCTAssertNil(BrowserTabFocus.Target(url: "http://127.0.0.1/"),
                     "没有端口时无法区分服务，只能回退去新开一个 tab")
        XCTAssertNil(BrowserTabFocus.Target(url: "not a url"))
    }

    func testNeedlesAreUnique() throws {
        let target = try XCTUnwrap(BrowserTabFocus.Target(url: "http://localhost:3000/"))
        XCTAssertEqual(Set(target.needles).count, target.needles.count)
    }

    // MARK: - 脚本生成

    func testChromiumScriptUsesActiveTabIndex() throws {
        let target = try XCTUnwrap(BrowserTabFocus.Target(url: "http://127.0.0.1:4096/"))
        let script = BrowserTabFocus.script(
            for: BrowserTabFocus.chromiumBrowsers[0], target: target)
        XCTAssertTrue(script.contains(#"tell application "Google Chrome""#))
        XCTAssertTrue(script.contains("active tab index of window wi to ti"))
        XCTAssertTrue(script.contains(#"u contains "127.0.0.1:4096""#))
        XCTAssertTrue(script.contains(#"return "found""#))
        XCTAssertTrue(script.contains(#"return "none""#), "没命中必须能区分出来")
    }

    /// Safari 的属性名与 Chromium 系不同，写混了就静默失效。
    func testSafariScriptUsesCurrentTab() throws {
        let target = try XCTUnwrap(BrowserTabFocus.Target(url: "http://127.0.0.1:4096/"))
        let script = BrowserTabFocus.script(for: BrowserTabFocus.safari, target: target)
        XCTAssertTrue(script.contains("current tab of window wi to tab ti of window wi"))
        XCTAssertFalse(script.contains("active tab index"))
    }

    /// 多个候选地址要拼成合法的 `or` 链，不能漏掉分隔。
    func testScriptJoinsNeedlesWithOr() throws {
        let target = try XCTUnwrap(BrowserTabFocus.Target(url: "http://127.0.0.1:4096/"))
        let script = BrowserTabFocus.script(for: BrowserTabFocus.safari, target: target)
        let needles = target.needles.count
        XCTAssertEqual(script.components(separatedBy: " or ").count, needles)
    }

    // MARK: - 候选顺序

    func testDefaultBrowserGoesFirst() {
        let chromeFirst = BrowserTabFocus.candidates(defaultBundle: "com.google.Chrome")
        XCTAssertEqual(chromeFirst.first?.bundle, "com.google.Chrome")
        XCTAssertEqual(chromeFirst.count, BrowserTabFocus.allBrowsers.count)

        let safariFirst = BrowserTabFocus.candidates(defaultBundle: "com.apple.Safari")
        XCTAssertEqual(safariFirst.first?.bundle, "com.apple.Safari")
    }

    /// 默认浏览器不在支持列表里（Firefox / Arc）时保持原顺序，一个都不丢。
    func testUnknownDefaultKeepsOrder() {
        let candidates = BrowserTabFocus.candidates(defaultBundle: "org.mozilla.firefox")
        XCTAssertEqual(candidates, BrowserTabFocus.allBrowsers)
    }

    func testCandidatesHaveUniqueBundles() {
        let bundles = BrowserTabFocus.allBrowsers.map(\.bundle)
        XCTAssertEqual(Set(bundles).count, bundles.count)
    }
}
