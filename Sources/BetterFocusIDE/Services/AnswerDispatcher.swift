// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 把用户应答写入文件，供 Qoder Hook / OpenCode Plugin 轮询读取决策结果。
///
/// 出站通道：灵动岛不直接回写 socket，而是落一个应答文件，hook/插件轮询取走。
enum AnswerDispatcher {
    /// 应答文件目录：~/Library/Application Support/BetterFocusIDE/answers
    static let answerDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterFocusIDE/answers")
    }()

    // MARK: - 问题应答

    /// 问题应答文件路径：有 requestID 时插入到文件名中段，避免跨请求串味。
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

    /// 下发一次问题作答（单选/多选/自定义统一走这里）。
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

    /// 下发一次问题超时（answer_index = -1）。
    static func dispatchTimeout(sessionID: String, questionID: String,
                                requestID: String = "") {
        let file = questionPath(sessionID: sessionID, questionID: questionID,
                                requestID: requestID)
        writeAnswer(to: file, optionIndex: -1, optionLabel: "",
                    extra: requestID.isEmpty ? nil : ["request_id": requestID])
    }

    // MARK: - 权限决策

    /// 权限应答文件路径：以 `perm-` 前缀区分于问题应答。
    static func permissionPath(sessionID: String, requestID: String) -> URL {
        answerDirectory.appendingPathComponent("\(sessionID)_perm-\(requestID).json")
    }

    /// 下发一次权限决策（允许/始终允许/拒绝），附带决策原始值。
    static func dispatchPermissionDecision(sessionID: String, requestID: String,
                                           decision: PermissionDecisionValue) {
        let file = permissionPath(sessionID: sessionID, requestID: requestID)
        writeAnswer(to: file, optionIndex: decision.answerIndex,
                    optionLabel: decision.label,
                    extra: ["decision": decision.rawValue, "message": ""])
    }

    /// 下发一次权限超时（decision = timeout）。
    static func dispatchPermissionTimeout(sessionID: String, requestID: String) {
        let file = permissionPath(sessionID: sessionID, requestID: requestID)
        writeAnswer(to: file, optionIndex: -1, optionLabel: "",
                    extra: ["decision": "timeout", "message": ""])
    }

    // MARK: - 核心写入

    /// 组装应答 JSON 并原子写入。
    ///
    /// 基础字段：answer_index / answer_label / timestamp；多选补 answer_indices；
    /// `extra` 里的键（如 request_id、decision）合并进同一对象。
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

    /// 清理早于 `age` 秒的陈旧应答文件（默认 120s），防止残留文件被误读。
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
