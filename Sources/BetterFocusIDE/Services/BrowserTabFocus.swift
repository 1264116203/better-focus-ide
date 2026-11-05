// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 把浏览器里**已经打开**的那个页面切到前台。
///
/// `opencode serve` 这类会话没有窗口，落地页是 `http://127.0.0.1:4096/`。
/// 直接 `NSWorkspace.open` 只会在默认浏览器里再开一个 tab——用户手里那个
/// 正在对话的页面还留在后面。这里用 AppleScript 遍历已开标签页找同一个地址，
/// 找到就把窗口提到最前并切到那个 tab；找不到才由调用方回退到新开。
///
/// 只覆盖支持脚本枚举标签页的浏览器（Chromium 系 + Safari）。Firefox / Arc
/// 没有对应 AppleScript 接口，会自然走到回退分支，行为与之前一致。
enum BrowserTabFocus {
    /// 一个可脚本枚举标签页的浏览器。
    struct Browser: Equatable {
        /// AppleScript 里的应用名（`tell application "…"`）。
        let name: String
        let bundle: String
    }

    /// Chromium 系：标签页 API 完全一致（`active tab index of window`）。
    static let chromiumBrowsers: [Browser] = [
        Browser(name: "Google Chrome", bundle: "com.google.Chrome"),
        Browser(name: "Microsoft Edge", bundle: "com.microsoft.edgemac"),
        Browser(name: "Brave Browser", bundle: "com.brave.Browser"),
        Browser(name: "Vivaldi", bundle: "com.vivaldi.Vivaldi"),
        Browser(name: "Chromium", bundle: "org.chromium.Chromium"),
    ]

    /// Safari 的标签页 API 与 Chromium 系不同（`current tab of window`）。
    static let safari = Browser(name: "Safari", bundle: "com.apple.Safari")

    static var allBrowsers: [Browser] { chromiumBrowsers + [safari] }

    /// 目标地址里用来比对的片段。
    struct Target: Equatable {
        let host: String
        let port: Int

        /// 地址无法解析出端口时返回 nil（只用主机名会误匹配整站）。
        init?(url: String) {
            guard let components = URLComponents(string: url),
                  let port = components.port, port > 0 else { return nil }
            host = components.host ?? "127.0.0.1"
            self.port = port
        }

        /// 浏览器地址栏里同一服务可能的写法：`127.0.0.1:4096` / `localhost:4096` 等。
        /// 用户手敲 `localhost`、插件上报 `127.0.0.1` 是常态，两种都要认。
        var needles: [String] {
            var seen: [String] = []
            for candidate in [host, "localhost", "127.0.0.1", "[::1]"] {
                let needle = "\(candidate):\(port)"
                if !candidate.isEmpty, !seen.contains(needle) { seen.append(needle) }
            }
            return seen
        }
    }

    /// 在已打开的标签页里找到该地址并切过去；没有则返回 false。
    ///
    /// 串行执行：连点几次时不能让多个 AppleScript 同时在后台线程上跑。
    static func focusExistingTab(url: String) -> Bool {
        queue.sync { focus(url: url) }
    }

    private static let queue = DispatchQueue(label: "com.betterfocus.browsertab",
                                             qos: .userInitiated)

    private static func focus(url: String) -> Bool {
        guard let target = Target(url: url) else { return false }
        let list = candidates()
        Log.info("标签页定位：前台=\(frontmostBrowserBundle() ?? "-") "
                 + "默认=\(defaultBrowserBundle() ?? "-")", topic: "launcher")
        for browser in list {
            guard isRunning(browser.bundle) else { continue }
            switch runScript(script(for: browser, target: target)) {
            case .found:
                Log.info("已切到 \(browser.name) 里已打开的 \(target.host):\(target.port)",
                         topic: "launcher")
                return true
            case .notFound(let windows, let tabs, let localPages):
                // 扫过多少要留下痕迹：命中不了时才能区分「浏览器里没这个页面」与
                // 「脚本根本没看到窗口」（无权限 / 窗口类型不支持）。
                Log.info("\(browser.name) 未命中：\(windows) 窗口 / \(tabs) 标签页"
                         + "（本机页面 \(localPages) 个）", topic: "launcher")
                continue
            case .failed:
                // 多半是没给「自动化」权限：换浏览器没意义，直接去回退分支。
                Log.info("\(browser.name) 标签页定位不可用（可能未授予自动化权限）", topic: "launcher")
                continue
            }
        }
        return false
    }

    // MARK: - 候选浏览器

