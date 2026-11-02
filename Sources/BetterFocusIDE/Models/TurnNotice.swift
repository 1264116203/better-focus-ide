// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// A "turn finished" notification the agent emits when it completes a reply
/// (Qoder Stop / OpenCode session.idle). Shown as a banner the user can click
/// to jump back to the IDE that produced it.
struct TurnNotice: Equatable, Identifiable {
    let id = UUID()
    let provider: String
    let providerName: String
    let sessionID: String
    let title: String
    let body: String
    let project: String
    let host: HostInfo?
    let arrivedAt: Date
    /// Whether clicking jumps back to the IDE.
    let jumpEnabled: Bool
    /// Session was spawned by `qodercli` (a headless script), not the IDE the
    /// user is waiting on — record it to history but don't raise a banner.
    let fromCLI: Bool

    static func == (lhs: TurnNotice, rhs: TurnNotice) -> Bool { lhs.id == rhs.id }

    /// Parse a `turn_finished` socket message into a notice.
    static func parse(message: AgentSocketMessage) -> TurnNotice? {
        let provider = (message.provider).lowercased()
        let sessionID = message.sessionID
        let host = HostInfo(from: message.host,
                            cwd: message.payload?["cwd"]?.stringValue)
        let project = projectLeaf(from: host)
        let name = AgentProvider(rawValue: provider)?.displayName
            ?? provider.capitalized
        // Read the real session title from the transcript jsonl the hook reports.
        // Missing / unreadable collapses to empty, so we fall back to generic text.
        let transcriptPath = message.payload?["transcript_path"]?.stringValue
        let summary = Transcript.sessionSummary(path: transcriptPath, provider: provider)

        return TurnNotice(
            provider: provider,
            providerName: name,
            sessionID: sessionID,
            title: summary.title.isEmpty ? "\(name) 回复完成" : summary.title,
            body: summary.latest.isEmpty ? "点击跳转回 \(name)" : summary.latest,
            project: project,
            host: host.isEmpty ? nil : host,
            arrivedAt: Date(),
            jumpEnabled: Settings.shared.turnNotifyJump,
            fromCLI: summary.fromCLI
        )
    }

    /// The last path component of the project directory (the window title).
    private static func projectLeaf(from host: HostInfo) -> String {
        let cwd = host.cwd
        guard !cwd.isEmpty else { return "" }
        return (cwd as NSString).lastPathComponent
    }
}
