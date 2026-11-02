// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

// MARK: - AgentQuestion

/// A question the agent asked through AskUserQuestion / question tool.
struct AgentQuestion: Equatable, Identifiable {
    let id: String
    let header: String
    let question: String
    let options: [AgentQuestionOption]
    var multiSelect: Bool = false
}

/// One selectable option on a question card.
struct AgentQuestionOption: Equatable {
    let label: String
    let description: String
}

// MARK: - AgentQuestionAnswer

/// What the person chose on a question card.
enum AgentQuestionAnswer: Equatable {
    case option(Int)
    case options([Int])
    case custom(String)

    static let multiSelectSeparator = "、"

    func label(in question: AgentQuestion) -> String {
        switch self {
        case .option(let idx):
            return question.options.indices.contains(idx) ? question.options[idx].label : ""
        case .options(let indices):
            return indices.sorted()
                .filter { question.options.indices.contains($0) }
                .map { question.options[$0].label }
                .joined(separator: Self.multiSelectSeparator)
        case .custom(let text):
            return text
        }
    }

    var answerIndex: Int {
        switch self {
        case .option(let idx): return idx
        case .options: return -3
        case .custom: return -2
        }
    }

    var answerIndices: [Int] {
        switch self {
        case .option(let idx): return [idx]
        case .options(let indices): return indices.sorted()
        case .custom: return []
        }
    }
}

// MARK: - AgentQuestionPrompt

/// A set of questions waiting for the person's answers.
struct AgentQuestionPrompt: Equatable, Identifiable {
    let provider: AgentProvider
    let sessionID: String
    let questions: [AgentQuestion]
    var index: Int = 0
    let arrivedAt: Date
    var requestID: String = ""

    var question: AgentQuestion { questions[min(index, questions.count - 1)] }

    var id: String {
        if !requestID.isEmpty {
            return "\(provider.rawValue).\(sessionID).r:\(requestID)"
        }
        return "\(provider.rawValue).\(sessionID).\(questions.first?.id ?? "q1")"
    }

    static func == (lhs: AgentQuestionPrompt, rhs: AgentQuestionPrompt) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Parsing from socket payload

    /// Parse questions from a socket message payload.
    static func parseQuestions(from payload: [String: AnyCodableValue]?) -> [AgentQuestion] {
        guard let payload, case .array(let arr) = payload["questions"] else { return [] }
        return arr.compactMap { entry -> AgentQuestion? in
            guard case .dictionary(let dict) = entry else { return nil }
            let id = dict["id"]?.stringValue ?? "q1"
            let header = dict["header"]?.stringValue ?? "Question"
            let text = dict["question"]?.stringValue ?? ""
            let multi = dict["multiSelect"]?.boolValue ?? dict["multi_select"]?.boolValue ?? false
            let options: [AgentQuestionOption]
            if case .array(let opts) = dict["options"] {
                options = opts.compactMap { opt -> AgentQuestionOption? in
                    if case .dictionary(let d) = opt {
                        return AgentQuestionOption(
                            label: d["label"]?.stringValue ?? "",
                            description: d["description"]?.stringValue ?? "")
                    } else if let s = opt.stringValue {
                        return AgentQuestionOption(label: s, description: "")
                    }
                    return nil
                }
            } else { options = [] }
            return AgentQuestion(id: id, header: header, question: text,
                                 options: options, multiSelect: multi)
        }
    }
}
