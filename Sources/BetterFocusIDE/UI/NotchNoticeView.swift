// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 智能体完成一次回复时展示的横幅。点击可跳回产生该回复的 IDE（启用跳转时）。
struct NotchNoticeView: View {
    let notice: TurnNotice
    var pinned = false
    var onTogglePin: () -> Void = {}
    let onTap: () -> Void
    /// 有值时触发提供方徽章上的铃铛摆动动画。
    var bellSwingStart: Date?
    /// 观察 Settings 单例，使设置变更时视图能自动重新渲染。
    @ObservedObject private var settings = Settings.shared

    @State private var bellAngle: Double = 0
    @State private var bellScale: CGFloat = 1.0

    /// 徽章主题色：取提供方 tint，无对应提供方时回退到默认蓝。
    private var tint: Color {
        AgentProvider(rawValue: notice.provider)?.tint ?? Color(red: 0.29, green: 0.62, blue: 1.0)
    }

    /// 卡片内边距（实时取自 Settings，改动即时生效）
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    // 提供方徽章 + 铃铛摆动动画
                    Text(String(notice.providerName.prefix(1)))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.9),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .rotationEffect(.degrees(bellAngle))
                        .scaleEffect(bellScale)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Text(notice.body)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        if !notice.project.isEmpty {
                            Text(notice.project)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 钉住开关：统一使用主题色
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
            .padding(.trailing, inset)  // 与左侧对称
            .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
        }
        .onAppear { startBellSwing() }
        .onChange(of: bellSwingStart) { startBellSwing() }
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
            body: "已将所有注释翻译为中文，编译通过。",
            project: "better-focus-ide",
            host: nil,
            arrivedAt: Date(),
            jumpEnabled: true,
            fromCLI: false
        )
        NotchNoticeView(notice: mock, onTap: {})
            .frame(width: 380)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
