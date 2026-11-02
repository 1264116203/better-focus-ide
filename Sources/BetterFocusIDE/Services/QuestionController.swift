// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import Combine

/// Manages question card state: current prompt, queue, picks, and answer dispatch.
final class QuestionController: ObservableObject {
    @Published private(set) var prompt: AgentQuestionPrompt?
    @Published private(set) var choice: AgentQuestionAnswer?
    @Published var picks: [String: AgentQuestionAnswer] = [:]
    @Published var texts: [String: String] = [:]
    @Published var writingOwn: Set<String> = []
    /// Bumped to ask the SwiftUI card to move focus into the "Other…" field (Tab key).
    @Published private(set) var focusOtherTick = 0

    /// Queue of pending prompts.
    private var queue: [AgentQuestionPrompt] = []

    /// Notify when card state changes (triggers island expand).
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var hasActiveCard: Bool { prompt != nil }
    var pendingCount: Int { queue.count }
    /// Total items (active + queued) — drives the collapsed pending dot.
    var count: Int { (prompt != nil ? 1 : 0) + queue.count }
    /// Provider tint for the pending dot (highest-priority item).
    var pendingTint: (r: Double, g: Double, b: Double)? {
        guard let p = prompt else { return nil }
        let rgb = p.provider.tintRGB
        return (r: rgb.red, g: rgb.green, b: rgb.blue)
    }

    // MARK: - Socket event entry

    func handleEvent(_ event: SocketEvent, message: AgentSocketMessage) {
        switch event {
        case .questionRequested:
            let questions = AgentQuestionPrompt.parseQuestions(from: message.payload)
            guard !questions.isEmpty else { return }
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            guard let provider = AgentProvider(rawValue: message.provider) else { return }
            let newPrompt = AgentQuestionPrompt(
                provider: provider, sessionID: message.sessionID,
                questions: questions, arrivedAt: Date(), requestID: requestID)
            present(newPrompt)

        case .questionAnswered, .questionTimeout:
            let questionID = message.payload?["question_id"]?.stringValue ?? "q1"
            let requestID = message.payload?["request_id"]?.stringValue ?? ""
            clearCurrent(questionID: questionID, requestID: requestID)

        case .sessionEnded:
            dropSession(sessionID: message.sessionID)

        default: break
        }
    }

    // MARK: - Present / Dismiss

    func present(_ newPrompt: AgentQuestionPrompt) {
        // Same session re-send: replace current
        if let current = prompt, choice == nil,
           current.provider == newPrompt.provider,
           current.sessionID == newPrompt.sessionID {
            prompt = newPrompt
            picks = [:]
            texts = [:]
            writingOwn = []
            onPresent?()
            return
        }
        // Already showing: enqueue, dropping the oldest when over the limit
        // (question_queue_limit) so the newest request is never lost.
        if prompt != nil || !queue.isEmpty {
            queue.append(newPrompt)
            let limit = max(1, Settings.shared.questionQueueLimit)
            if queue.count > limit { queue.removeFirst(queue.count - limit) }
            return
        }
        prompt = newPrompt
        picks = [:]
        texts = [:]
        writingOwn = []
        onPresent?()
    }

    func clearCurrent(questionID: String, requestID: String) {
        guard let current = prompt else { return }
        if current.matches(questionID: questionID, requestID: requestID) {
            dismiss()
        }
    }

    func dropSession(sessionID: String) {
        if prompt?.sessionID == sessionID { dismiss() }
        queue.removeAll { $0.sessionID == sessionID }
    }

    /// Drop cards nobody waits for any more: the hook already timed out (wait
    /// limit + margin + grace), so the request fell back to the IDE.
    func sweepStale(olderThan deadline: TimeInterval) {
        let now = Date()
        queue.removeAll { now.timeIntervalSince($0.arrivedAt) > deadline }
        if let p = prompt, choice == nil, now.timeIntervalSince(p.arrivedAt) > deadline {
            dismiss()
        }
    }

    private func dismiss() {
        prompt = nil
        choice = nil
        picks = [:]
        texts = [:]
        writingOwn = []
        onDismiss?()
        promoteNext()
    }

    private func promoteNext() {
        guard prompt == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        prompt = next
        picks = [:]
        texts = [:]
        writingOwn = []
        onPresent?()
    }

    // MARK: - User interactions

    func navigate(to index: Int) {
        guard var p = prompt else { return }
        p.index = max(0, min(index, p.questions.count - 1))
        prompt = p
    }

    func pick(_ answer: AgentQuestionAnswer, for questionID: String) {
        guard prompt != nil else { return }
        if let current = prompt, current.question.multiSelect {
            // Toggle for multi-select
            var indices = Set(picks[questionID]?.answerIndices ?? [])
            switch answer {
            case .option(let idx):
                if indices.contains(idx) { indices.remove(idx) }
                else { indices.insert(idx) }
                picks[questionID] = indices.isEmpty ? nil : .options(Array(indices))
            default: picks[questionID] = answer
            }
        } else {
            picks[questionID] = answer
            // Auto-advance for single-select
            advanceIfNeeded()
        }
    }

    func beginOwnAnswer(for questionID: String) {
        writingOwn.insert(questionID)
        picks[questionID] = .custom(texts[questionID] ?? "")
    }

    /// Tab / `.other`: start a custom answer and ask the view to focus the field.
    func requestFocusOther(for questionID: String) {
        beginOwnAnswer(for: questionID)
        focusOtherTick += 1
    }

    func setText(_ text: String, for questionID: String) {
        texts[questionID] = text
        if writingOwn.contains(questionID) {
            picks[questionID] = .custom(text)
        }
    }

    var canSend: Bool {
        guard let p = prompt else { return false }
        return p.questions.allSatisfy { q in
            switch picks[q.id] {
            case .option: return true
            case .options(let indices): return !indices.isEmpty
            case .custom(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case nil: return false
            }
        }
    }

    func submit() {
        guard canSend, let p = prompt, choice == nil else { return }
        let ordered = p.questions.map { picks[$0.id] ?? .option(-1) }
        // Dispatch answers
        for (i, q) in p.questions.enumerated() {
            AnswerDispatcher.dispatchAnswer(
                sessionID: p.sessionID, questionID: q.id,
                requestID: p.requestID, answer: ordered[i], question: q)
        }
        choice = ordered.first
        FeedbackService.onAnswer()
        // Brief feedback then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismiss()
        }
    }

    private func advanceIfNeeded() {
        guard let p = prompt, p.index + 1 < p.questions.count else { return }
        navigate(to: p.index + 1)
    }
}

// MARK: - Prompt matching extension

private extension AgentQuestionPrompt {
    func matches(questionID: String, requestID: String) -> Bool {
        if !requestID.isEmpty && !self.requestID.isEmpty {
            return self.requestID == requestID
        }
        return questions.contains { $0.id == questionID }
    }
}
