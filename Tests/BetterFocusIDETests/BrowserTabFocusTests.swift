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
        XCTAssertTrue(script.contains(#"return "none " & wc & " " & tc & " " & lc"#),
                      "没命中必须能区分出来，并带上扫描计数")
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
        let condition = target.needles
            .map { #"(u contains "\#($0)")"# }
            .joined(separator: " or ")
        XCTAssertTrue(script.contains("if \(condition) then"),
                      "命中条件被拼坏了：\(condition)")
    }

    // MARK: - 候选顺序

    /// 前台浏览器排第一：系统默认是 Safari、用户实际在 Chrome 里聊天时，
    /// 只按默认排序会切到 Safari 里那个早已过期的旧标签页。
    func testFrontmostBrowserGoesFirst() {
        let ordered = BrowserTabFocus.orderedCandidates(
            frontmost: "com.google.Chrome", defaultBundle: "com.apple.Safari")
        XCTAssertEqual(ordered.first?.bundle, "com.google.Chrome")
        XCTAssertEqual(ordered.count, BrowserTabFocus.allBrowsers.count)
        XCTAssertEqual(ordered[1].bundle, "com.apple.Safari")
    }

    func testDefaultBrowserGoesFirstWithoutFrontmost() {
        let safariFirst = BrowserTabFocus.orderedCandidates(
            frontmost: nil, defaultBundle: "com.apple.Safari")
        XCTAssertEqual(safariFirst.first?.bundle, "com.apple.Safari")
        XCTAssertEqual(safariFirst.count, BrowserTabFocus.allBrowsers.count)
    }

    /// 前台就是默认浏览器时不能重复出现两份。
    func testSameFrontmostAndDefaultNotDuplicated() {
        let ordered = BrowserTabFocus.orderedCandidates(
            frontmost: "com.google.Chrome", defaultBundle: "com.google.Chrome")
        XCTAssertEqual(ordered.filter { $0.bundle == "com.google.Chrome" }.count, 1)
        XCTAssertEqual(ordered.count, BrowserTabFocus.allBrowsers.count)
    }

    /// 前台应用不是浏览器（IDE / 终端）时返回 nil，不参与排序。
    func testFrontmostNonBrowserIsIgnored() {
        let ordered = BrowserTabFocus.orderedCandidates(
            frontmost: "com.jetbrains.intellij", defaultBundle: "com.apple.Safari")
        XCTAssertEqual(ordered.first?.bundle, "com.apple.Safari")
        XCTAssertEqual(ordered.count, BrowserTabFocus.allBrowsers.count)
    }

    func testCandidatesHaveUniqueBundles() {
        let bundles = BrowserTabFocus.allBrowsers.map(\.bundle)
        XCTAssertEqual(Set(bundles).count, bundles.count)
    }

    // MARK: - 脚本结果解析

    func testParseFound() {
        XCTAssertEqual(BrowserTabFocus.parse("found"), .found)
        XCTAssertEqual(BrowserTabFocus.parse("found\n"), .found)
    }

    /// 扫描计数要能读出来：0 窗口说明脚本压根没看到窗口（权限 / 窗口类型）。
    func testParseNotFoundCarriesCounts() {
        XCTAssertEqual(BrowserTabFocus.parse("none 3 47 2"),
                       .notFound(windows: 3, tabs: 47, localPages: 2))
        XCTAssertEqual(BrowserTabFocus.parse("none 0 0 0"),
                       .notFound(windows: 0, tabs: 0, localPages: 0))
    }

    func testParseGarbageFallsBackToZeroCounts() {
        XCTAssertEqual(BrowserTabFocus.parse(""),
                       .notFound(windows: 0, tabs: 0, localPages: 0))
        XCTAssertEqual(BrowserTabFocus.parse("something else"),
                       .notFound(windows: 0, tabs: 0, localPages: 0))
    }
}
