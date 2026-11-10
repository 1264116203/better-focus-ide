// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 可以安装 hook / 插件的宿主，以及「这台 Mac 上有没有它」。
///
/// 安装菜单只列出本机应用列表里已经有的、而且受支持的应用。
/// 配置目录不算：安装器自己会把目录建出来。
enum HookInstallCatalog {
    struct Host {
        let id: String
        let label: String
        /// 勾选行下面的一句说明：接到岛上之后用户需要知道的事。
        let hint: String
        let isPresent: () -> Bool
        let install: () throws -> Void
    }

    /// 顺序就是勾选列表和安装汇总的顺序。
    static let all: [Host] = [
        Host(id: "qoder", label: "Qoder",
             hint: "桌面应用。提问可在岛上作答，装好后重启才生效。",
             isPresent: { isApplicationPresent(id: "qoder") },
             install: { try QoderHookInstaller.install() }),
        Host(id: "qoder-ide", label: "Qoder IDE",
             hint: "提问可在岛上作答。装好后重启 Qoder IDE 才生效。",
             isPresent: { isApplicationPresent(id: "qoder-ide") },
             install: { try QoderHookInstaller.install() }),
        Host(id: "qoder-cli", label: "Qoder CLI",
             hint: "终端里的 Qoder。提问可在岛上作答，和 IDE 不是同一个应用。",
             isPresent: { cliPresent(.english) },
             install: { try QoderHookInstaller.install() }),
        Host(id: "qoder-cn", label: "Qoder CN",
             hint: "国内版桌面应用。写入独立目录，装好后重启才生效。",
             isPresent: { isApplicationPresent(id: "qoder-cn") },
             install: { try QoderCnHookInstaller.install() }),
        Host(id: "qoder-cn-ide", label: "Qoder CN IDE",
             hint: "提问可在岛上作答。写入独立目录，装好后重启才生效。",
             isPresent: { isApplicationPresent(id: "qoder-cn-ide") },
             install: { try QoderCnHookInstaller.install() }),
        Host(id: "qoder-cn-cli", label: "Qoder CN CLI",
             hint: "终端里的国内版。写入独立目录，和 IDE 不是同一个应用。",
             isPresent: { cliPresent(.cn) },
             install: { try QoderCnHookInstaller.install() }),
        Host(id: "opencode", label: "OpenCode",
             hint: "提问可在岛上作答。没有权限提醒，也没有会话结束。",
             isPresent: { isApplicationPresent(id: "opencode") },
             install: { try OpenCodePluginInstaller.install() }),
        Host(id: "cursor", label: "Cursor",
             hint: "通知回合完成、会话结束和权限申请。批准仍在 Cursor 里，点通知跳回去。",
             isPresent: { isApplicationPresent(id: "cursor") },
             install: { try CursorHookInstaller.install() }),
        Host(id: "workbuddy", label: "WorkBuddy",
             hint: "提问只提醒，点一下跳回去答。装好后要重开当前会话。",
             isPresent: { isApplicationPresent(id: "workbuddy") },
             install: { try WorkBuddyHookInstaller.install() }),
        Host(id: "claude", label: "Claude Code",
             hint: "提问可在岛上作答，权限只提醒。",
             isPresent: { isApplicationPresent(id: "claude") },
             install: { try ClaudeCodeHookInstaller.install() }),
        Host(id: "chatgpt", label: "ChatGPT",
             hint: "没有提问卡。装好后要在 ChatGPT 里把 hook 信任一次。",
             isPresent: { isApplicationPresent(id: "chatgpt") },
             install: { try CodexHookInstaller.install() }),
        Host(id: "trae-cn", label: "Trae CN",
             hint: "提问可在岛上作答。没有会话结束，也没有待办。",
             isPresent: { isApplicationPresent(id: "trae-cn") },
             install: { try TraeHookInstaller.install(.cn) }),
        Host(id: "trae", label: "Trae",
             hint: "提问可在岛上作答。没有会话结束，也没有待办。",
             isPresent: { isApplicationPresent(id: "trae") },
             install: { try TraeHookInstaller.install(.international) }),
        Host(id: "kimi", label: "Kimi",
             hint: "提问可在岛上作答，权限只提醒。",
             isPresent: { isApplicationPresent(id: "kimi") },
             install: { try KimiHookInstaller.install() }),
        Host(id: "copilot", label: "GitHub Copilot",
             hint: "提问可在岛上作答，权限只提醒。",
             isPresent: { isApplicationPresent(id: "copilot") },
             install: { try CopilotHookInstaller.install() }),
        Host(id: "jetbrains-acp", label: "JetBrains ACP",
             hint: "ACP 会话只提醒。回合、权限和待办在岛上亮，批准仍在 IDE 里。装好后重启 IDE。",
             isPresent: { AcpBridgeInstaller.isHostPresent() },
             install: { try AcpBridgeInstaller.install() }),
    ]

