// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// hook 在事件顶层上报的宿主应用身份信息。
struct HostInfo: Equatable {
    var bundle: String = ""
    var name: String = ""
    var path: String = ""
    var cwd: String = ""

    init() {}

    /// 从 socket 消息的 host 字典 + 可选 cwd 构造；缺失字段留空。
    init(from dict: [String: AnyCodableValue]?, cwd: String? = nil) {
        guard let dict else { return }
        bundle = dict["bundle"]?.stringValue ?? ""
        name = dict["name"]?.stringValue ?? ""
        path = dict["path"]?.stringValue ?? ""
        self.cwd = cwd ?? dict["cwd"]?.stringValue ?? ""
    }

    /// bundle/name/path 全空视为无有效宿主信息。
    var isEmpty: Bool { bundle.isEmpty && name.isEmpty && path.isEmpty }
}

/// 唤起产生某条通知的 IDE 窗口。
///
/// 用 AppleScript `tell application ... activate` 而非 `NSRunningApplication.activate`：
/// 从裸可执行文件启动的辅助应用缺乏 macOS 焦点保护所需的 bundle 身份，而 Apple Events
/// 是针对*目标*应用的身份来授权的。
enum IDELauncher {
    // 提供方 → bundle id / 应用名，按尝试顺序排列。
    static let ideBundles: [String: [String]] = [
        "qoder": ["com.qoder.ide", "com.aliyun.lingma.ide"],
        "opencode": ["ai.opencode.desktop"],
    ]
    static let ideNames: [String: [String]] = [
        "qoder": ["Qoder"],
        "opencode": ["OpenCode"],
    ]
    static let jetbrainsPrefix = "com.jetbrains."
    /// 表示"跑在终端里、没有可跳回的 GUI 窗口"的 bundle 集合。
    static let terminalBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
        "com.github.wez.wezterm", "com.microsoft.VSCode",
    ]

    /// 决定该为这条通知唤起哪个应用；返回 nil 表示没有可跳转的目标。
    static func target(for provider: String, host: HostInfo?) -> (bundles: [String], names: [String])? {
        let key = ideBundles[provider] != nil ? provider : "qoder"
        let bundles = ideBundles[key] ?? []
        let names = ideNames[key] ?? []
        let bundle = host?.bundle ?? ""
        if bundle.isEmpty { return (bundles, names) }
        // JetBrains 系：直接用上报的具体 bundle/名字（每个 IDE bundle 各不同）。
        if bundle.hasPrefix(jetbrainsPrefix) {
            let name = host?.name ?? ""
            return ([bundle], name.isEmpty ? [] : [name])
        }
        if bundles.contains(bundle) { return (bundles, names) }
        // Qoder 跑在终端里：无窗口可跳，返回 nil。
        if terminalBundles.contains(bundle) && provider == "qoder" { return nil }
        return (bundles, names)
    }

    /// 为该通知唤起 IDE。返回是否成功。
    @discardableResult
    static func activate(provider: String, host: HostInfo?) -> Bool {
        guard let targets = target(for: provider, host: host) else {
            Log.info("\(provider) 跑在终端里，没有可跳转的窗口", topic: "launcher")
            return false
        }
        // 1. 优先按运行中应用的 bundle id 激活。
        for bundle in targets.bundles {
            if isRunning(bundle: bundle), activateByAppleScript(bundle: bundle) {
                Log.info("已激活 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        // 2. 回退到应用名（中文区 bundle id 常常对不上）。
        for name in runningNames(matching: targets.names) {
            if activateByAppName(name: name) {
                Log.info("已按应用名激活 \(name)", topic: "launcher")
                return true
            }
        }
        // 3. 没在运行：直接启动它。
        for bundle in targets.bundles {
            if launch(bundle: bundle) {
                Log.info("已启动 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        Log.warning("未能唤起 \(provider)", topic: "launcher")
        return false
    }

    /// 在主线程之外执行唤起——AppleScript 首次编译约需 1 秒，会卡主线程。
    static func activateAsync(provider: String, host: HostInfo?) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = activate(provider: provider, host: host)
        }
    }

    // MARK: - 辅助方法

    /// 指定 bundle id 的应用是否正在运行。
    private static func isRunning(bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// 在运行中应用里挑出展示名匹配目标名的（去重、保序）。
    private static func runningNames(matching names: [String]) -> [String] {
        var found: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            let localizedName = app.localizedName ?? ""
            if !localizedName.isEmpty,
               names.contains(where: { localizedName.contains($0) }),
               !found.contains(localizedName) {
                found.append(localizedName)
            }
        }
        return found
    }

    /// 按 bundle id 用 AppleScript 激活。
    private static func activateByAppleScript(bundle: String) -> Bool {
        runAppleScript("tell application id \"\(bundle)\" to activate")
    }

    /// 按应用名用 AppleScript 激活（对名字里的反斜杠/引号做转义）。
    private static func activateByAppName(name: String) -> Bool {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return runAppleScript("tell application \"\(escaped)\" to activate")
    }

    /// 执行一段 AppleScript；出错时记录并返回 false。
    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.warning("AppleScript 失败：\(errorInfo)", topic: "launcher")
            return false
        }
        return true
    }

    /// 用 `/usr/bin/open -b` 启动指定 bundle 的应用，退出码 0 视为成功。
    private static func launch(bundle: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundle]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            Log.warning("启动 \(bundle) 失败：\(error)", topic: "launcher")
            return false
        }
    }
}
