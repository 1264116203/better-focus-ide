// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Installs / uninstalls the Qoder hook that forwards permission requests,
/// AskUserQuestion prompts, turn-finished and session-end events to the
/// BetterFocusIDE island.
///
/// Two files are written: a tiny shell launcher (`betterfocus-notify.sh`) and
/// the Python body (`betterfocus-hook.py`) that owns the protocol. All JSON
/// work happens in Python so the hook needs no `jq`; python3 is already
/// required to reach the socket. The hook group is merged into
/// `~/.qoder/settings.json` under a marker so install / uninstall only ever
/// touch our own entries.
enum QoderHookInstaller {
    static let marker = InstallerPaths.marker

    // MARK: - Lifecycle

    static func install() throws {
        try ensureFile(path: InstallerPaths.qoderScriptPath,
                       content: scriptContent, executable: true)
        try ensureFile(path: InstallerPaths.qoderHelperPath,
                       content: helperContent, executable: false)
        try mergeSettings()
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: InstallerPaths.qoderScriptPath)
        try? FileManager.default.removeItem(atPath: InstallerPaths.qoderHelperPath)
        removeHookFromSettings()
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: InstallerPaths.qoderScriptPath)
    }

    // MARK: - Settings merge

    /// Adds — or refreshes — our own matcher groups inside `hooks`, leaving
    /// every other event and group untouched. Registers four events:
    ///   - PermissionRequest (matcher `*`): the real permission channel.
    ///   - PreToolUse (matcher `*`): legacy question entry; hook only handles
    ///     AskUserQuestion, everything else exits immediately.
    ///   - SessionEnd / Stop: fire-and-forget, short timeout so they never
    ///     hold up the session.
    static func mergedHooks(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooksAfterRemoval(hooks)

        func entry(matcher: String, timeout: Int) -> [String: Any] {
            [
                "_betterfocus_marker": marker,
                "matcher": matcher,
                "hooks": [[
                    "type": "command",
                    "command": InstallerPaths.qoderScriptPath,
                    "timeout": timeout,
                ]],
            ]
        }

        let specs: [(String, String, Int)] = [
            ("PreToolUse", "*", InstallerPaths.hookTimeoutSeconds),
            ("PermissionRequest", "*", InstallerPaths.hookTimeoutSeconds),
            ("SessionEnd", "*", 5),
            ("Stop", "*", 5),
        ]
        for (event, matcher, timeout) in specs {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let newEntry = entry(matcher: matcher, timeout: timeout)
            if let idx = groups.firstIndex(where: { isOurGroup($0) }) {
                groups[idx] = newEntry
            } else {
                groups.append(newEntry)
            }
            hooks[event] = groups
        }
        return hooks
    }

    static func hooksAfterRemoval(_ hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for event in ["PreToolUse", "PermissionRequest", "SessionEnd", "Stop"] {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isOurGroup($0) }
            if groups.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = groups }
        }
        return hooks
    }

    private static func isOurGroup(_ group: [String: Any]) -> Bool {
        if (group["_betterfocus_marker"] as? String) == marker { return true }
        // Legacy flat shape: no hooks array, command points at our script.
        if group["hooks"] is [Any] { return false }
        if let command = group["command"] as? String,
           command.contains("betterfocus-notify.sh") { return true }
        return false
    }

    private static func mergeSettings() throws {
        var settings = loadSettings()
        settings["hooks"] = mergedHooks(settings["hooks"] as? [String: Any] ?? [:])
        let dir = (InstallerPaths.qoderSettingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath),
                       options: .atomic)
    }

    private static func removeHookFromSettings() {
        var settings = loadSettings()
        guard !settings.isEmpty else { return }
        let merged = hooksAfterRemoval(settings["hooks"] as? [String: Any] ?? [:])
        if merged.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = merged }
        if let data = try? JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath),
                            options: .atomic)
        }
    }

    private static func loadSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    // MARK: - File write (idempotent)

    /// Writes content only when it differs, so repeated installs don't churn
    /// the mtime (which would make the platform think the script just changed).
    private static func ensureFile(path: String, content: String, executable: Bool) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let existing = try? String(contentsOfFile: path, encoding: .utf8),
           existing == content {
            if executable { chmod(path, 0o755) }
            return
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        if executable { chmod(path, 0o755) }
    }

    // MARK: - Templates

    /// The tiny shell launcher. Falls back to Qoder's own dialog when python3
    /// is missing so a request is never left waiting on a card nobody sees.
    static var scriptContent: String {
        """
        #!/bin/bash
        # BetterFocusIDE ↔ Qoder hook launcher. Forwards permission requests,
        # AskUserQuestion, turn-finished and session-end to the Dynamic Island.
        # All JSON work lives in betterfocus-hook.py beside it (no `jq` needed).

        SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
        PYTHON=$(command -v python3 || echo /usr/bin/python3)

        if [ ! -x "$PYTHON" ]; then
          printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"ask","permissionDecisionReason":"python3 is not installed; ask in the Qoder dialog."}}'
          exit 0
        fi

        exec "$PYTHON" "$SELF_DIR/betterfocus-hook.py"
        """
    }

    /// The Python hook body. Placeholders are substituted with this build's
    /// namespace paths so the hook points at BetterFocusIDE, not Vorssaint.
    static var helperContent: String {
        HelperTemplate.body
            .replacingOccurrences(of: "__SOCKET_PATH__", with: InstallerPaths.socketPath)
            .replacingOccurrences(of: "__ANSWER_DIR__", with: InstallerPaths.answerDir)
            .replacingOccurrences(of: "__SETTINGS_PATH__", with: InstallerPaths.settingsPath)
            .replacingOccurrences(of: "__QUESTION_TIMEOUT__", with: "\(InstallerPaths.questionTimeoutSeconds)")
            .replacingOccurrences(of: "__PERMISSION_TIMEOUT__", with: "\(InstallerPaths.permissionTimeoutSeconds)")
    }
}
