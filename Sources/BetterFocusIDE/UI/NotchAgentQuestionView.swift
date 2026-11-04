// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 智能体提问时在灵动岛上展示的交互式问题卡片。
struct NotchAgentQuestionView: View {
    @ObservedObject var controller: QuestionController
    /// 观察 Settings 单例，使设置变更时视图能自动重新渲染（字号、间距等即时生效）。
    @ObservedObject private var settings = Settings.shared
    var pinned = false
    var onTogglePin: () -> Void = {}
    @FocusState private var otherFocused: Bool

    private var prompt: AgentQuestionPrompt? { controller.prompt }
    private var currentQuestion: AgentQuestion? { prompt?.question }

    // 字号（硬编码默认值，不再从 Settings 读取）
    private var bodyFontSize: CGFloat { 12 }
    private var optionFontSize: CGFloat { 12 }
    private var descFontSize: CGFloat { 10.5 }
    /// 卡片内边距（实时取自 Settings，改动即时生效）
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    /// 来源展示名：使用 AgentProvider 的统一辅助方法，优先 host.name（具体 IDE 名称），
    /// 回退到 displayName，JetBrains 插件模式下兜底为 "JetBrains"。
    private var sourceName: String {
        guard let prompt = prompt else { return "" }
        return AgentProvider.effectiveName(provider: prompt.provider, hostName: prompt.host?.name)
    }

    /// 项目名：从 host.cwd 提取末级目录名，用于卡片头部展示。
    private var projectName: String {
        guard let cwd = prompt?.host?.cwd, !cwd.isEmpty else { return "" }
        return (cwd as NSString).lastPathComponent
    }

    /// 徽章文本：取来源展示名的首字母大写。
    private var badgeText: String {
        return String(sourceName.prefix(1)).uppercased()
    }

    var body: some View {
        if let prompt = prompt, let question = currentQuestion {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    header(prompt: prompt, question: question)
                    if !projectName.isEmpty {
                        Text(projectName)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
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

                // 钉住开关：ZStack 覆盖层，统一使用主题色
                Button(action: onTogglePin) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(pinned ? 0 : 45))
                        .foregroundStyle(pinned
                            ? Color(red: settings.accentRGB.r,
                                    green: settings.accentRGB.g,
                                    blue: settings.accentRGB.b)
                            : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .padding(.trailing, inset)
                .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
            }
        }
    }

    // MARK: - 头部

    /// 头部：提供方徽章 + "来源 · 问题标题" + 多问翻页步进器。
    private func header(prompt: AgentQuestionPrompt, question: AgentQuestion) -> some View {
        HStack(spacing: 8) {
            // 提供方徽章：优先使用真实 IDE 图标，回退到文字徽章
            IDEIconProvider.badgeView(
                hostName: prompt.host?.name,
                bundleID: prompt.host?.bundle,
                fallbackText: badgeText,
                tint: prompt.provider.tint,
                size: 24
            )
            .layoutPriority(1)
            Text("\(sourceName) · \(question.header)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 0)
            // 多问翻页步进器（一次提问含多问时才出现）
            if prompt.questions.count > 1 {
                HStack(spacing: 4) {
                    Button { controller.navigate(to: prompt.index - 1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.index <= 0)
                    Text("\(prompt.index + 1) / \(prompt.questions.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button { controller.navigate(to: prompt.index + 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.index >= prompt.questions.count - 1)
                }
                .foregroundStyle(.white.opacity(0.85))
                .layoutPriority(1)
            }
        }
    }

    // MARK: - 选项

    private func optionsView(question: AgentQuestion) -> some View {
        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
            optionRow(index: index, option: option, question: question)
        }
    }

    /// 单个选项行：勾选符号 + 标签 + 可选描述；选中时用提供方主题色高亮底。
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

    // MARK: - "其他…"行

    /// "其他…"行：点击进入自定义作答，展开一个输入框；焦点由 focusOtherTick 驱动。
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

    // MARK: - 发送按钮

    /// 发送按钮：仅在 `canSend` 时高亮可点，提交后禁用。
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

    // MARK: - 辅助方法

    /// 该选项是否处于选中态（已提交则看 choice，否则看当前 picks）。
    private func isSelected(_ index: Int, question: AgentQuestion) -> Bool {
        let displayed = controller.choice ?? controller.picks[question.id]
        switch displayed {
        case .option(let picked): return picked == index
        case .options(let picked): return picked.contains(index)
        default: return false
        }
    }

    /// 该问题当前是否为自定义作答。
    private func isOwnAnswer(question: AgentQuestion) -> Bool {
        let displayed = controller.choice ?? controller.picks[question.id]
        if case .custom = displayed { return true }
        return false
    }

    /// 勾选符号：多选方形、单选圆形；选中时填充。
    private func pickSymbol(_ picked: Bool, multiSelect: Bool) -> String {
        if multiSelect { return picked ? "checkmark.square.fill" : "square" }
        return picked ? "checkmark.circle.fill" : "circle"
    }
}

#if DEBUG
/// Xcode Canvas 预览：构造一个 QuestionController 并注入模拟的提问。
struct NotchAgentQuestionView_Previews: PreviewProvider {
    static var previews: some View {
        let ctrl = QuestionController()
        let question = AgentQuestion(
            id: "q1",
            header: "重构方案选择",
            question: "是否将当前工程拆分为 library + executable 双目标以支持 SwiftUI Preview？",
            options: [
                AgentQuestionOption(label: "是，立即重构", description: "拆分为库目标与瘦可执行目标"),
                AgentQuestionOption(label: "暂不", description: "保持现有单 executable 结构"),
                AgentQuestionOption(label: "稍后提醒", description: "下次启动时再询问"),
            ],
            multiSelect: false
        )
        var host = HostInfo()
        host.bundle = "com.jetbrains.intellij"
        host.name = "IntelliJ IDEA"
        host.path = "/Applications/IntelliJ IDEA.app"
        host.cwd = "/Users/dev/better-focus-ide"
        let prompt = AgentQuestionPrompt(
            provider: .qoder,
            sessionID: "preview-session",
            questions: [question],
            arrivedAt: Date(),
            host: host
        )
        ctrl.present(prompt)
        return NotchAgentQuestionView(controller: ctrl)
            .frame(width: 420)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
