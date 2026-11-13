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
    /// 正文和选项说明是否已展开。放不下时点那段文字展开，再点一次收回。
    var detailExpanded = false
    var onToggleDetail: () -> Void = {}
    @FocusState private var otherFocused: Bool

    private var prompt: AgentQuestionPrompt? { controller.prompt }
    private var currentQuestion: AgentQuestion? { prompt?.question }

    // 字号（硬编码默认值，不再从 Settings 读取）
    private var bodyFontSize: CGFloat { 12 }
    private var optionFontSize: CGFloat { 12 }
    private var descFontSize: CGFloat { 10.5 }
    /// 卡片内边距（实时取自 Settings，改动即时生效）
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    /// 来源展示名：走 AgentProvider.label——GUI 宿主用 host.name（具体 IDE 名称），
    /// CLI 宿主标成「产品（终端）」如 "Qoder CLI（Warp）"，JetBrains 兜底 "JetBrains"。
    private var sourceName: String {
        guard let prompt = prompt else { return "" }
        return AgentProvider.label(provider: prompt.provider,
                                   hostName: prompt.host?.name,
                                   bundleID: prompt.host?.bundle)
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
            VStack(alignment: .leading, spacing: 8) {
                header(prompt: prompt, question: question)
                if !projectName.isEmpty {
                    Text(projectName)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                detailSection(question)
                // 选项列表直接展开（不再套 ScrollView），所有选项一次性可见；
                // 卡片高度由 NotchService.questionCardHeight() 按内容自适应。
                VStack(spacing: 6) {
                    optionsView(question: question)
                    otherRow(question: question)
                }
                sendButton(prompt: prompt)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 详情

    private var questionTextWidth: CGFloat {
        max(80, NotchLayout.questionCardWidth - inset * 2)
    }

    private var optionTextWidth: CGFloat {
        max(40, questionTextWidth - QuestionCardLayout.rowTextInset)
    }

    private var detailStyle: DetailText.Style {
        .question(expanded: detailExpanded)
    }

    @ViewBuilder
    private func detailSection(_ question: AgentQuestion) -> some View {
        if !question.question.isEmpty {
            let measured = DetailText.measure(
                question.question,
                width: questionTextWidth,
                font: bodyFontSize,
                collapsedLines: detailStyle.bodyCollapsedLines,
                expanded: detailExpanded)
            // 只有这段正文自己放不下时才能点。选项说明另算，避免点到短正文把整张卡展开。
            DetailTextBlock(
                text: question.question,
                fontSize: bodyFontSize,
                collapsedLines: detailStyle.bodyCollapsedLines,
                expanded: detailExpanded,
                measure: measured,
                onToggle: measured.showsControl ? onToggleDetail : nil)
                .allowsHitTesting(measured.showsControl)
        }
    }

    // MARK: - 头部

    /// 头部：提供方徽章 + "来源 · 问题标题" + 多问翻页步进器。
    private func header(prompt: AgentQuestionPrompt, question: AgentQuestion) -> some View {
        HStack(spacing: 8) {
            // 提供方徽章：优先使用真实 IDE 图标，回退到文字徽章；
            // host 缺失时用 sourceName（统一兜底名）匹配图标。
            // 图标身份与来源文字同源（CLI → 终端图标，GUI → 产品图标）。
            let iconID = AgentProvider.iconIdentity(
                provider: prompt.provider,
                hostName: prompt.host?.name ?? sourceName,
                bundleID: prompt.host?.bundle)
            IDEIconProvider.badgeView(
                hostName: iconID.name,
                bundleID: iconID.bundle,
                fallbackText: badgeText,
                tint: prompt.provider.tint,
                size: IDEIconProvider.badgeSize
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
                            .frame(width: 22, height: 22)
                            .liquidGlass(.circle, variant: .clear, interactive: prompt.index > 0, fallback: .clear)
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
                            .frame(width: 22, height: 22)
                            .liquidGlass(.circle, variant: .clear,
                                         interactive: prompt.index < prompt.questions.count - 1,
                                         fallback: .clear)
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.index >= prompt.questions.count - 1)
                }
                .foregroundStyle(.white.opacity(0.85))
                .layoutPriority(1)
            }
            // 钉住开关：作为行内元素排在头部末尾，避免与翻页步进器抢右上角空间。
            PinButton(pinned: pinned, action: onTogglePin)
                .layoutPriority(2)
        }
    }

    // MARK: - 选项

    private func optionsView(question: AgentQuestion) -> some View {
        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
            optionRow(index: index, option: option, question: question)
        }
    }

    /// 单个选项行：勾选符号 + 标签 + 可选描述；选中时用提供方主题色高亮底。
    ///
    /// 说明被省略时，点说明展开或收回，不能同时把这一项选上。
    /// 说明因此叠在选项按钮之上，只盖住说明本身；标签、图标和空白仍是选择。
    private func optionRow(index: Int, option: AgentQuestionOption, question: AgentQuestion) -> some View {
        let picked = isSelected(index, question: question)
        let focused = controller.keyboardFocus == index
        let descMeasure = optionDescriptionMeasure(option)
        let descOverflows = descMeasure?.showsControl == true
        return ZStack(alignment: .topLeading) {
            Button {
                controller.pick(.option(index), for: question.id)
            } label: {
                optionRowBody(option: option, question: question, picked: picked,
                              focused: focused, descMeasure: descMeasure,
                              descriptionVisible: !descOverflows)
            }
            .buttonStyle(.plain)
            .disabled(controller.choice != nil)

            if descOverflows, let descMeasure {
                optionDescriptionToggle(option: option, measure: descMeasure)
            }
        }
    }

    private func optionDescriptionMeasure(_ option: AgentQuestionOption) -> DetailText.Measure? {
        guard !option.description.isEmpty else { return nil }
        let lines = DetailText.Style.question(expanded: false).descriptionCollapsedLines
        return DetailText.measure(option.description, width: optionTextWidth, font: descFontSize,
                                  collapsedLines: lines, expanded: detailExpanded)
    }

    /// 与选项行同一套内边距，只让说明文字接住点击。
    private func optionDescriptionToggle(option: AgentQuestionOption,
                                         measure: DetailText.Measure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: 16, height: 1)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                optionLabel(option.label)
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                descriptionBlock(option.description, measure: measure, tappable: true)
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private func optionRowBody(option: AgentQuestionOption, question: AgentQuestion,
                               picked: Bool, focused: Bool,
                               descMeasure: DetailText.Measure?,
                               descriptionVisible: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pickSymbol(picked, multiSelect: question.multiSelect))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(picked ? AnyShapeStyle(prompt?.provider.tint ?? .blue)
                                 : AnyShapeStyle(.white.opacity(0.4)))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                optionLabel(option.label)
                if let descMeasure {
                    descriptionBlock(option.description, measure: descMeasure, tappable: false)
                        .opacity(descriptionVisible ? 1 : 0)
                        .accessibilityHidden(!descriptionVisible)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.rounded(16), variant: .clear,
                     tint: picked ? (prompt?.provider.tint ?? .blue) : nil,
                     interactive: controller.choice == nil,
                     fallback: picked
                        ? (prompt?.provider.tint ?? .blue).opacity(0.22)
                        : Color.white.opacity(0.06))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if focused && !picked {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            }
        }
    }

    private func optionLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: optionFontSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func descriptionBlock(_ text: String, measure: DetailText.Measure,
                                  tappable: Bool) -> some View {
        let lines = DetailText.Style.question(expanded: false).descriptionCollapsedLines
        return DetailTextBlock(
            text: text,
            fontSize: descFontSize,
            color: .secondary,
            collapsedLines: lines,
            expanded: detailExpanded,
            measure: measure,
            onToggle: tappable ? onToggleDetail : nil)
    }

    // MARK: - "其他…"行

    /// "其他…"行：点击后**同一行内**直接变为输入框（不再下方另起一行），
    /// 焦点由 focusOtherTick 驱动。
    @ViewBuilder
    private func otherRow(question: AgentQuestion) -> some View {
        let picked = isOwnAnswer(question: question)
        let writing = controller.writingOwn.contains(question.id)

        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(picked ? AnyShapeStyle(prompt?.provider.tint ?? .blue)
                                 : AnyShapeStyle(.white.opacity(0.4)))
                .frame(width: 16)

            if writing {
                // 激活后同行走输入框：直接在此输入，无需再点一下。
                TextField("输入自定义回答…",
                          text: Binding(
                            get: { controller.texts[question.id] ?? "" },
                            set: { controller.setText($0, for: question.id) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: optionFontSize))
                    .foregroundStyle(.white.opacity(0.95))
                    .focused($otherFocused)
                    .onSubmit { controller.confirmOrSubmit() }
                    .disabled(controller.choice != nil)
                    .onChange(of: controller.focusOtherTick) {
                        otherFocused = true
                    }
            } else {
                Text("其他…")
                    .font(.system(size: optionFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 30)
        .liquidGlass(.rounded(16), variant: .clear,
                     tint: picked ? (prompt?.provider.tint ?? .blue) : nil,
                     interactive: controller.choice == nil,
                     fallback: picked
                        ? (prompt?.provider.tint ?? .blue).opacity(0.22)
                        : Color.white.opacity(0.06))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            // 点击整行即进入自定义作答，并请求焦点移入同行的输入框。
            guard !writing else { return }
            controller.requestFocusOther(for: question.id)
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
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // 可点时不用交互玻璃。交互玻璃会把按下收成高光，按钮动作到不了。
                .liquidGlass(.rounded(14), variant: .clear,
                             tint: controller.canSend ? prompt.provider.tint : nil,
                             interactive: false,
                             fallback: controller.canSend
                                ? prompt.provider.tint
                                : Color.white.opacity(0.08))
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
