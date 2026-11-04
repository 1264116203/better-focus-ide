// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 气泡边缘呼吸灯覆盖层。
///
/// 当有未处理的通知卡片时，在气泡（收起态灵动岛）周围绘制辉光描边，
/// 透明度按正弦波呼吸。颜色跟随通知提供方的主题色。
/// reduce motion 启用时降级为静态半透明描边。
struct BreathingGlowOverlay: View {
    /// 辉光颜色（nil 时不显示）
    let tint: Color?
    /// 灵动岛轮廓形状（使用 NotchShape 匹配气泡实际外形）
    let shape: NotchShape
    
    /// 呼吸动画的当前透明度
    @State private var glowOpacity: Double = 0
    
    /// 是否启用 reduce motion（从 Settings 读取）
    private var reduceMotion: Bool { Settings.shared.reduceMotionResolved }
    
    /// 单次呼吸周期（秒）
    private let breathePeriod: TimeInterval = 1.8
    
    /// 辉光层配置（多层叠加实现更强效果）
    /// 参数大幅增强，使气泡（小尺寸）上的辉光也能清晰可见
    private let glowLayers: [(lineWidth: CGFloat, blur: CGFloat, maxOpacity: Double)] = [
        (24, 30, 0.95),  // 外层：超大模糊，远距离辉光
        (14, 18, 0.8),   // 中层：强扩散
        (8, 8, 0.65),    // 内层：明显描边
    ]
    
    var body: some View {
        guard let tint = tint else {
            return AnyView(EmptyView())
        }
        
        // reduce motion：静态半透明描边，不闪烁
        if reduceMotion {
            return AnyView(
                ZStack {
                    // 多层静态辉光
                    ForEach(0..<glowLayers.count, id: \.self) { i in
                        shape
                            .stroke(tint, lineWidth: glowLayers[i].lineWidth)
                            .blur(radius: glowLayers[i].blur * 0.5)
                            .opacity(0.4)
                    }
                }
            )
        }
        
        // 正常模式：正弦呼吸动画，多层辉光叠加
        return AnyView(
            ZStack {
                // 多层辉光叠加，产生更强的发光效果
                ForEach(0..<glowLayers.count, id: \.self) { i in
                    shape
                        .stroke(tint, lineWidth: glowLayers[i].lineWidth)
                        .blur(radius: glowLayers[i].blur)
                        .opacity(glowOpacity * glowLayers[i].maxOpacity)
                }
            }
            .onAppear {
                // 初始透明度设为峰值
                glowOpacity = 1.0
                // 启动呼吸循环
                withAnimation(
                    .easeInOut(duration: breathePeriod / 2)
                    .repeatForever(autoreverses: true)
                ) {
                    glowOpacity = 0.2
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
            screen: CGRect(x: 0, y: 0, width: 200, height: 32),
            safeAreaTop: 32,
            cameraWidth: 150
        )
        let previewShape = NotchShape.island(height: 32, geometry: previewGeometry)
        
        VStack(spacing: 60) {
            // 有呼吸灯
            ZStack {
                Color.black
                BreathingGlowOverlay(tint: .blue, shape: previewShape)
            }
            .frame(width: 200, height: 40)
            
            // 无呼吸灯
            ZStack {
                Color.black
                BreathingGlowOverlay(tint: nil, shape: previewShape)
            }
            .frame(width: 200, height: 40)
            
            // 紫色辉光
            ZStack {
                Color.black
                BreathingGlowOverlay(tint: .purple, shape: previewShape)
            }
            .frame(width: 200, height: 40)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
#endif
