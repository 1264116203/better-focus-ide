// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Writes user answers to files that Qoder Hook / OpenCode Plugin poll for decisions.
enum AnswerDispatcher {
    static let answerDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterFocusIDE/answers")
    }()

    // MARK: - Question answers

    static func questionPath(sessionID: String, questionID: String,
                             requestID: String = "") -> URL {
        let name: String
        if !requestID.isEmpty {
            name = "\(sessionID)_\(requestID)_\(questionID).json"
        } else {
            name = "\(sessionID)_\(questionID).json"
        }
        return answerDirectory.appendingPathComponent(name)
    }

    static func dispatchAnswer(sessionID: String, questionID: String,
                               requestID: String = "",
                               answer: AgentQuestionAnswer, question: AgentQuestion) {
        let file = questionPath(sessionID: sessionID, questionID: questionID,
                                requestID: requestID)
        writeAnswer(to: file, optionIndex: answer.answerIndex,
                    optionLabel: answer.label(in: question),
                    optionIndices: answer.answerIndices,
                    extra: requestID.isEmpty ? nil : ["request_id": requestID])
    }

    static func dispatchTimeout(sessionID: String, questionID: String,
                                requestID: String = "") {
        let file = questionPath(sessionID: sessionID, questionID: questionID,
                                requestID: requestID)
        writeAnswer(to: file, optionIndex: -1, optionLabel: "",
                    extra: requestID.isEmpty ? nil : ["request_id": requestID])
    }

    // MARK: - Permission decisions

    static func permissionPath(sessionID: String, requestID: String) -> URL {
        answerDirectory.appendingPathComponent("\(sessionID)_perm-\(requestID).json")
    }

    static func dispatchPermissionDecision(sessionID: String, requestID: String,
                                           decision: PermissionDecisionValue) {
        let file = permissionPath(sessionID: sessionID, requestID: requestID)
        writeAnswer(to: file, optionIndex: decision.answerIndex,
                    optionLabel: decision.label,
                    extra: ["decision": decision.rawValue, "message": ""])
    }

    static func dispatchPermissionTimeout(sessionID: String, requestID: String) {
        let file = permissionPath(sessionID: sessionID, requestID: requestID)
        writeAnswer(to: file, optionIndex: -1, optionLabel: "",
                    extra: ["decision": "timeout", "message": ""])
    }

    // MARK: - Core write

    private static func writeAnswer(to file: URL, optionIndex: Int,
                                     optionLabel: String, optionIndices: [Int] = [],
                                     extra: [String: Any]? = nil) {
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var content: [String: Any] = [
            "answer_index": optionIndex,
            "answer_label": optionLabel,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        if !optionIndices.isEmpty { content["answer_indices"] = optionIndices }
        if let extra { content.merge(extra) { _, new in new } }

        if let data = try? JSONSerialization.data(withJSONObject: content,
                                                   options: [.prettyPrinted]) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Clean up answer files older than `age` seconds.
    static func cleanup(olderThan age: TimeInterval = 120) {
        let cutoff = Date().addingTimeInterval(-age)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: answerDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for file in files where file.pathExtension == "json" {
            if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = attrs.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
