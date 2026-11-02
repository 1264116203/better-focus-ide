// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// Manages permission card state: current request, queue, and decision dispatch.
final class PermissionController: ObservableObject {
    @Published private(set) var request: PermissionRequest?
    @Published private(set) var choice: PermissionDecisionValue?

    private var queue: [PermissionRequest] = []

    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var hasActiveCard: Bool { request != nil }
    var pendingCount: Int { queue.count }
    /// Total items (active + queued) — drives the collapsed pending dot.
    var count: Int { (request != nil ? 1 : 0) + queue.count }
    /// Provider tint for the pending dot (highest-priority item).
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let req = request else { return nil }
        let rgb = req.provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - Socket event entry

    func handleEvent(_ event: SocketEvent, message: AgentSocketMessage) {
        switch event {
        case .permissionRequested:
            guard let provider = AgentProvider(rawValue: message.provider),
                  let req = PermissionRequest.parse(
                    payload: message.payload, provider: provider,
                    sessionID: message.sessionID) else { return }
            present(req)

        case .permissionResolved, .permissionTimeout:
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            clearCurrent(requestID: requestID)

        case .sessionEnded:
            dropSession(sessionID: message.sessionID)

        default: break
        }
    }

    // MARK: - Present / Dismiss

    func present(_ newRequest: PermissionRequest) {
        // Same request re-send: replace
        if let current = request, choice == nil,
           current.requestID == newRequest.requestID,
           current.sessionID == newRequest.sessionID {
            request = newRequest
            onPresent?()
            return
        }
        if request != nil || !queue.isEmpty {
            queue.append(newRequest)
            let limit = max(1, Settings.shared.permissionQueueLimit)
            if queue.count > limit { queue.removeFirst(queue.count - limit) }
            return
        }
        request = newRequest
        onPresent?()
    }

    func clearCurrent(requestID: String) {
        guard let current = request else { return }
        if current.requestID == requestID && current.sessionID == current.sessionID {
            dismiss()
        } else if !requestID.isEmpty {
            // Check by ID match
            if current.requestID == requestID { dismiss() }
        }
    }

    func dropSession(sessionID: String) {
        if request?.sessionID == sessionID { dismiss() }
        queue.removeAll { $0.sessionID == sessionID }
    }

    /// Drop cards nobody waits for any more: the hook already timed out (wait
    /// limit + margin + grace), so the request fell back to the IDE.
    func sweepStale(olderThan deadline: TimeInterval) {
        let now = Date()
        queue.removeAll { now.timeIntervalSince($0.arrivedAt) > deadline }
        if let r = request, choice == nil, now.timeIntervalSince(r.arrivedAt) > deadline {
            dismiss()
        }
    }

    private func dismiss() {
        request = nil
        choice = nil
        onDismiss?()
        promoteNext()
    }

    private func promoteNext() {
        guard request == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        request = next
        onPresent?()
    }

    // MARK: - User decisions

    func decide(_ decision: PermissionDecisionValue) {
        guard let req = request, choice == nil else { return }
        AnswerDispatcher.dispatchPermissionDecision(
            sessionID: req.sessionID, requestID: req.requestID, decision: decision)
        choice = decision
        FeedbackService.onAnswer()
        // Brief feedback then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismiss()
        }
    }
}
