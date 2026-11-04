// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 智能体完成一次回复时展示的横幅。点击可跳回产生该回复的 IDE（启用跳转时）。
struct NotchNoticeView: View {
    /// 通知控制器，用于读取未读队列数量并观察变化。
    @ObservedObject var controller: NoticeController
    let notice: TurnNotice
    var pinned = false
    var onTogglePin: () -> Void = {}
    let onTap: () -> Void
    /// 点击"已读"按钮的回调（不跳转 IDE，直接标记已读并关闭）。
    var onMarkRead: () -> Void = {}
    /// 有值时触发提供方徽章上的铃铛摆动动画。
    var bellSwingStart: Date?
    /// 观察 Settings 单例，使设置变更时视图能自动重新渲染。
    @ObservedObject private var settings = Settings.shared

    @State private var bellAngle: Double = 0
    @State private var bellScale: CGFloat = 1.0
    /// 抽屉效果：内容向右偏移量（跟随手指）。
    @State private var drawerOffset: CGFloat = 0
    /// 抽屉效果：可见宽度（从卡片满宽逐渐缩小到 0，模拟收入右侧抽屉）。
    @State private var drawerVisibleWidth: CGFloat? = nil

    /// 拖动关闭触发阈值（点）。
    private let swipeDismissThreshold: CGFloat = 80

    /// 徽章主题色：取提供方 tint，无对应提供方时回退到默认蓝。
    private var tint: Color {
        AgentProvider(rawValue: notice.provider)?.tint ?? Color(red: 0.29, green: 0.62, blue: 1.0)
    }

    /// 卡片内边距（实时取自 Settings，改动即时生效）
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    /// 徽章文本：取 providerName（已由 Controller 层处理为具体 IDE 名称）的首字母大写。
    private var badgeText: String {
        String(notice.providerName.prefix(1)).uppercased()
    }

    var body: some View {
        GeometryReader { geo in
            let fullW = geo.size.width
            // 可见宽度：拖动时随偏移缩小（抽屉效果），未拖动时为满宽。
            let visW = drawerVisibleWidth ?? fullW

            ZStack(alignment: .topTrailing) {
                Button(action: onTap) {
                    HStack(spacing: 10) {
                        // 提供方徽章：优先使用真实 IDE 图标，回退到文字徽章。
                        // host 缺失时（如 CLI 直发的测试消息）用 providerName 兜底，
                        // 使 opencode / qoder 等提供方仍能匹配到真实图标。
                        // 图标身份与标题同源（见 `AgentProvider.iconIdentity`）：
                        // CLI 用终端图标，GUI 用产品图标，不跟着被污染的 host 走。
                        let iconID = AgentProvider.iconIdentity(
                            provider: notice.provider,
                            hostName: notice.host?.name ?? notice.providerName,
                            bundleID: notice.host?.bundle)
                        IDEIconProvider.badgeView(
                            hostName: iconID.name,
                            bundleID: iconID.bundle,
                            fallbackText: badgeText,
                            tint: tint,
                            size: IDEIconProvider.badgeSize
                        )
                        .rotationEffect(.degrees(bellAngle))
                        .scaleEffect(bellScale)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("任务完成")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                            Text(notice.body)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                            if !notice.project.isEmpty {
                                Text(notice.project)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        // 未读通知计数徽章：队列中还有更多通知时显示
                        if controller.queueCount > 1 {
                            Text("+\(controller.queueCount)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.15),
                                            in: Capsule())
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 右上角工具栏：已读按钮 + 钉住开关
                HStack(spacing: 8) {
                    Button(action: onMarkRead) {
                        Text("已读")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 6,
                                                             style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("标记为已读（不跳转）")

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
                    .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
                }
                .padding(.top, 4)
                .padding(.trailing, inset)
            }
            // ── 抽屉效果：内容向右偏移 + 可见区域从左侧收缩 ──
            .frame(width: visW, alignment: .trailing)
            .offset(x: drawerOffset)
            .clipped()
            // 向右拖动视为已读并关闭（左拖无效果）
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let dx = max(0, value.translation.width)  // 只允许向右
                        drawerOffset = dx
                        drawerVisibleWidth = max(0, fullW - dx)
                    }
                    .onEnded { value in
                        let dx = max(0, value.translation.width)
                        if dx > swipeDismissThreshold {
                            // 超过阈值：动画收入右侧抽屉后标记已读
                            withAnimation(.easeIn(duration: 0.22)) {
                                drawerOffset = fullW
                                drawerVisibleWidth = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                drawerOffset = 0
                                drawerVisibleWidth = nil
                                onMarkRead()
                            }
                        } else {
                            // 未达阈值：弹回原位
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                drawerOffset = 0
                                drawerVisibleWidth = nil
                            }
                        }
                    }
            )
            .onAppear { startBellSwing() }
            .onChange(of: bellSwingStart) { startBellSwing() }
        }
    }
    
    /// 铃铛摆动：1.2 秒内 4 个正弦周期，幅度 20° 衰减到 0，缩放从 1.35 衰减到 1.0
    /// （Python BELL_SWING_*）。
    private func startBellSwing() {
        // 先放大再落定。
        bellScale = 1.35
        bellAngle = 20
        withAnimation(.easeOut(duration: 1.2)) {
            bellAngle = 0
            bellScale = 1.0
        }
    }
}

#if DEBUG
/// Xcode Canvas 预览：构造一条模拟的 turn_finished 通知横幅。
struct NotchNoticeView_Previews: PreviewProvider {
    static var previews: some View {
        let mock = TurnNotice(
            provider: "qoder",
            providerName: "Qoder",
            sessionID: "preview-session",
            title: "预览模式：代码重构已完成",
            body: "是否将当前工程拆分为 library + executable 双目标以支持 SwiftUI Preview？",
            project: "better-focus-ide",
            host: {
                var h = HostInfo()
                h.bundle = "com.qoder.ide"
                h.name = "Qoder IDE"
                h.path = "/Applications/Qoder IDE.app"
                h.cwd = "/Users/dev/better-focus-ide"
                return h
            }(),
            arrivedAt: Date(),
            jumpEnabled: true,
            fromCLI: false
        )
        let ctrl = NoticeController()
        NotchNoticeView(controller: ctrl, notice: mock, onTap: {}, onMarkRead: {})
            .frame(width: 380)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
