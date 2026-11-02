// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// Manages the transient "turn finished" banner: debounces per-session repeats,
/// skips while a card awaits the user, and auto-dismisses after a duration.
final class NoticeController: ObservableObject {
    @Published private(set) var notice: TurnNotice?

    /// Called when a banner should appear / disappear (drives island expand).
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// Called for every finished turn so it lands in history — even a CLI
    /// session that raises no banner is still recorded for later review.
    var onRemember: ((TurnNotice) -> Void)?

    /// Suppresses the banner while an interactive card is on screen.
    var hasPendingCard: () -> Bool = { false }
    /// When true the banner is pinned open and must not auto-dismiss.
    var isPinned: () -> Bool = { false }

    /// Last notice time per session, for debounce.
    private var lastNoticeAt: [String: Date] = [:]

    var hasActiveNotice: Bool { notice != nil }
    /// Total items — drives the collapsed pending dot.
    var count: Int { notice != nil ? 1 : 0 }
    /// Provider tint for the pending dot.
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let p = notice?.provider,
              let provider = AgentProvider(rawValue: p) else { return nil }
        let rgb = provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - Event entry

    func handleTurnFinished(message: AgentSocketMessage) {
        let settings = Settings.shared
        guard settings.turnNotifyEnabled else { return }

        let sessionID = message.sessionID
        let now = Date()
        // Debounce: several sub-sessions report idle back to back.
        if let last = lastNoticeAt[sessionID],
           now.timeIntervalSince(last) < settings.notifyBannerDuration * 0.4 {
            return
        }
        // Don't cover a card that is waiting on the user.
        if hasPendingCard() { return }

        guard let parsed = TurnNotice.parse(message: message) else { return }
        if lastNoticeAt.count > 32 { lastNoticeAt.removeAll() }
        lastNoticeAt[sessionID] = now

        // Every finished turn is recorded to history first. A `qodercli` session
        // (headless autocommit-style scripts) leaves a trace but never steals the
        // screen — its "user input" is a piped diff, not something the user waits on.
        onRemember?(parsed)
        if parsed.fromCLI { return }

        show(parsed)
    }

    // MARK: - Present / dismiss

    private func show(_ newNotice: TurnNotice) {
        notice = newNotice
        onPresent?()
        FeedbackService.onArrive()
        // Auto-collapse is managed by NotchService's hover timer.
    }

    /// Called when the pin state flips while a banner is showing.
    /// NotchService manages the auto-collapse timer; this just signals state change.
    func applyPinChange() {
        // No-op: auto-collapse is managed externally by NotchService.
    }

    func dismiss() {
        guard notice != nil else { return }
        notice = nil
        onDismiss?()
    }

    /// The user clicked the banner: jump back to the IDE, then dismiss.
    func tapped() {
        guard let notice = notice else { return }
        if notice.jumpEnabled {
            IDELauncher.activateAsync(provider: notice.provider, host: notice.host)
        }
        dismiss()
    }
}
