// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 灵动岛边缘呼吸灯覆盖层。
///
/// 当卡片出现时，沿灵动岛轮廓绘制一圈辉光描边，透明度按正弦波节奏呼吸。
/// 颜色跟随当前提供方的主题色；reduce motion 启用时降级为静态半透明描边。
struct BreathingGlowOverlay: View {
    /// 辉光颜色（nil 时不显示）
    let tint: Color?
    /// 灵动岛轮廓形状
    let shape: NotchShape
    /// 描边宽度（默认 2pt，与 NotchLayout.outlineWidth 对齐）
    var lineWidth: CGFloat = 2
    /// 模糊半径（模拟辉光扩散）
    var blurRadius: CGFloat = 3
    
    /// 呼吸动画的当前透明度
    @State private var glowOpacity: Double = 0
    
    /// 是否启用 reduce motion（从 Settings 读取）
    private var reduceMotion: Bool { Settings.shared.reduceMotionResolved }
    
    /// 单次呼吸周期（秒）
    private let breathePeriod: TimeInterval = 1.8
    
    var body: some View {
        guard let tint = tint else {
            return AnyView(EmptyView())
        }
        
        // reduce motion：静态半透明描边，不闪烁
        if reduceMotion {
            return AnyView(
                shape
                    .stroke(tint, lineWidth: lineWidth)
                    .opacity(0.5)
                    .blur(radius: blurRadius * 0.5)
            )
        }
        
        // 正常模式：正弦呼吸动画
        return AnyView(
            shape
                .stroke(tint, lineWidth: lineWidth)
                .opacity(glowOpacity)
                .blur(radius: blurRadius)
                .onAppear {
                    // 初始透明度设为峰值
                    glowOpacity = 0.7
                    // 启动呼吸循环
                    withAnimation(
                        .easeInOut(duration: breathePeriod / 2)
                        .repeatForever(autoreverses: true)
                    ) {
                        glowOpacity = 0.15
                    }
                }
                .onDisappear {
                    glowOpacity = 0
                }
        )
    }
}

#if DEBUG
/// Xcode Canvas 预览：呼吸灯覆盖层效果
struct BreathingGlowOverlay_Previews: PreviewProvider {
    static var previews: some View {
        let previewGeometry = NotchGeometry(
            screen: CGRect(x: 0, y: 0, width: 400, height: 80),
            safeAreaTop: 32,
            cameraWidth: 150
        )
        let previewShape = NotchShape.island(height: 80, geometry: previewGeometry)
        
        VStack(spacing: 40) {
            // 正常模式
            ZStack {
                Color.black
                BreathingGlowOverlay(tint: .blue, shape: previewShape)
            }
            .frame(width: 400, height: 80)
            .clipShape(previewShape)
            
            // 无呼吸灯状态
            ZStack {
                Color.black
                BreathingGlowOverlay(tint: nil, shape: previewShape)
            }
            .frame(width: 400, height: 80)
            .clipShape(previewShape)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
#endif