    /// 用户此刻正在用的浏览器 → 系统默认浏览器 → 其余。
    ///
    /// 默认浏览器未必是用户开着页面的那个：系统默认是 Safari、用户实际在
    /// Chrome 里聊天时，只按默认排序会切到 Safari 里那个早已过期的旧标签页。
    /// 点击通知时本应用是 `.nonactivatingPanel`，不会抢焦点，所以前台应用
    /// 仍是用户刚离开的那个浏览器，这是最可靠的信号。
    static func orderedCandidates(frontmost: String?, defaultBundle: String?) -> [Browser] {
        var ordered: [Browser] = []
        for bundle in [frontmost, defaultBundle].compactMap({ $0 }) {
            guard let browser = allBrowsers.first(where: { $0.bundle == bundle }),
                  !ordered.contains(browser) else { continue }
            ordered.append(browser)
        }
        ordered += allBrowsers.filter { !ordered.contains($0) }
        return ordered
    }

    static func candidates() -> [Browser] {
        orderedCandidates(frontmost: frontmostBrowserBundle(),
                          defaultBundle: defaultBrowserBundle())
    }

    /// 前台应用若是受支持的浏览器则返回它的 bundle id。
    static func frontmostBrowserBundle() -> String? {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier,
              allBrowsers.contains(where: { $0.bundle == bundle }) else { return nil }
        return bundle
    }

    /// 系统里打开 http 的默认应用。
    static func defaultBrowserBundle() -> String? {
        guard let probe = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    /// 找不到标签页时的兜底：优先开在用户正在用的浏览器里，而不是系统默认。
    static func openInPreferredBrowser(url: String) -> Bool {
        guard let bundle = candidates().first(where: { isRunning($0.bundle) })?.bundle
                ?? defaultBrowserBundle() else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundle, url]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return false }
            Log.info("已在 \(bundle) 打开 \(url)", topic: "launcher")
            return true
        } catch {
            return false
        }
    }

    static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    // MARK: - 脚本

    /// 生成「找到就切过去、否则什么都不做」的 AppleScript。
    ///
    /// 抽成纯函数便于测试：两套浏览器的标签页属性名不同，写错一个字母就静默
    /// 变成「每次都在新 tab 打开」。
    static func script(for browser: Browser, target: Target) -> String {
        let condition = target.needles
            .map { #"(u contains "\#(escape($0))")"# }
            .joined(separator: " or ")
        let activation: String
        if browser.bundle == safari.bundle {
            activation = """
                    set current tab of window wi to tab ti of window wi
                    set miniaturized of window wi to false
                    set index of window wi to 1
                    activate
                    return "found"
            """
        } else {
            activation = """
                    set active tab index of window wi to ti
                    set minimized of window wi to false
                    set index of window wi to 1
                    activate
                    return "found"
            """
        }
        return """
        tell application "\(escape(browser.name))"
            set wc to count of windows
            set tc to 0
            set lc to 0
            repeat with wi from 1 to wc
                set n to count of tabs of window wi
                set tc to tc + n
                repeat with ti from 1 to n
                    set u to URL of tab ti of window wi
                    if (u contains "://127.0.0.1:") or (u contains "://localhost:") then
                        set lc to lc + 1
                    end if
                    if \(condition) then
        \(activation)
                    end if
                end repeat
            end repeat
            return "none " & wc & " " & tc & " " & lc
        end tell
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 脚本执行结果。区分「没找到」与「跑不起来」——前者要换下一个浏览器试，
    /// 后者通常是没给自动化权限，继续试只会一路失败。
    enum ScriptResult: Equatable {
        case found
        /// 扫完没命中：窗口数、标签页数、其中本机地址（127.0.0.1/localhost）的页数。
        /// 0 窗口说明脚本没看到窗口（权限 / 窗口类型）；有本机页面却未命中说明端口不同。
        case notFound(windows: Int, tabs: Int, localPages: Int)
        case failed
    }

    /// 执行脚本并归类结果。
    static func runScript(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else { return .failed }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.warning("AppleScript 失败：\(errorInfo)", topic: "launcher")
            return .failed
        }
        return parse(result.stringValue ?? "")
    }

    /// 解析脚本返回：`found` 或 `none <窗口数> <标签页数> <本机页面数>`。
    static func parse(_ result: String) -> ScriptResult {
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "found" { return .found }
        let parts = text.split(separator: " ")
        guard parts.count == 4, parts[0] == "none",
              let windows = Int(parts[1]), let tabs = Int(parts[2]),
              let local = Int(parts[3]) else {
            return .notFound(windows: 0, tabs: 0, localPages: 0)
        }
        return .notFound(windows: windows, tabs: tabs, localPages: local)
    }
}
