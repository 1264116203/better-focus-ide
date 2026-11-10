// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import ApplicationServices
import Foundation

/// 本应用向系统要的「自动化」授权。
///
/// 点击通知后激活 IDE、把浏览器里已经打开的标签页带到前台，都是通过
/// Apple Events 完成的。系统按目标应用分别授权，没有一个总开关。
/// 查询用 `AEDeterminePermissionToAutomateTarget` 且不向用户弹窗。
enum AutomationPermission {
    /// 窗口抬升和菜单定位都经过系统事件。
    static let systemEventsBundle = "com.apple.systemevents"

    /// 单个目标当前的授权结果。
    enum Grant: Equatable {
        /// 用户已经允许。
        case allowed
        /// 用户已经拒绝，只能到系统设置里改。
        case denied
        /// 还没问过。第一次跳转时系统会弹授权。
        case notDetermined
        /// 目标进程没在跑，系统不回答是否已授权。
        case notRunning
        /// 查询失败。
        case unknown

        /// 设置页上的状态文案。
        var label: String {
            switch self {
            case .allowed: return "已允许"
            case .denied: return "已拒绝"
            case .notDetermined: return "尚未询问"
            case .notRunning: return "未在运行"
            case .unknown: return "无法确认"
            }
        }
    }

    /// 目标属于哪一类，只用于设置页分组。
    enum Kind: String, Equatable {
        case system = "系统事件"
        case ide = "IDE"
        case terminal = "终端"
        case browser = "浏览器"
    }

    /// 一个会收到 Apple Event 的目标应用。
    struct Target: Equatable, Identifiable {
        let bundle: String
        let name: String
        let kind: Kind
        var id: String { bundle }
    }

    /// 一条带授权结果的目标。
    struct Row: Equatable, Identifiable {
        let target: Target
        let grant: Grant
        var id: String { target.id }
    }

    /// 把 `AEDeterminePermissionToAutomateTarget` 的返回值收成授权结果。
    ///
    /// - `0` 已允许
    /// - `-1743` `errAEEventNotPermitted` 已拒绝
    /// - `-1744` `errAEEventWouldRequireUserConsent` 尚未询问
    /// - `-600` `procNotFound` 目标进程不在
    static func interpret(_ status: OSStatus) -> Grant {
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .notRunning
        default: return .unknown
        }
    }

    /// 本机已安装、且跳转时可能被控制的应用。系统事件始终在第一行。
    static func installedTargets() -> [Target] {
        var seen = Set<String>()
        var rows: [Target] = []
        func add(bundle: String, name: String, kind: Kind, required: Bool = false) {
            guard seen.insert(bundle).inserted else { return }
            guard required || isInstalled(bundle) else { return }
            let resolved = name.isEmpty ? fallbackName(bundle) : name
            rows.append(Target(bundle: bundle, name: resolved, kind: kind))
        }

        add(bundle: systemEventsBundle, name: "系统事件", kind: .system, required: true)

        let ides = IDELauncher.ideBundles.values.flatMap { $0 }.sorted()
        for bundle in ides {
            add(bundle: bundle,
                name: HostInfo.bundleIdDisplayName[bundle] ?? "",
                kind: .ide)
        }
        for (bundle, name) in TerminalHost.bundles.sorted(by: { $0.value < $1.value }) {
            add(bundle: bundle, name: name, kind: .terminal)
        }
        for browser in BrowserTabFocus.allBrowsers {
            add(bundle: browser.bundle, name: browser.name, kind: .browser)
        }
        return rows
    }

    /// 查询每个已安装目标的授权。不弹系统对话框。
    static func evaluate() -> [Row] {
        installedTargets().map { target in
            Row(target: target, grant: grant(for: target.bundle))
        }
    }

    /// 打开「系统设置 → 隐私与安全性 → 自动化」。
    @discardableResult
    static func openSettings() -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return true }
        }
        return false
    }

    /// 查询某一个目标。`askUserIfNeeded` 必须是 false，设置页只读状态。
    static func grant(for bundle: String) -> Grant {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        return interpret(status)
    }

    private static func isInstalled(_ bundle: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
    }

    private static func fallbackName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return bundle
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

/// 设置页上的授权列表。查询放到后台，避免卡住面板。
final class AutomationPermissionReport: ObservableObject {
    @Published private(set) var rows: [AutomationPermission.Row] = []
    @Published private(set) var checking = false

    func refresh() {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = AutomationPermission.evaluate()
            DispatchQueue.main.async {
                self.rows = rows
                self.checking = false
            }
        }
    }
}
