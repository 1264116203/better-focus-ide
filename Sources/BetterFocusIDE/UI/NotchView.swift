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
                
                // 气泡覆盖层：展开时气泡显示在卡片上方。
                // 点击收起统一由外层那个带坐标的 onTapGesture 处理。若在这里也挂一个手势，
                // 同一次点击会先 collapse() 让 expanded 变 false，外层 guard 随即放行
                // 并 toggle() → expand()，于是「收起 → 立刻弹回」反复闪烁。
                bubbleWithGlow
                    .frame(width: service.geometry.collapsed.width,
                           height: service.geometry.collapsed.height)
                    .frame(maxWidth: .infinity)  // 水平居中
            } else {
                collapsedContent
            }
        }
        .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
        .clipped()  // 防止 SwiftUI 内容在 AppKit 壳布局完成前溢出
        .foregroundStyle(.white)
        // 表面点击：整层只用这一个手势，按落点区分。
        // - 收起态：整块气泡都可点，走常规 toggle（恢复通知 / 展开待处理卡片 / 历史）。
        // - 展开态：只有顶部气泡区域可收起；卡片内容区留给按钮和选项，
        //   点选项间隙不会误关卡片。
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .local) { location in
            if service.expanded || service.closingCard != nil {
                let w = service.geometry.collapsed.width
                let h = service.geometry.collapsed.height
                let bubble = CGRect(x: (service.surfaceSize.width - w) / 2,
                                    y: 0, width: w, height: h)
                if bubble.contains(location) { service.collapse() }
            } else {
                service.handleSurfaceTap()
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }
    
    /// 气泡内容（仅有待处理项时显示圆点 + 计数）
    private var bubbleContent: some View {
        ZStack(alignment: .bottom) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 收起态进度：零额外高度，余光即可看到推进；全部完成后自动消失。
            if service.todoController.hasTodo,
               !service.todoController.progress.isFinished {
                todoProgressLine
            }
        }
    }

    /// 贴气泡下沿的进度线。
    ///
    /// 高度只有 2pt 且留了左右内边距——气泡的圆角轮廓由 AppKit 遮罩裁出，
    /// 让线条贴到边缘会被切掉端头，看起来像「线画歪了」。
    private var todoProgressLine: some View {
        let fraction = service.todoController.progress.fraction
        let tint = service.todoController.provider.tint
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 3)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: fraction)
        .transition(.opacity)
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
            case .todo:
                NotchTodoView(controller: service.todoController,
                              pinned: service.pinned,
                              onTogglePin: { service.togglePin() })
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
