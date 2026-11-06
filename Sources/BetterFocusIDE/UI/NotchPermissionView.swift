// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 工具调用需要审批时，在灵动岛上展示的权限卡片。
struct NotchPermissionView: View {
    @ObservedObject var controller: PermissionController
    /// 观察 Settings 单例，使设置变更时视图能自动重新渲染（间距等即时生效）。
    @ObservedObject private var settings = Settings.shared
    var pinned = false
    var onTogglePin: () -> Void = {}

    private var request: PermissionRequest? { controller.request }

    /// 卡片内边距（实时取自 Settings）。
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    /// 来源展示名：走 AgentProvider.label——GUI 宿主用 host.name（具体 IDE 名称），
    /// CLI 宿主标成「产品（终端）」如 "Qoder CLI（Warp）"，JetBrains 兜底 "JetBrains"。
    private var sourceName: String {
        guard let req = request else { return "" }
        return AgentProvider.label(provider: req.provider,
                                   hostName: req.host?.name,
                                   bundleID: req.host?.bundle)
    }

    /// 徽章文本：取来源展示名的首字母大写。
    private var badgeText: String {
        return String(sourceName.prefix(1)).uppercased()
    }

    var body: some View {
        if let req = request {
            VStack(alignment: .leading, spacing: 8) {
                header(req)
                bodyText(req)
                if !req.detail.isEmpty {
                    detailBlock(req)
                }
                buttonsView(req)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 头部

    /// 头部：来源徽章 + "来源 · 动作标题" + 待处理数徽标。
    private func header(_ req: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            // 提供方徽章：优先使用真实 IDE 图标，回退到文字徽章；
            // host 缺失时用 sourceName（统一兜底名）匹配图标。
            // 图标身份与来源文字同源（CLI → 终端图标，GUI → 产品图标）。
            let iconID = AgentProvider.iconIdentity(
                provider: req.provider,
                hostName: req.host?.name ?? sourceName,
                bundleID: req.host?.bundle)
            IDEIconProvider.badgeView(
                hostName: iconID.name,
                bundleID: iconID.bundle,
                fallbackText: badgeText,
                tint: req.provider.tint,
                size: IDEIconProvider.badgeSize
            )
            .layoutPriority(1)
            Text("\(sourceName) · \(req.title)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 0)
            if controller.pendingCount > 0 {
                Text("+\(controller.pendingCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .liquidGlass(.capsule, fallback: Color.white.opacity(0.12))
                    .layoutPriority(1)
            }
            // 钉住开关：作为行内元素排在头部末尾，避免与计数徽标抢右上角空间。
            PinButton(pinned: pinned, action: onTogglePin)
                .layoutPriority(2)
        }
    }

    // MARK: - 正文

    /// 正文提示行："Agent（xxx）请求执行「标题」，是否允许？"，可多行换行。
    private func bodyText(_ req: PermissionRequest) -> some View {
        let agent = req.agent.isEmpty ? "" : "（\(req.agent)）"
        return Text("Agent\(agent) 请求执行「\(req.title)」，是否允许？")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 详情

    /// 详情块：等宽字体展示命令/路径，最多 4 行，带半透明圆角底。
    private func detailBlock(_ req: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(req.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.rounded(14), fallback: Color.white.opacity(0.06))
    }

    // MARK: - 按钮

    /// 三个决策按钮：允许 / 始终允许 / 拒绝。
    private func buttonsView(_ req: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            permissionButton("允许", decision: .allowOnce,
                             color: req.provider.tint, req: req)
            permissionButton("始终允许", decision: .allowAlways,
                             color: req.provider.tint.opacity(0.7), req: req)
            permissionButton("拒绝", decision: .reject,
                             color: Color(red: 0.9, green: 0.3, blue: 0.3), req: req)
        }
    }

    /// 单个决策按钮；已做出任一选择后全部禁用，选中项用实色、其余降透明度。
    private func permissionButton(_ label: String, decision: PermissionDecisionValue,
                                   color: Color, req: PermissionRequest) -> some View {
        let chosen = controller.choice == decision
        return Button {
            controller.decide(decision)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .liquidGlass(.rounded(14), variant: .clear,
                             tint: color,
                             interactive: controller.choice == nil,
                             fallback: chosen ? color : color.opacity(0.6))
        }
        .buttonStyle(.plain)
        .disabled(controller.choice != nil)
    }
}

#if DEBUG
/// Xcode Canvas 预览：构造一个 PermissionController 并注入模拟的权限请求。
struct NotchPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        let ctrl = PermissionController()
        let mock = PermissionRequest(
            requestID: "preview-req-1",
            provider: .qoder,
            sessionID: "preview-session",
            action: "shell",
            resources: ["swift build -c debug"],
            agent: "CodeAssistant",
            toolName: "bash",
            toolInput: nil,
            arrivedAt: Date()
        )
        ctrl.present(mock)
        return NotchPermissionView(controller: ctrl)
            .frame(width: 420)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
