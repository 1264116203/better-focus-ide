// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 设置面板里的「调试」页：手动触发各家 IDE 的各种通知，省去为了看一眼卡片
/// 而真的去 IDE 里跑一轮对话。
///
/// 设计上刻意与真实链路对齐——按钮注入的是与 hook **同构**的 socket 消息，
/// 走 `NotchService` 的同一套分发（仅绕过「提醒」开关门控），因此这里看到的
/// 排版、图标、主题色、跳转目标就是真机上的样子；唯一不会发生的是应答回写：
/// 调试卡片作答只会写一个 `debug-*` 前缀的应答文件，没有任何 hook 在等它。
struct DebugPanelView: View {
    /// 当前选中的目标 IDE（伪造的 provider / host 身份）。
    @State private var targetID = DebugTarget.all[0].id
    /// 模拟项目名：通知横幅上那句项目标签取自它。
    @State private var project = "better-focus-ide"
    /// 最近一次触发的结果文案。
    @State private var status = "选一个目标 IDE，再点右侧「触发」"
    /// 刚触发过的场景 id（按钮短暂显示对勾）。
    @State private var flashID: String?

    private enum Metric {
        static let margin: CGFloat = 16
        static let rowGap: CGFloat = 6
        static let buttonWidth: CGFloat = 78
        static let projectWidth: CGFloat = 170
    }

    private var target: DebugTarget {
        DebugTarget.all.first { $0.id == targetID } ?? DebugTarget.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.rowGap) {
                header
                todoQuickSection
                ForEach(DebugCatalog.groups, id: \.self) { group in
                    Text(group)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                    ForEach(DebugCatalog.scenes(in: group)) { scene in
                        row(scene)
                    }
                }
            }
            .padding(Metric.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 头部（目标 IDE / 模拟项目 / 状态）

    /// 顶部说明卡：目标 IDE 选择器 + 模拟项目名 + 最近一次触发的结果。
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("目标 IDE")
                    .font(.system(size: 11.5))
                Circle()
                    .fill(target.provider.tint)
                    .frame(width: 7, height: 7)
                Picker("", selection: $targetID) {
                    ForEach(DebugTarget.all) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)

                Text("模拟项目")
                    .font(.system(size: 11.5))
                    .padding(.leading, 8)
                TextField("better-focus-ide", text: $project)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: Metric.projectWidth)
                Spacer(minLength: 0)
            }

            Text("按钮注入的是与 hook 同构的本地事件，走真实分发链路，但不受「提醒」开关限制，也不会回写任何应答文件。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                Text(status)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - 场景行

    /// 「各 IDE 快速验证」区块：一个宿主一个按钮，点击即以该宿主身份注入一条
    /// 标准的「进行中」任务进度，省去先选目标 IDE 再点触发的两步。列出的宿主
    /// 都是 hook 侧真正能收到 todo 事件的（Qoder / OpenCode / Claude Code / Kimi /
    /// WorkBuddy），Cursor / Trae / Codex 收不到故不列。
    private var todoQuickSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("任务进度 · 各 IDE 快速验证")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            Text("点击即以该宿主身份注入一条 6 项任务进度，验证徽章、主题色与跳转目标。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            // 用自适应网格排按钮：窗口窄时自动换行，宽时排成一行。
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                alignment: .leading, spacing: 6
            ) {
                ForEach(DebugTarget.todoCapable) { item in
                    quickButton(item)
                }
            }
        }
    }

    /// 单个宿主的快速验证按钮：左侧宿主色点 + 名字，点完短暂变「已注入 ✓」。
    private func quickButton(_ item: DebugTarget) -> some View {
        let fired = flashID == "todo-quick-\(item.id)"
        return Button {
            status = DebugInjector.fireTodoQuick(target: item, project: project)
            flashID = "todo-quick-\(item.id)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if flashID == "todo-quick-\(item.id)" { flashID = nil }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(item.provider.tint)
                    .frame(width: 7, height: 7)
                Text(fired ? "已注入" : item.title)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    /// 一行一个场景：标题 + 说明 + 触发按钮。
    private func row(_ scene: DebugScene) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.title)
                    .font(.system(size: 11.5))
                Text(scene.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            triggerButton(scene)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// 触发按钮：点完短暂变「已触发 ✓」，给一点可感知的反馈。
    private func triggerButton(_ scene: DebugScene) -> some View {
        let fired = flashID == scene.id
        return Button {
            fire(scene)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: fired ? "checkmark" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(fired ? "已触发" : "触发")
                    .font(.system(size: 11))
            }
            .frame(width: Metric.buttonWidth)
        }
        .controlSize(.small)
    }

    // MARK: - 动作

    /// 执行一次注入，并把结果写回状态行。
    private func fire(_ scene: DebugScene) {
        status = DebugInjector.fire(scene, target: target, project: project)
        flashID = scene.id
        // 0.9 秒后收回对勾；期间若又点了别的场景，只让最后一次生效。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if flashID == scene.id { flashID = nil }
        }
    }
}

#if DEBUG
/// Xcode Canvas 预览：调试页（使用 Settings.shared 实时配置）。
struct DebugPanelView_Previews: PreviewProvider {
    static var previews: some View {
        DebugPanelView()
            .frame(width: 620, height: 620)
    }
}
#endif
