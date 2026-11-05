// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 卡片右上角的「钉住」开关。
///
/// 统一了图标尺寸、未固定时的 45° 旋转姿态、激活色与命中区域，
/// 各卡片把它作为**普通行内元素**排进头部 HStack——不要再以 ZStack 覆盖层
/// 叠到右上角，否则会与头部末尾的翻页步进器 / 计数徽标抢同一块空间。
///
/// 配色**固定为灰阶**、不跟随主题强调色：图钉是"视图状态"开关而非品牌点缀，
/// 一旦染上主题色就会与头部其他强调元素（提供方色点、进度条）抢注意力。
struct PinButton: View {
    var pinned: Bool
    var action: () -> Void

    /// 命中区域边长：比 12pt 图标略大，避免刘海上的小图标难点中。
    private let hitSize: CGFloat = 16

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(pinned ? 0 : 45))
                .foregroundStyle(PinColors.tint(pinned: pinned))
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
        .accessibilityLabel(pinned ? "取消固定" : "固定卡片")
    }
}

/// 图钉的固定灰阶配色（不读取主题强调色）。
enum PinColors {
    /// 已固定：中灰（比未固定明显、但不刺眼，与黑色岛面保持低反差）。
    static let active = Color.white.opacity(0.6)
    /// 未固定：暗灰。
    static let inactive = Color.white.opacity(0.4)

    static func tint(pinned: Bool) -> Color {
        pinned ? active : inactive
    }
}
