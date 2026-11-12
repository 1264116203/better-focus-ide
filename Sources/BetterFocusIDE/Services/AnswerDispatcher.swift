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

    /// 「让位」标记：宿主自己会画提问面板，让 hook 停止接管。
    ///
    /// 值取 -4，避开已有的 -1（超时）、-2（自定义文本）、-3（多选）。
    /// 同时写 `defer: true`，hook / 插件优先认这个键，下标只是兜底。
    static let deferIndex = -4

    /// 下发一次「让位」：告诉 hook 别接管这道题，把决定权交回宿主自己的对话框。
    ///
    /// 这是**必须被对端理解**的信号——只要有一个通道没实现（老版本 hook、旧插件），
    /// 用户就会看到「卡片不出现、工具却一直卡着」直到超时。因此新增通道时，
    /// 三个模板（HostHookTemplate / HelperTemplate / OpenCode 插件）要一起改，
    /// 并各自留一条契约测试。
    static func dispatchDefer(sessionID: String, questionIDs: [String],
                              requestID: String = "") {
        for questionID in questionIDs {
            let file = questionPath(sessionID: sessionID, questionID: questionID,
                                    requestID: requestID)
            var extra: [String: Any] = ["defer": true]
            if !requestID.isEmpty { extra["request_id"] = requestID }
            writeAnswer(to: file, optionIndex: deferIndex, optionLabel: "",
                        extra: extra)
        }
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
    ///
    /// `commandToken` 只在「始终允许」已经写入 Qoder 允许列表时带上，供 hook 核对。
    static func dispatchPermissionDecision(sessionID: String, requestID: String,
                                           decision: PermissionDecisionValue,
                                           commandToken: String? = nil,
                                           optionLabel: String? = nil) {
        let file = permissionPath(sessionID: sessionID, requestID: requestID)
        var extra: [String: Any] = ["decision": decision.rawValue, "message": ""]
        if let commandToken, !commandToken.isEmpty {
            extra["command_token"] = commandToken
        }
        writeAnswer(to: file, optionIndex: decision.answerIndex,
                    optionLabel: optionLabel ?? decision.label,
                    extra: extra)
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
