// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 灵动岛主容器视图：根据展开/收起状态路由到对应内容。
struct NotchView: View {
    @ObservedObject var service: NotchService
    /// 直接观察 Settings，确保任何设置变更（包括岛收起时 surfaceSize 不变的情况）
    /// 都能触发 SwiftUI 重新渲染，让卡片视图采纳新的字号 / 间距 / 颜色等。
    @ObservedObject private var settings = Settings.shared
    
    var body: some View {
        // 黑色岛面及其形变轮廓由 AppKit 画布（一层遮罩层）绘制；SwiftUI 层只承载
        // 内容，保持透明，绝不与形状形变争抢。
        ZStack(alignment: .top) {
            if service.expanded || service.closingCard != nil {
                expandedContent
                
                // 气泡覆盖层：展开时气泡显示在卡片上方，点击可收起
                bubbleWithGlow
                    .frame(width: service.geometry.collapsed.width,
                           height: service.geometry.collapsed.height)
                    .frame(maxWidth: .infinity)  // 水平居中
                    .contentShape(Rectangle())
                    .onTapGesture {
                        service.collapse()
                    }
            } else {
                collapsedContent
            }
        }
        .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
        .clipped()  // 防止 SwiftUI 内容在 AppKit 壳布局完成前溢出
        .foregroundStyle(.white)
        // 表面点击：仅收起态或无卡片时处理；展开的交互式卡片由自身处理交互，
        // 背景点击不应触发收起（否则点选项间隙会误关卡片）。
        .contentShape(Rectangle())
        .onTapGesture {
            guard !service.expanded || service.activeCard == .none else { return }
            service.handleSurfaceTap()
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }
    
    /// 气泡内容（仅有待处理项时显示圆点 + 计数）
    private var bubbleContent: some View {
        HStack(spacing: 4) {
            if service.pendingTotal > 0 {
                Circle()
                    .fill(Color(red: service.pendingTint.r,
                                green: service.pendingTint.g,
                                blue: service.pendingTint.b))
                    .frame(width: NotchLayout.idleDotRadius * 2,
                           height: NotchLayout.idleDotRadius * 2)
                if service.pendingTotal > 1 {
                    Text("\(service.pendingTotal)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: service.pendingTint.r,
                                               green: service.pendingTint.g,
                                               blue: service.pendingTint.b))
                }
            }
            // 空闲状态不显示任何内容，仅靠外缘呼吸灯提示
        }
    }
    
    /// 气泡内容。外缘呼吸辉光由 AppKit 画布层绘制（NotchCanvas.glowLayer），
    /// 不再在 SwiftUI 层渲染——因为黑色岛面轮廓由 AppKit 遮罩裁剪，SwiftUI 内容
    /// 无法越出气泡外缘。
    private var bubbleWithGlow: some View {
        bubbleContent
    }
    
    private var collapsedContent: some View {
        // 纯黑胶囊 + 居中圆点（对齐 Python 空闲态）。有待处理项时圆点用提供方主题色并显示计数。
        bubbleWithGlow
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var expandedContent: some View {
        VStack(spacing: 12) {
            // 撤下动画期间展示 closingCard 的内容。
            let card = service.activeCard != .none ? service.activeCard : (service.closingCard ?? .none)
            switch card {
            case .question:
                NotchAgentQuestionView(controller: service.questionController,
                                       pinned: service.pinned,
                                       onTogglePin: { service.togglePin() })
            case .permission:
                NotchPermissionView(controller: service.permissionController,
                                    pinned: service.pinned,
                                    onTogglePin: { service.togglePin() })
            case .notice:
                if let notice = service.noticeController.notice {
                    NotchNoticeView(controller: service.noticeController,
                                    notice: notice,
                                    pinned: service.pinned,
                                    onTogglePin: { service.togglePin() },
                                    onTap: { service.noticeController.tapped() },
                                    onMarkRead: { service.noticeController.markRead() },
                                    bellSwingStart: service.bellSwingStart)
                }
            case .history:
                NotchHistoryView(controller: service.historyController,
                                 pinned: service.pinned,
                                 onTogglePin: { service.togglePin() }) { entry in
                    service.historyController.tapped(entry)
                    service.collapse()
                }
            case .none:
                // 无卡片活动——不显示任何东西（toggle 不会展开到 .none）。
                EmptyView()
            }
        }
        .padding(.top, service.geometry.safeContentTop)
    }
}

// MARK: - NotchShape

/// 灵动岛轮廓形状。
///
/// `attached` 为 true 时绘制贴合屏幕顶边的"液态岛"轮廓（顶部直角、底部圆肩）；
/// 否则是普通圆角矩形。关键不变量：`path(in:)` 忽略 `rect.origin`，故末尾必须把
/// 局部坐标描出的路径平移到 rect 原点，否则遮罩会与居中的 host 水平错位。
struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    var floatingGap: CGFloat? = nil
    
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    
    static func island(height: CGFloat, geometry: NotchGeometry) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height), floatingGap: geometry.floatingGap)
    }
    
    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        if let floatingGap {
            return Path(NotchLayout.capsulePath(in: rect, gap: floatingGap))
        }
        let shoulder = NotchLayout.shoulder(height: rect.height)
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        // 轮廓在局部坐标描出；平移到岛矩形的原点，使遮罩与居中的 host 对齐。
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

#if DEBUG
/// Xcode Canvas 预览：展示灵动岛主容器的收起态（空闲岛面）。
/// 使用 NotchService.shared 单例，预览构建时会自动初始化。
struct NotchView_Previews: PreviewProvider {
    static var previews: some View {
        NotchView(service: NotchService.shared)
            .preferredColorScheme(.dark)
    }
}
#endif
