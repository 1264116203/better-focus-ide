// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 把 JetBrains ACP 登记里的代理命令换成 stdio 桥。
///
/// 桥原样转发 JSON-RPC，只把回合、权限、提问、待办译成岛上已有的事件。
/// 原始命令记在 sidecar 里，不写进 `installed.json` 的自定义字段——
/// IDE 更新代理时会整段覆盖登记，下次安装再按新命令套回去。
enum AcpBridgeInstaller {
    static let scriptName = "acp-bridge.py"

    enum Failure: LocalizedError {
        case sourceMissing
        case registryMissing
        case noAgent

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "找不到 ACP 桥脚本"
            case .registryMissing:
                return "还没有 ACP 代理登记。先在 IDE 里打开一次 AI 会话，再安装"
            case .noAgent:
                return "登记里没有本机平台的 ACP 代理"
            }
        }
    }

    static var platformKey: String {
        #if arch(arm64)
        return "darwin-aarch64"
        #else
        return "darwin-x86_64"
        #endif
    }

    static let jetbrainsBundles = [
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.webstorm",
        "com.jetbrains.goland", "com.jetbrains.rider", "com.jetbrains.clion",
        "com.jetbrains.phpstorm", "com.jetbrains.rubymine", "com.jetbrains.datagrip",
        "com.jetbrains.fleet",
    ]

    static func install(registryPath: String = InstallerPaths.jetbrainsAcpRegistry,
                        scriptPath: String = InstallerPaths.acpBridgeScript,
                        sidecarPath: String = InstallerPaths.acpBridgeSidecar,
                        platform: String = platformKey) throws {
        let source = try loadSource()
        guard FileManager.default.fileExists(atPath: registryPath) else {
            throw Failure.registryMissing
        }
        var registry = HookInstallerSupport.loadJSON(registryPath)
        var sidecar = HookInstallerSupport.loadJSON(sidecarPath)
        let beforeRegistry = canonical(registry)
        let beforeSidecar = canonical(sidecar)
        let wrapped = wrap(&registry, sidecar: &sidecar, scriptPath: scriptPath, platform: platform)
        guard wrapped > 0 else { throw Failure.noAgent }
        try HookInstallerSupport.ensureFile(path: scriptPath, content: source, executable: true)
        if canonical(sidecar) != beforeSidecar {
            try HookInstallerSupport.writeJSON(sidecar, to: sidecarPath)
        }
        if canonical(registry) != beforeRegistry {
            try HookInstallerSupport.writeJSON(registry, to: registryPath)
        }
    }

    static func uninstall(registryPath: String = InstallerPaths.jetbrainsAcpRegistry,
                          scriptPath: String = InstallerPaths.acpBridgeScript,
                          sidecarPath: String = InstallerPaths.acpBridgeSidecar,
                          platform: String = platformKey) {
        var registry = HookInstallerSupport.loadJSON(registryPath)
        let sidecar = HookInstallerSupport.loadJSON(sidecarPath)
        if restore(&registry, sidecar: sidecar, scriptPath: scriptPath, platform: platform) {
            try? HookInstallerSupport.writeJSON(registry, to: registryPath)
        }
        try? FileManager.default.removeItem(atPath: scriptPath)
        try? FileManager.default.removeItem(atPath: sidecarPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: InstallerPaths.acpBridgeScript)
    }

    static func isRegistered(registryPath: String = InstallerPaths.jetbrainsAcpRegistry,
                             platform: String = platformKey) -> Bool {
        let registry = HookInstallerSupport.loadJSON(registryPath)
        guard let agents = registry["agents"] as? [String: Any] else { return false }
        for (_, raw) in agents {
            guard let cmd = command(in: raw, platform: platform) else { continue }
            if cmd.contains(scriptName) { return true }
        }
        return false
    }

    static func isHostPresent(registryPath: String = InstallerPaths.jetbrainsAcpRegistry,
                              installed: (String) -> Bool = {
                                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                              }) -> Bool {
        if FileManager.default.fileExists(atPath: registryPath) { return true }
        return jetbrainsBundles.contains(where: installed)
    }

    /// 套上桥。已经套过的代理不改 sidecar 里的原始命令。返回套上的个数。
    @discardableResult
    static func wrap(_ registry: inout [String: Any], sidecar: inout [String: Any],
                     scriptPath: String, platform: String) -> Int {
        guard var agents = registry["agents"] as? [String: Any] else { return 0 }
        var saved = sidecar["agents"] as? [String: Any] ?? [:]
        var count = 0
        for (id, raw) in agents {
            guard var entry = raw as? [String: Any] else { continue }
            guard var slot = binarySlot(&entry, platform: platform) else { continue }
            let cmd = slot["cmd"] as? String ?? ""
            guard !cmd.isEmpty else { continue }
            let args = stringList(slot["args"])
            if cmd.contains(scriptName) {
                slot["cmd"] = scriptPath
                slot["args"] = [id]
            } else {
                var record: [String: Any] = ["cmd": cmd, "args": args]
                if let env = slot["env"] { record["env"] = env }
                saved[id] = record
                slot["cmd"] = scriptPath
                slot["args"] = [id]
            }
            writeSlot(slot, into: &entry, platform: platform)
            agents[id] = entry
            count += 1
        }
        sidecar["agents"] = saved
        registry["agents"] = agents
        return count
    }

    /// 把本机平台的命令还回去。别的平台、别的字段不动。
    @discardableResult
    static func restore(_ registry: inout [String: Any], sidecar: [String: Any],
                        scriptPath: String, platform: String) -> Bool {
        guard var agents = registry["agents"] as? [String: Any] else { return false }
        let saved = sidecar["agents"] as? [String: Any] ?? [:]
        var changed = false
        for (id, raw) in agents {
            guard var entry = raw as? [String: Any] else { continue }
            guard var slot = binarySlot(&entry, platform: platform) else { continue }
            let cmd = slot["cmd"] as? String ?? ""
            guard cmd.contains(scriptName) else { continue }
            guard let record = saved[id] as? [String: Any],
                  let original = record["cmd"] as? String, !original.isEmpty else { continue }
            slot["cmd"] = original
            slot["args"] = stringList(record["args"])
            if let env = record["env"] { slot["env"] = env }
            writeSlot(slot, into: &entry, platform: platform)
            agents[id] = entry
            changed = true
        }
        if changed { registry["agents"] = agents }
        return changed
    }

    // MARK: - 脚本正文

    static func loadSource() throws -> String {
        if let text = resourceText(), text.contains("session/update") { return text }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/acp-bridge.py")
        if let text = try? String(contentsOf: dev, encoding: .utf8),
           text.contains("session/update") {
            return text
        }
        throw Failure.sourceMissing
    }

    private static func resourceText() -> String? {
        let bundleName = "BetterFocusIDE_BetterFocusIDE.bundle"
        var roots: [URL] = []
        if let path = Bundle.main.resourceURL?.appendingPathComponent(bundleName) {
            roots.append(path)
        }
        roots.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(bundleName))
        if let exec = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent(bundleName) {
            roots.append(exec)
        }
        for root in roots {
            let file = root.appendingPathComponent(scriptName)
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    // MARK: - JSON

    private static func canonical(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    private static func command(in raw: Any, platform: String) -> String? {
        guard let entry = raw as? [String: Any],
              let agent = entry["agent"] as? [String: Any],
              let distribution = agent["distribution"] as? [String: Any],
              let binary = distribution["binary"] as? [String: Any],
              let slot = binary[platform] as? [String: Any] else { return nil }
        return slot["cmd"] as? String
    }

    private static func binarySlot(_ entry: inout [String: Any], platform: String) -> [String: Any]? {
        guard let agent = entry["agent"] as? [String: Any],
              let distribution = agent["distribution"] as? [String: Any],
              let binary = distribution["binary"] as? [String: Any],
              let slot = binary[platform] as? [String: Any] else { return nil }
        return slot
    }

    private static func writeSlot(_ slot: [String: Any], into entry: inout [String: Any],
                                  platform: String) {
        guard var agent = entry["agent"] as? [String: Any],
              var distribution = agent["distribution"] as? [String: Any],
              var binary = distribution["binary"] as? [String: Any] else { return }
        binary[platform] = slot
        distribution["binary"] = binary
        agent["distribution"] = distribution
        entry["agent"] = agent
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        return []
    }
}
