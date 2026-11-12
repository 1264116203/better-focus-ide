// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 把 Qoder 终端命令的「始终允许」写进界面配置和执行端配置。
///
/// 允许列表只在终端模式为 `askEveryTime` 时才会让后续同类命令不再询问。
/// 这里不改运行模式。任一份文件缺失、顶层不是对象，或命令名不能安全落盘时，
/// 返回 `.downgraded`，调用方把这一次当成「允许」。
enum QoderCommandAllowList {
    /// 写入结果。`remembered` 的字符串是落盘的命令名。
    enum Outcome: Equatable {
        case remembered(String)
        case downgraded
    }

    /// 测试注入路径。非 nil 时不再碰用户目录。
    static var locationsForTesting: ((AgentProvider) -> (ui: URL, runtime: URL)?)?

    private static let defaultDenyList = "rm,mv,sudo,wget,curl,chown,remove-item"

    /// 取命令的第一个词。含逗号或引号、或命中禁用列表时返回 nil。
    static func token(from command: String, denyList: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let token = String(first)
        guard !token.isEmpty else { return nil }
        if token.contains(",") || token.contains("\"") || token.contains("'") { return nil }
        let denied = denyList.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if denied.contains(token.lowercased()) { return nil }
        return token
    }

    /// 把命令名追加进逗号分隔列表。已有同名项（忽略大小写）则不重复。
    static func merging(_ existing: String, token: String) -> String {
        var parts = existing.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if parts.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) {
            return parts.joined(separator: ",")
        }
        parts.append(token)
        return parts.joined(separator: ",")
    }

    /// 按产品选择两份配置。Qoder CN 用自己的 Application Support 目录。
    static func locations(for provider: AgentProvider) -> (ui: URL, runtime: URL)? {
        if let locationsForTesting { return locationsForTesting(provider) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        switch provider {
        case .qoder, .qoder_ide, .qoder_cli:
            return (support.appendingPathComponent("Qoder/User/settings.json"),
                    support.appendingPathComponent("Qoder/SharedClientCache/cache/app-config.json"))
        case .qoder_cn, .qoder_cn_ide, .qoder_cn_cli:
            return (support.appendingPathComponent("QoderCN/User/settings.json"),
                    support.appendingPathComponent("QoderCN/SharedClientCache/cache/app-config.json"))
        default:
            return nil
        }
    }

    /// 把这条命令记入两份允许列表。失败时两份都尽量恢复原样。
    static func remember(command: String, provider: AgentProvider) -> Outcome {
        guard let urls = locations(for: provider) else { return .downgraded }
        let fm = FileManager.default
        guard fm.fileExists(atPath: urls.ui.path),
              fm.fileExists(atPath: urls.runtime.path) else { return .downgraded }
        guard let uiData = try? Data(contentsOf: urls.ui),
              let runtimeData = try? Data(contentsOf: urls.runtime),
              var ui = jsonObject(uiData),
              var runtime = jsonObject(runtimeData) else { return .downgraded }
        guard var app = ui["app"] as? [String: Any] else { return .downgraded }

        let deny = denyList(app: app, runtime: runtime)
        guard let token = token(from: command, denyList: deny) else { return .downgraded }

        let uiList = app["configChatCommandAllowlist"] as? String ?? ""
        let runtimeList = runtime["commandAllowList"] as? String ?? ""
        app["configChatCommandAllowlist"] = merging(uiList, token: token)
        ui["app"] = app
        runtime["commandAllowList"] = merging(runtimeList, token: token)

        guard let newUI = try? JSONSerialization.data(withJSONObject: ui, options: [.prettyPrinted]),
              let newRuntime = try? JSONSerialization.data(withJSONObject: runtime, options: [.prettyPrinted])
        else { return .downgraded }

        do {
            try newUI.write(to: urls.ui, options: .atomic)
            do {
                try newRuntime.write(to: urls.runtime, options: .atomic)
            } catch {
                try? uiData.write(to: urls.ui, options: .atomic)
                Log.error("Qoder 执行端允许列表写入失败：\(error.localizedDescription)", topic: "permission")
                return .downgraded
            }
        } catch {
            Log.error("Qoder 界面允许列表写入失败：\(error.localizedDescription)", topic: "permission")
            return .downgraded
        }
        return .remembered(token)
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func denyList(app: [String: Any], runtime: [String: Any]) -> String {
        if let deny = app["configChatCommandDenyList"] as? String, !deny.isEmpty { return deny }
        if let deny = runtime["commandDenyList"] as? String, !deny.isEmpty { return deny }
        return defaultDenyList
    }
}
