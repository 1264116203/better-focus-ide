// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// One entry in the recent-notifications history: what happened, which app
/// produced it, and how to jump back. Kept in memory only (last N entries).
struct HistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
    /// Result line, e.g. "已回答" / "已拒绝" / "回复完成".
    let state: String
    /// Source display name (host app name or provider name).
    let source: String
    /// Project leaf shown as the faint meta text.
    let project: String
    let provider: String?
    let host: HostInfo?
    let tintRGB: (red: Double, green: Double, blue: Double)
    let timestamp: Date

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }

    var clockText: String {
        HistoryEntry.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// First letter of the source, uppercased — the badge glyph.
    var badgeText: String {
        let base = source.isEmpty ? "?" : source
        return String(base.prefix(1)).uppercased()
    }
}
