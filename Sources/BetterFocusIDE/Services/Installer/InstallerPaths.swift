// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Central namespace for the hook / plugin integration. BetterFocusIDE keeps
/// its own directory so it can run side by side with Vorssaint without either
/// contending for the same socket / answer directory / hook group.
///
///   - Socket : ~/Library/Application Support/BetterFocusIDE/agent-events.sock
///   - Answers: ~/Library/Application Support/BetterFocusIDE/answers
///   - Hook   : ~/.qoder/hooks/betterfocus-notify.sh (+ betterfocus-hook.py)
///   - Plugin : ~/.config/opencode/plugins/betterfocus-notify.js
enum InstallerPaths {
    static let namespace = "BetterFocusIDE"
    /// Marker written into the installed Qoder hook group so install / uninstall
    /// only ever touches our own entries, never a colleague's hooks.
    static let marker = "betterfocus"

    static let home = NSHomeDirectory()

    static var appSupport: String {
        (home as NSString).appendingPathComponent("Library/Application Support/\(namespace)")
    }
    static var socketPath: String {
        (appSupport as NSString).appendingPathComponent("agent-events.sock")
    }
    static var answerDir: String {
        (appSupport as NSString).appendingPathComponent("answers")
    }
    static var settingsPath: String {
        (appSupport as NSString).appendingPathComponent("settings.json")
    }

    // Qoder
    static var qoderDir: String { (home as NSString).appendingPathComponent(".qoder") }
    static var qoderSettingsPath: String { (qoderDir as NSString).appendingPathComponent("settings.json") }
    static var qoderHooksDir: String { (qoderDir as NSString).appendingPathComponent("hooks") }
    static var qoderScriptPath: String { (qoderHooksDir as NSString).appendingPathComponent("betterfocus-notify.sh") }
    static var qoderHelperPath: String { (qoderHooksDir as NSString).appendingPathComponent("betterfocus-hook.py") }

    // OpenCode
    static var opencodePluginsDir: String {
        (home as NSString).appendingPathComponent(".config/opencode/plugins")
    }
    static var opencodePluginPath: String {
        (opencodePluginsDir as NSString).appendingPathComponent("betterfocus-notify.js")
    }

    /// Card-side wait limit; the Hook / Plugin poll timeouts track it so the
    /// card always expires before the platform does. Qoder additionally gives
    /// the script +60s of slack before killing the hook. Changing
    /// `agentWaitLimit` (needs=reinstall) re-runs the installers, which
    /// regenerate the hook with these values.
    static var questionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var permissionTimeoutSeconds: Int { Settings.shared.agentWaitLimit }
    static var hookTimeoutSeconds: Int { Settings.shared.agentWaitLimit + 60 }
}
