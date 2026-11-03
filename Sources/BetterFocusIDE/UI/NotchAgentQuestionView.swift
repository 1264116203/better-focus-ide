// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// Interactive question card shown on the island when an agent asks a question.
struct NotchAgentQuestionView: View {
    @ObservedObject var controller: QuestionController
    var pinned = false
    var onTogglePin: () -> Void = {}
    @FocusState private var otherFocused: Bool

    private var prompt: AgentQuestionPrompt? { controller.prompt }
    private var currentQuestion: AgentQuestion? { prompt?.question }

    // Live type sizes (Python body_font / option_font / desc_font), read at
    // render time so panel edits apply without a restart.
    private var bodyFontSize: CGFloat { CGFloat(Settings.shared.bodyFont) }
    private var optionFontSize: CGFloat { CGFloat(Settings.shared.optionFont) }
    private var descFontSize: CGFloat { CGFloat(Settings.shared.descFont) }
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    var body: some View {
        if let prompt = prompt, let question = currentQuestion {
            VStack(alignment: .leading, spacing: 8) {
                header(prompt: prompt, question: question)
                if !question.question.isEmpty {
                    Text(question.question)
                        .font(.system(size: bodyFontSize))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        optionsView(question: question)
                        otherRow(question: question)
                    }
                }
                sendButton(prompt: prompt)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Header

    private func header(prompt: AgentQuestionPrompt, question: AgentQuestion) -> some View {
        HStack(spacing: 8) {
            // Provider badge
            Text(String(prompt.provider.displayName.prefix(1)))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(prompt.provider.tint.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 4))
                .layoutPriority(1)
            Text("\(prompt.provider.displayName) · \(question.header)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 0)
            // Multi-question stepper
            if prompt.questions.count > 1 {
                HStack(spacing: 4) {
                    Button { controller.navigate(to: prompt.index - 1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.index <= 0)
                    Text("\(prompt.index + 1) / \(prompt.questions.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button { controller.navigate(to: prompt.index + 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.index >= prompt.questions.count - 1)
                }
                .foregroundStyle(.white.opacity(0.85))
                .layoutPriority(1)
            }
            // Pin icon (hold mode): click or ⌘⇧P toggles 固定 ⇄ 按需.
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .foregroundStyle(pinned ? AnyShapeStyle(prompt.provider.tint)
                                     : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help(pinned ? "取消固定（按需收起）" : "固定（保持展开）")
        }
    }

    // MARK: - Options

    private func optionsView(question: AgentQuestion) -> some View {
        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
            optionRow(index: index, option: option, question: question)
        }
    }

    private func optionRow(index: Int, option: AgentQuestionOption, question: AgentQuestion) -> some View {
        let picked = isSelected(index, question: question)
        return Button {
            controller.pick(.option(index), for: question.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: pickSymbol(picked, multiSelect: question.multiSelect))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(picked ? AnyShapeStyle(prompt?.provider.tint ?? .blue)
                                     : AnyShapeStyle(.white.opacity(0.4)))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: optionFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: descFontSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? (prompt?.provider.tint ?? .blue).opacity(0.22) : .white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(controller.choice != nil)
    }

    // MARK: - Other row

    @ViewBuilder
    private func otherRow(question: AgentQuestion) -> some View {
        let picked = isOwnAnswer(question: question)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                controller.beginOwnAnswer(for: question.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(picked ? AnyShapeStyle(prompt?.provider.tint ?? .blue)
                                         : AnyShapeStyle(.white.opacity(0.4)))
                        .frame(width: 16)
                    Text("其他…")
                        .font(.system(size: optionFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(picked ? (prompt?.provider.tint ?? .blue).opacity(0.22) : .white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(controller.choice != nil)

            if controller.writingOwn.contains(question.id) {
                TextField("输入自定义回答…",
                          text: Binding(
                            get: { controller.texts[question.id] ?? "" },
                            set: { controller.setText($0, for: question.id) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: optionFontSize))
                    .focused($otherFocused)
                    .onSubmit { controller.submit() }
                    .disabled(controller.choice != nil)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(.white.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: controller.focusOtherTick) {
                        otherFocused = true
                    }
            }
        }
    }

    // MARK: - Send button

    private func sendButton(prompt: AgentQuestionPrompt) -> some View {
        Button {
            controller.submit()
        } label: {
            Text("发送")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(controller.canSend ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(controller.canSend
                            ? AnyShapeStyle(prompt.provider.tint)
                            : AnyShapeStyle(.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!controller.canSend || controller.choice != nil)
    }

    // MARK: - Helpers

    private func isSelected(_ index: Int, question: AgentQuestion) -> Bool {
        let displayed = controller.choice ?? controller.picks[question.id]
        switch displayed {
        case .option(let picked): return picked == index
        case .options(let picked): return picked.contains(index)
        default: return false
        }
    }

    private func isOwnAnswer(question: AgentQuestion) -> Bool {
        let displayed = controller.choice ?? controller.picks[question.id]
        if case .custom = displayed { return true }
        return false
    }

    private func pickSymbol(_ picked: Bool, multiSelect: Bool) -> String {
        if multiSelect { return picked ? "checkmark.square.fill" : "square" }
        return picked ? "checkmark.circle.fill" : "circle"
    }
}
