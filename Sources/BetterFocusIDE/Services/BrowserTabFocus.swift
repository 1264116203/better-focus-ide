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
        for browser in candidates() {
            guard isRunning(browser.bundle) else { continue }
            switch runScript(script(for: browser, target: target)) {
            case .found:
                Log.info("已切到 \(browser.name) 里已打开的 \(target.host):\(target.port)",
                         topic: "launcher")
                return true
            case .notFound:
                // 这个浏览器里没有目标页面，换下一个候选。
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

    /// 默认浏览器优先，其余按固定顺序跟上——用户可能用非默认的那个开着页面。
    static func candidates(defaultBundle: String? = nil) -> [Browser] {
        let preferred = defaultBundle ?? defaultBrowserBundle()
        let all = allBrowsers
        guard let first = all.first(where: { $0.bundle == preferred }) else { return all }
        return [first] + all.filter { $0 != first }
    }

    /// 系统里打开 http 的默认应用。
    static func defaultBrowserBundle() -> String? {
        guard let probe = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
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
            repeat with wi from 1 to (count of windows)
                repeat with ti from 1 to (count of tabs of window wi)
                    set u to URL of tab ti of window wi
                    if \(condition) then
        \(activation)
                    end if
                end repeat
            end repeat
        end tell
        return "none"
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
        case notFound
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
        return result.stringValue == "found" ? .found : .notFound
    }
}
