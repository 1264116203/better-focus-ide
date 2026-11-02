// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// Host app identity reported by the hook at the top level of an event.
struct HostInfo: Equatable {
    var bundle: String = ""
    var name: String = ""
    var path: String = ""
    var cwd: String = ""

    init() {}

    init(from dict: [String: AnyCodableValue]?, cwd: String? = nil) {
        guard let dict else { return }
        bundle = dict["bundle"]?.stringValue ?? ""
        name = dict["name"]?.stringValue ?? ""
        path = dict["path"]?.stringValue ?? ""
        self.cwd = cwd ?? dict["cwd"]?.stringValue ?? ""
    }

    var isEmpty: Bool { bundle.isEmpty && name.isEmpty && path.isEmpty }
}

/// Activates the IDE window that produced a notification.
///
/// Uses AppleScript `tell application ... activate` rather than
/// `NSRunningApplication.activate`, because an accessory app launched from a
/// bare executable lacks the bundle identity macOS focus-protection requires;
/// Apple Events are authorized against the *target* app's identity.
enum IDELauncher {
    // Provider → bundle ids / app names, in attempt order.
    static let ideBundles: [String: [String]] = [
        "qoder": ["com.qoder.ide", "com.aliyun.lingma.ide"],
        "opencode": ["ai.opencode.desktop"],
    ]
    static let ideNames: [String: [String]] = [
        "qoder": ["Qoder"],
        "opencode": ["OpenCode"],
    ]
    static let jetbrainsPrefix = "com.jetbrains."
    static let terminalBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
        "com.github.wez.wezterm", "com.microsoft.VSCode",
    ]

    /// Decide which app to raise for this notification; nil = nothing to jump to.
    static func target(for provider: String, host: HostInfo?) -> (bundles: [String], names: [String])? {
        let key = ideBundles[provider] != nil ? provider : "qoder"
        let bundles = ideBundles[key] ?? []
        let names = ideNames[key] ?? []
        let bundle = host?.bundle ?? ""
        if bundle.isEmpty { return (bundles, names) }
        if bundle.hasPrefix(jetbrainsPrefix) {
            let name = host?.name ?? ""
            return ([bundle], name.isEmpty ? [] : [name])
        }
        if bundles.contains(bundle) { return (bundles, names) }
        if terminalBundles.contains(bundle) && provider == "qoder" { return nil }
        return (bundles, names)
    }

    /// Raise the IDE for this notification. Returns whether it succeeded.
    @discardableResult
    static func activate(provider: String, host: HostInfo?) -> Bool {
        guard let targets = target(for: provider, host: host) else {
            Log.info("\(provider) 跑在终端里，没有可跳转的窗口", topic: "launcher")
            return false
        }
        // 1. Try bundle ids of running apps.
        for bundle in targets.bundles {
            if isRunning(bundle: bundle), activateByAppleScript(bundle: bundle) {
                Log.info("已激活 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        // 2. Fall back to app name (CN bundle ids often mismatch).
        for name in runningNames(matching: targets.names) {
            if activateByAppName(name: name) {
                Log.info("已按应用名激活 \(name)", topic: "launcher")
                return true
            }
        }
        // 3. Not running: launch it.
        for bundle in targets.bundles {
            if launch(bundle: bundle) {
                Log.info("已启动 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        Log.warning("未能唤起 \(provider)", topic: "launcher")
        return false
    }

    /// Activate off the main thread — AppleScript's first compile takes ~1s.
    static func activateAsync(provider: String, host: HostInfo?) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = activate(provider: provider, host: host)
        }
    }

    // MARK: - Helpers

    private static func isRunning(bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

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

    private static func activateByAppleScript(bundle: String) -> Bool {
        runAppleScript("tell application id \"\(bundle)\" to activate")
    }

    private static func activateByAppName(name: String) -> Bool {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return runAppleScript("tell application \"\(escaped)\" to activate")
    }

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
