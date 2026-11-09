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
                    .onAppear { service.collapsedContentDidLayout() }
            }
        }
        .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
        .onChange(of: service.surfaceSize) { _, _ in
            service.collapsedContentDidLayout()
        }
        // 提问 / 权限 / 通知占主体时，进行中的进度缩成卡片底边这条线。
        // 挂在整张岛的底边，而不是顶部气泡里，避免和气泡下沿再叠一条。
        .overlay(alignment: .bottom) {
            TodoProgressLine(service: service, todos: service.todoController, placement: .cardEdge)
        }
        .modifier(IslandGlassClip())
        .foregroundStyle(.white)
        // 展开态不要在整张卡片上挂点击。祖先的 onTapGesture 会和「发送」等按钮抢同一次点击，
        // 按钮看起来可点，动作却被这层手势吃掉；键盘不经过命中测试，所以 Enter 仍然有效。
        // 收起只认气泡；展开时只有顶部那一块气泡负责收起。
        .background {
            if !(service.expanded || service.closingCard != nil) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { service.handleSurfaceTap() }
            }
        }
        .overlay(alignment: .top) {
            if service.expanded || service.closingCard != nil {
                Color.clear
                    .frame(width: service.geometry.collapsed.width,
                           height: service.geometry.collapsed.height)
                    .contentShape(Rectangle())
                    .onTapGesture { service.collapse() }
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

            // 收起态，以及展开后顶部那颗气泡：进行中才画。
            // 卡片底边已经在画同一条线时，这里留空，避免上下各一条。
            TodoProgressLine(service: service, todos: service.todoController, placement: .bubble)
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
        // 控件单独成组。间距 0：相邻行不融合，每条都保留自己的折光棱边。
        .liquidGlassGroup()
    }
}

/// 进行中的待办进度线。气泡下沿和展开卡片底边共用这一套画法。
///
/// 自己订阅 `TodoController`：通知 / 提问 / 权限在屏时进度不换卡，
/// `NotchService` 不会因此再发布一次，线仍要跟着刷新。
private struct TodoProgressLine: View {
    @ObservedObject var service: NotchService
    @ObservedObject var todos: TodoController
    var placement: NotchService.ProgressLineSlot

    private var slot: NotchService.ProgressLineSlot {
        let card = service.activeCard != .none ? service.activeCard : (service.closingCard ?? .none)
        return NotchService.progressLineSlot(
            expanded: service.expanded,
            closing: service.closingCard != nil,
            card: card,
            inProgress: todos.hasTodo && !todos.progress.isFinished)
    }

    var body: some View {
        if slot == placement {
            let fraction = todos.progress.fraction
            let tint = todos.provider.tint
            let horizontal = placement == .bubble
                ? NotchLayout.progressLineBubbleInset
                : NotchLayout.progressLineInset(cardHeight: service.surfaceSize.height)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: NotchLayout.progressLineHeight)
            .padding(.horizontal, horizontal)
            .padding(.bottom, NotchLayout.progressLineBottomPadding)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: fraction)
        }
    }
}

/// 液态玻璃的棱边折光画在形状外侧。macOS 26+ 不能再 `.clipped()`，
/// 否则卡片和控件的边缘光线会被齐根切掉，只剩一块平的磨砂。
private struct IslandGlassClip: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content.clipped()
        }
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