    /// 每个勾选项对应的应用 bundle id。系统应用列表里有其中任意一个才显示。
    /// Qoder 六个产品各算各的：桌面应用、IDE、CLI 不共用一个勾选。
    /// CLI 没有 bundle，走 `cliPresent`。
    static let applicationBundles: [String: [String]] = [
        "qoder": ["com.qoder.app"],
        "qoder-ide": ["com.qoder.ide"],
        "qoder-cli": [],
        "opencode": ["ai.opencode.desktop"],
        "cursor": ["com.todesktop.230313mzl4w4u92", "com.cursor"],
        "workbuddy": ["com.tencent.workbuddy.mac", "ai.workbuddy", "com.workbuddy.workbuddy-ai"],
        "claude": ["com.anthropic.claudefordesktop"],
        "chatgpt": ["com.openai.codex"],
        "trae-cn": ["cn.trae.app"],
        "trae": ["com.trae.app"],
        "kimi": ["com.moonshot.kimichat.kmp.mac"],
        "qoder-cn": [],
        "qoder-cn-ide": ["com.aliyun.lingma.ide"],
        "qoder-cn-cli": [],
        "copilot": ["com.github.githubapp"],
        "jetbrains-acp": AcpBridgeInstaller.jetbrainsBundles,
    ]

    /// 终端里的 Qoder。IDE 包内的 `bin/qoder` 只是 IDE 的启动脚本，不算 CLI。
    enum CLIKind {
        case english
        case cn
    }

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

    /// `installed` 用来在测试里换掉系统应用列表。
    static func isApplicationPresent(id: String, installed: (String) -> Bool = launchServicesHas) -> Bool {
        (applicationBundles[id] ?? []).contains(where: installed)
    }

    private static func launchServicesHas(_ bundle: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
    }

    /// 英文 CLI 与国内版 CLI 分开认。IDE 应用里自带的脚本不算。
    static func matchesCLI(path: String, kind: CLIKind) -> Bool {
        let name = (path as NSString).lastPathComponent
        let insideIDE = path.contains("/Qoder IDE.app/") || path.contains("/Qoder CN.app/")
        if insideIDE { return false }
        switch kind {
        case .english:
            guard name == "qoder" || name == "qodercli" else { return false }
            return !path.contains("/.qoder-cn/")
        case .cn:
            if name == "qoder-cn" || name == "qodercn" { return true }
            guard name == "qoder" || name == "qodercli" else { return false }
            return path.contains("/.qoder-cn/")
        }
    }

    private static func cliPresent(_ kind: CLIKind) -> Bool {
        let names = ["qoder", "qodercli", "qoder-cn", "qodercn"]
        let home = NSHomeDirectory()
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin",
                       (home as NSString).appendingPathComponent(".local/bin"),
                       (home as NSString).appendingPathComponent(".qoder/bin"),
                       (home as NSString).appendingPathComponent(".qoder-cn/bin")]
        where !dirs.contains(extra) {
            dirs.append(extra)
        }
        let fm = FileManager.default
        for dir in dirs {
            for name in names {
                let path = (dir as NSString).appendingPathComponent(name)
                guard fm.isExecutableFile(atPath: path), matchesCLI(path: path, kind: kind) else { continue }
                return true
            }
        }
        return false
    }
}

/// 勾选面板的状态。菜单只列已安装的，并默认勾上。
/// 引导页列出全部受支持的 IDE，没安装的不勾选。
final class HookInstallPickerModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let label: String
        let hint: String
        /// 本机有没有这个应用。没有时引导页仍展示，但不勾选。
        var installed: Bool
        var selected: Bool
    }

    @Published var items: [Item] = []

    /// 右键安装菜单：只列出已安装的，默认全部勾上。
    func reload() {
        items = HookInstallCatalog.present().map {
            Item(id: $0.id, label: $0.label, hint: $0.hint, installed: true, selected: true)
        }
    }

    /// 引导页：受支持的都展示。已安装的勾上，没安装的不勾。
    func reloadForGuide() {
        items = HookInstallCatalog.all.map { host in
            let installed = host.isPresent()
            return Item(id: host.id, label: host.label, hint: host.hint,
                        installed: installed, selected: installed)
        }
    }

    var selectedIDs: [String] {
        items.filter(\.selected).map(\.id)
    }
}
