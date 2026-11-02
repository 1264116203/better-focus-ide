// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// Keeps the most recent notifications (questions, permissions, turn-finished)
/// so the user can review "which apps reached out" by clicking the idle island.
final class HistoryController: ObservableObject {
    static let limit = 5

    @Published private(set) var entries: [HistoryEntry] = []

    /// Newest first, capped at `limit`.
    func remember(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Tapping a row jumps back to that entry's source app.
    func tapped(_ entry: HistoryEntry) {
        if let provider = entry.provider {
            IDELauncher.activateAsync(provider: provider, host: entry.host)
        }
    }

    // MARK: - Builders

    static func question(prompt: AgentQuestionPrompt, state: String) -> HistoryEntry {
        let tint = prompt.provider.tintRGB
        return HistoryEntry(
            title: prompt.question.header,
            body: prompt.question.question,
            state: state,
            source: prompt.provider.displayName,
            project: "",
            provider: prompt.provider.rawValue,
            host: nil,
            tintRGB: tint,
            timestamp: Date())
    }

    static func permission(request: PermissionRequest, state: String) -> HistoryEntry {
        let tint = request.provider.tintRGB
        return HistoryEntry(
            title: request.title,
            body: request.detail,
            state: state,
            source: request.provider.displayName,
            project: "",
            provider: request.provider.rawValue,
            host: nil,
            tintRGB: tint,
            timestamp: Date())
    }

    static func turn(notice: TurnNotice, state: String) -> HistoryEntry {
        let tint = AgentProvider(rawValue: notice.provider)?.tintRGB
            ?? (red: 0.29, green: 0.62, blue: 1.0)
        let source = notice.host?.name.isEmpty == false ? notice.host!.name : notice.providerName
        return HistoryEntry(
            title: notice.title,
            body: notice.body,
            state: state,
            source: source,
            project: notice.project,
            provider: notice.provider,
            host: notice.host,
            tintRGB: tint,
            timestamp: notice.arrivedAt)
    }
}
