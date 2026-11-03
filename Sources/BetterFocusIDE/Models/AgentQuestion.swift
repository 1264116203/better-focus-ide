// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

// MARK: - AgentQuestion

/// 智能体通过 AskUserQuestion / question 工具抛出的一个问题。
///
/// 对应问题卡片上的一段提问：标题(header)、正文(question)、
/// 若干可选项(options)，以及是否允许多选(multiSelect)。
struct AgentQuestion: Equatable, Identifiable {
    /// 问题在会话内的唯一标识。
    let id: String
    /// 简短标题（卡片顶部的粗体一行）。
    let header: String
    /// 完整问题正文。
    let question: String
    /// 可选项列表。
    let options: [AgentQuestionOption]
    /// 是否为多选题，默认单选。
    var multiSelect: Bool = false
}

/// 问题卡片上的一个可选项。
struct AgentQuestionOption: Equatable {
    /// 选项标签（显示的主文字）。
    let label: String
    /// 选项描述（补充说明的副文字）。
    let description: String
}

// MARK: - AgentQuestionAnswer

/// 用户在问题卡片上做出的选择。
enum AgentQuestionAnswer: Equatable {
    /// 单选：选中某个选项的下标。
    case option(Int)
    /// 多选：选中多个选项的下标集合。
    case options([Int])
    /// 自定义："其他…"输入的自由文本。
    case custom(String)

    /// 多选项拼接展示时的分隔符（顿号）。
    static let multiSelectSeparator = "、"

    /// 将选择转换为可读文本标签（用于回显与历史）。
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

    /// 单一下标编码：正常选项返回其下标，多选返回 -3，自定义返回 -2。
    /// 供写回应答文件时区分选择类型。
    var answerIndex: Int {
        switch self {
        case .option(let idx): return idx
        case .options: return -3
        case .custom: return -2
        }
    }

    /// 所有选中的下标（自定义返回空数组，多选返回排序后的下标）。
    var answerIndices: [Int] {
        switch self {
        case .option(let idx): return [idx]
        case .options(let indices): return indices.sorted()
        case .custom: return []
        }
    }
}

// MARK: - AgentQuestionPrompt

/// 一组等待用户作答的问题（一次提问可能包含多问，通过 index 翻页）。
struct AgentQuestionPrompt: Equatable, Identifiable {
    let provider: AgentProvider
    let sessionID: String
    let questions: [AgentQuestion]
    /// 当前显示到第几个问题（多问翻页游标）。
    var index: Int = 0
    let arrivedAt: Date
    /// 请求标识；为空时回退到首个问题 id 组合。
    var requestID: String = ""
    /// 宿主应用身份（hook 上报的 IDE 信息），用于历史来源展示与跳转。
    var host: HostInfo?

    /// 当前问题（对 index 做越界钳制）。
    var question: AgentQuestion { questions[min(index, questions.count - 1)] }

    /// 卡片唯一标识：优先用 requestID，否则用提供方+会话+首问题 id 拼接。
    var id: String {
        if !requestID.isEmpty {
            return "\(provider.rawValue).\(sessionID).r:\(requestID)"
        }
        return "\(provider.rawValue).\(sessionID).\(questions.first?.id ?? "q1")"
    }

    static func == (lhs: AgentQuestionPrompt, rhs: AgentQuestionPrompt) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: 从 socket 载荷解析

    /// 从 socket 消息的 payload 中解析出问题列表。
    ///
    /// 容错：缺失/畸形字段回退到默认值；options 支持"字典"或"纯字符串"两种形态。
    static func parseQuestions(from payload: [String: AnyCodableValue]?) -> [AgentQuestion] {
        guard let payload, case .array(let arr) = payload["questions"] else { return [] }
        return arr.compactMap { entry -> AgentQuestion? in
            guard case .dictionary(let dict) = entry else { return nil }
            let id = dict["id"]?.stringValue ?? "q1"
            let header = dict["header"]?.stringValue ?? "Question"
            let text = dict["question"]?.stringValue ?? ""
            // multiSelect 兼容驼峰与下划线两种键名。
            let multi = dict["multiSelect"]?.boolValue ?? dict["multi_select"]?.boolValue ?? false
            let options: [AgentQuestionOption]
            if case .array(let opts) = dict["options"] {
                options = opts.compactMap { opt -> AgentQuestionOption? in
                    if case .dictionary(let d) = opt {
                        return AgentQuestionOption(
                            label: d["label"]?.stringValue ?? "",
                            description: d["description"]?.stringValue ?? "")
                    } else if let s = opt.stringValue {
                        // 选项可能是纯字符串（无描述）。
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
