// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 卡片右上角的「钉住」开关。
///
/// 统一了图标尺寸、未固定时的 45° 旋转姿态、激活色与命中区域，
/// 各卡片把它作为**普通行内元素**排进头部 HStack——不要再以 ZStack 覆盖层
/// 叠到右上角，否则会与头部末尾的翻页步进器 / 计数徽标抢同一块空间。
struct PinButton: View {
    var pinned: Bool
    var action: () -> Void

    @ObservedObject private var settings = Settings.shared

    /// 命中区域边长：比 12pt 图标略大，避免刘海上的小图标难点中。
    private let hitSize: CGFloat = 16

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(pinned ? 0 : 45))
                .foregroundStyle(pinned
                    ? Color(red: settings.accentRGB.r,
                            green: settings.accentRGB.g,
                            blue: settings.accentRGB.b)
                    : Color.white.opacity(0.4))
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
        .accessibilityLabel(pinned ? "取消固定" : "固定卡片")
    }
}
