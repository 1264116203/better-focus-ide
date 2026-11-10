// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 可以安装 hook / 插件的宿主，以及「这台 Mac 上有没有它」。
///
/// 安装菜单只列出 `isPresent == true` 的项。没装的宿主不建配置目录。
enum HookInstallCatalog {
    struct Host {
        let id: String
        let label: String
        let isPresent: () -> Bool
        let install: () throws -> Void
    }

    /// 顺序就是勾选列表和安装汇总的顺序。
    static let all: [Host] = [
        Host(id: "qoder", label: "Qoder",
             isPresent: qoderPresent,
             install: { try QoderHookInstaller.install() }),
        Host(id: "opencode", label: "OpenCode",
             isPresent: opencodePresent,
             install: { try OpenCodePluginInstaller.install() }),
        Host(id: "cursor", label: "Cursor",
             isPresent: cursorPresent,
             install: { try CursorHookInstaller.install() }),
        Host(id: "workbuddy", label: "WorkBuddy",
             isPresent: workbuddyPresent,
             install: { try WorkBuddyHookInstaller.install() }),
        Host(id: "claude", label: "Claude Code",
             isPresent: claudePresent,
             install: { try ClaudeCodeHookInstaller.install() }),
        Host(id: "chatgpt", label: "ChatGPT",
             isPresent: { CodexHookInstaller.isPresent },
             install: { try CodexHookInstaller.install() }),
        Host(id: "trae-cn", label: "Trae CN",
             isPresent: { TraeHookInstaller.Flavor.cn.isPresent },
             install: { try TraeHookInstaller.install(.cn) }),
        Host(id: "trae", label: "Trae",
             isPresent: { TraeHookInstaller.Flavor.international.isPresent },
             install: { try TraeHookInstaller.install(.international) }),
        Host(id: "kimi", label: "Kimi",
             isPresent: { KimiHookInstaller.isPresent },
             install: { try KimiHookInstaller.install() }),
        Host(id: "qoder-cn", label: "Qoder CN",
             isPresent: { QoderCnHookInstaller.isPresent },
             install: { try QoderCnHookInstaller.install() }),
        Host(id: "copilot", label: "GitHub Copilot",
             isPresent: { CopilotHookInstaller.isPresent },
             install: { try CopilotHookInstaller.install() }),
    ]

    /// 本机已经安装的受支持宿主。
    static func present() -> [Host] {
        all.filter { $0.isPresent() }
    }

    /// 只安装勾选的 id。不在目录里、或本机没装的 id 直接跳过。
    static func install(_ ids: [String]) -> String {
        let wanted = Set(ids)
        var lines: [String] = []
        for host in all where wanted.contains(host.id) && host.isPresent() {
            do {
                try host.install()
                lines.append("✓ \(host.label) 已安装")
            } catch {
                lines.append("✗ \(host.label) 失败：\(error.localizedDescription)")
            }
        }
        if lines.isEmpty {
            lines.append("没有安装任何宿主")
        }
        Log.info("install hooks: " + lines.joined(separator: " | "), topic: "install")
        return lines.joined(separator: "\n")
    }

    // MARK: - 是否装在本机

    private static func appInstalled(_ bundle: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
    }

    private static func qoderPresent() -> Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.qoderDir)
            || appInstalled("com.qoder.ide")
            || appInstalled("com.qoder.app")
    }

    private static func opencodePresent() -> Bool {
        let root = (InstallerPaths.opencodePluginsDir as NSString).deletingLastPathComponent
        return InstallerPaths.hostDirectoryExists(root)
            || appInstalled("ai.opencode.desktop")
            || commandExists("opencode")
    }

    private static func cursorPresent() -> Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.cursorDir)
            || appInstalled("com.todesktop.230313mzl4w4u92")
            || appInstalled("com.cursor")
    }

    private static func workbuddyPresent() -> Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.workbuddyDir)
            || appInstalled("com.tencent.workbuddy.mac")
            || appInstalled("ai.workbuddy")
            || appInstalled("com.workbuddy.workbuddy-ai")
    }

    private static func claudePresent() -> Bool {
        InstallerPaths.hostDirectoryExists(InstallerPaths.claudeDir)
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
            || commandExists("claude")
    }

    private static func commandExists(_ name: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fm = FileManager.default
        return path.split(separator: ":").contains { dir in
            fm.isExecutableFile(atPath: (String(dir) as NSString).appendingPathComponent(name))
        }
    }
}

/// 勾选面板的状态。每次打开菜单都重新检测，默认全部勾上。
final class HookInstallPickerModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let label: String
        var selected: Bool
    }

    @Published var items: [Item] = []

    func reload() {
        items = HookInstallCatalog.present().map {
            Item(id: $0.id, label: $0.label, selected: true)
        }
    }

    var selectedIDs: [String] {
        items.filter(\.selected).map(\.id)
    }
}
