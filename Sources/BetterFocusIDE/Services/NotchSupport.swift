// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import CoreGraphics

// MARK: - NotchLayout

/// 灵动岛布局常量。
///
/// 大部分尺寸在调用时实时读取 Settings，使改动立即生效；固定几何量（肩部、
/// 头部高度等）作为常量。所有可配置项均对齐 Python 参考实现。
enum NotchLayout {
    /// 肩部宽度：灵动岛轮廓两侧的内收量。
    static let shoulder: CGFloat = 14
    static let horizontalInset: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let spacing: CGFloat = 12
    static let bottomInset: CGFloat = 16
    /// 头部 + 间距 + 底部内收构成的"边框"总高。
    static var chromeHeight: CGFloat { headerHeight + spacing + bottomInset }
    
    // MARK: - 对齐 Python 的尺寸（实时读 Settings，改动即时生效）
    
    /// 黄金分割比例：卡片:物理刘海 = 1.5:0.618，故卡片宽 = 刘海宽 × 1.5 ÷ 0.618（≈2.427 倍）。
    static let goldenSectionDivisor: CGFloat = 0.618
    static let goldenSectionMultiplier: CGFloat = 1.5

    /// 物理刘海宽度（pt）：用摄像头左右两侧「顶部辅助安全区」反推（屏宽 − 左 − 右），
    /// 机型自适应。无刘海屏或辅助区不可用时返回 nil。与 NotchService.detectCameraWidth 同源。
    static func physicalNotchWidth(of screen: NSScreen) -> CGFloat? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              !left.isEmpty, !right.isEmpty else { return nil }
        let width = screen.frame.width - left.width - right.width
        return width > 0 ? width : nil
    }

    /// 当前刘海屏（safeAreaInsets.top > 0）；无刘海屏返回 nil。
    static var notchedScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
    }

    /// 四类卡片统一宽度：跟随刘海时 = 刘海宽 × 1.5 ÷ 0.618（黄金分割，机型自适应）；
    /// 否则用手动 notifyWidth。无刘海屏（外接显示器等）即便开启跟随也回退手动值。
    static var resolvedCardWidth: CGFloat {
        if Settings.shared.cardFollowsNotch,
           let screen = notchedScreen, let notch = physicalNotchWidth(of: screen) {
            return (notch * goldenSectionMultiplier / goldenSectionDivisor).rounded()
        }
        return CGFloat(Settings.shared.notifyWidth)
    }

    /// 通知横幅宽高（Python EXPANDED_WIDTH × EXPANDED_HEIGHT）。
    static var expandedWidth: CGFloat { resolvedCardWidth }
    static var expandedHeight: CGFloat { CGFloat(Settings.shared.notifyHeight) }
    /// 问题 / 权限卡片宽度（与通知横幅统一）。
    static var questionCardWidth: CGFloat { resolvedCardWidth }
    /// 历史面板宽度（Python HISTORY_WIDTH = EXPANDED_WIDTH）。
    static var historyWidth: CGFloat { resolvedCardWidth }
    
    // 卡片布局度量（Python config.py）
    static var cardInset: CGFloat { CGFloat(Settings.shared.cardInset) }
    static let cardHeaderHeight: CGFloat = 26
    static let cardGap: CGFloat = 8
    static var questionBodyFont: CGFloat { CGFloat(Settings.shared.bodyFont) }
    static var questionOptionRowMin: CGFloat { CGFloat(Settings.shared.optionRowMin) }
    /// 选项标签字号（与 NotchAgentQuestionView 硬编码的 optionFontSize 对齐）。
    static let optionFont: CGFloat = 12
    /// 选项描述字号（与 NotchAgentQuestionView 硬编码的 descFontSize 对齐）。
    static let descFont: CGFloat = 10.5
    static let questionOtherRowHeight: CGFloat = 30
    /// 发送按钮高度：必须与 NotchAgentQuestionView.sendButton 的 .frame(height:) 一致。
    static let questionSendHeight: CGFloat = 26
    static let questionMaxBodyLines: Int = 4
    static let permissionButtonHeight: CGFloat = 32
    static let permissionButtonGap: CGFloat = 8
    
    // 空闲小圆点（Python IDLE_DOT_RADIUS / IDLE_DOT_PULSE）
    static let idleDotRadius: CGFloat = 3.0
    static let idleDotPulse: CGFloat = 1.2
    static var idlePulsePeriod: TimeInterval { Settings.shared.idlePulsePeriod }
    
    // 强调色（Python ACCENT_COLOR）
    static var accentColor: (r: Double, g: Double, b: Double) {
        let c = Settings.shared.accentRGB
        return (r: c.r, g: c.g, b: c.b)
    }
    
    /// 该高度表面的圆角半径（上限 = radius_expanded）。
    static func surfaceRadius(height: CGFloat) -> CGFloat {
        min(CGFloat(Settings.shared.radiusExpanded), height * 0.34)
    }
    /// 该高度下的实际肩部（不超过高度 19%）。
    static func shoulder(height: CGFloat) -> CGFloat { min(shoulder, height * 0.19) }
    
    /// 可选描边的线宽。
    static let outlineWidth: CGFloat = 2
    
    // MARK: 胶囊
    
    /// 胶囊上下各留出的菜单栏边距。
    static let capsuleMargin: CGFloat = 2
    
    /// 闭合胶囊两端是圆的（端帽半径 = radius_bubble）。
    static func capsuleRadius(height: CGFloat) -> CGFloat {
        min(max(0, height) / 2, CGFloat(Settings.shared.radiusBubble))
    }
    
    /// 胶囊轮廓路径。
    ///
    /// 用贝塞尔近似圆角（handle 系数 1 − 0.55228475），在 rect 内按 gap 内收后绘制。
    static func capsulePath(in rect: CGRect, gap: CGFloat) -> CGPath {
        let body = capsuleBody(in: rect, gap: gap)
        let corner = min(capsuleRadius(height: body.height), body.width / 2)
        let handle = corner * (1 - 0.55228475)
        let (left, right, top, bottom) = (body.minX, body.maxX, body.minY, body.maxY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + corner, y: top))
        path.addLine(to: CGPoint(x: right - corner, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + corner), control1: CGPoint(x: right - handle, y: top),
                      control2: CGPoint(x: right, y: top + handle))
        path.addLine(to: CGPoint(x: right, y: bottom - corner))
        path.addCurve(to: CGPoint(x: right - corner, y: bottom), control1: CGPoint(x: right, y: bottom - handle),
                      control2: CGPoint(x: right - handle, y: bottom))
        path.addLine(to: CGPoint(x: left + corner, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - corner), control1: CGPoint(x: left + handle, y: bottom),
                      control2: CGPoint(x: left, y: bottom - handle))
        path.addLine(to: CGPoint(x: left, y: top + corner))
        path.addCurve(to: CGPoint(x: left + corner, y: top), control1: CGPoint(x: left, y: top + handle),
                      control2: CGPoint(x: left + handle, y: top))
        path.closeSubpath()
        return path
    }
    
    /// rect 内按肩部与 gap 内收后的胶囊主体矩形。
    static func capsuleBody(in rect: CGRect, gap: CGFloat) -> CGRect {
        let width = max(0, rect.width), height = max(0, rect.height)
        let side = min(shoulder(height: height), width / 2)
        let inset = min(max(0, gap), height / 2)
        return CGRect(x: rect.minX + side, y: rect.minY + inset,
                      width: width - side * 2, height: height - inset * 2)
    }
}

// MARK: - NotchGeometry

/// 灵动岛相对屏幕的几何信息：是否刘海屏、摄像头尺寸、菜单栏高度、各状态尺寸与帧位置。
struct NotchGeometry: Equatable {
    let screen: CGRect
    var surfaceShift: CGFloat = 0
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let isNotched: Bool
    let menuBarHeight: CGFloat
    let floatingGap: CGFloat?
    
    init(screen: CGRect, safeAreaTop: CGFloat, cameraWidth: CGFloat,
         menuBarHeight: CGFloat = 24) {
        self.screen = screen
        self.cameraWidth = min(max(0, cameraWidth), screen.width * 0.7)
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && cameraWidth.isFinite && cameraWidth > 0
        floatingGap = nil
        self.cameraHeight = isNotched ? min(max(0, safeAreaTop), 64) : menuBarHeight
        self.menuBarHeight = max(cameraHeight, menuBarHeight)
    }
    
    /// 是否为"悬浮胶囊"形态（有 floatingGap）。
    var floats: Bool { floatingGap != nil }
    
    /// 内容顶部安全区：悬浮形态用底部内收，刘海形态避开摄像头。
    var safeContentTop: CGFloat { floats ? NotchLayout.bottomInset : cameraHeight + CGFloat(Settings.shared.notchTopPadding) }
    
    var stripHeight: CGFloat { cameraHeight }
    
    /// 气泡基础尺寸（不含 padding）：
    /// 跟随刘海且为刘海屏时取物理摄像头区域（机型自适应）；否则用手动设置。
    /// 无刘海屏（外接显示器等）即便开启跟随也回退手动值。
    ///
    /// 宽度补偿：渲染轮廓 NotchShape(attached:) 两侧各内收 shoulder，若 base 宽直接
    /// 取刘海宽，黑色主体会比刘海小一圈、缩在刘海内，左右辉光被挤在刘海硬件上看不见。
    /// 故 base 宽 = 刘海宽 + 2×shoulder，使渲染主体恰好与刘海齐平，左右辉光落到
    /// 刘海外的菜单栏上清晰可见。高度不补偿（主体高 = 刘海高）。
    private var bubbleBase: CGSize {
        if Settings.shared.bubbleFollowsNotch && isNotched {
            let shoulder = NotchLayout.shoulder(height: cameraHeight)
            return CGSize(width: cameraWidth + shoulder * 2, height: cameraHeight)
        }
        return CGSize(width: CGFloat(Settings.shared.bubbleWidth),
                      height: CGFloat(Settings.shared.bubbleHeight))
    }

    /// 收起态尺寸（基础尺寸 + 额外余量）。
    /// bubbleWidthPadding/bubbleHeightPadding 用于增加额外空间以容纳呼吸灯辉光效果
    var collapsed: CGSize {
        let base = bubbleBase
        let widthPadding = CGFloat(Settings.shared.bubbleWidthPadding)
        let heightPadding = CGFloat(Settings.shared.bubbleHeightPadding)
        return CGSize(
            width: base.width + widthPadding,
            height: base.height + heightPadding
        )
    }
    
    /// 空闲气泡尺寸（无卡片时刘海处的黑色气泡形状）。
    var idleBubbleSize: CGSize { bubbleBase }
    
    /// 静止尺寸：显示内容时取 collapsed，否则使用空闲气泡尺寸。
    func restingSize(showsContent: Bool) -> CGSize {
        if showsContent { return collapsed }
        return idleBubbleSize
    }
    
    /// 给定尺寸在屏幕坐标系中的 frame。
    ///
    /// Frame 顶边始终对齐屏幕顶边。收起态气泡位于刘海位置，展开态卡片向下延伸。
    /// 水平位置根据 showsContent 参数选择不同的偏移量：
    /// - showsContent = false（收起态气泡）：使用 bubbleHorizontalOffset
    /// - showsContent = true（展开态卡片）：使用 cardHorizontalOffset
    func frame(for size: CGSize, showsContent: Bool = true) -> CGRect {
        let offsetX = showsContent
            ? CGFloat(Settings.shared.cardHorizontalOffset)
            : CGFloat(Settings.shared.bubbleHorizontalOffset)
        let x = screen.midX - size.width / 2 + offsetX
        let y = screen.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - NotchMotion

/// 弹性动画物理模型（对齐 Python `motion.spring_for`）。
enum NotchMotion {
    /// 弹簧参数：时长 + 回弹量。
    struct Spring: Equatable {
        var duration: TimeInterval
        var bounce: Double
        
        /// 在给定时刻的进度（0→1，可因回弹短暂越过 1）。欠阻尼用衰减正弦，临界阻尼用单调式。
        func progress(at time: TimeInterval) -> Double {
            guard time > 0 else { return 0 }
            let natural = 2 * Double.pi / duration
            let damping = 1 - bounce
            if damping >= 1 { return 1 - exp(-natural * time) * (1 + natural * time) }
            let damped = natural * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * natural * time)
                * (cos(damped * time) + damping * natural / damped * sin(damped * time))
        }
        
        /// 首个超调峰值比例（bounce=0 时为 0）。
        var overshoot: Double {
            guard bounce > 0 else { return 0 }
            let damping = 1 - bounce
            return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
        }
        
        /// 当超调位移会超过 `limit` 时，反解出恰好满足上限的 bounce。
        func limited(travel: CGFloat, limit: CGFloat) -> Spring {
            guard bounce > 0, travel > 0, Double(travel) * overshoot > Double(limit) else { return self }
            let share = log(Double(max(limit, 0.01) / travel))
            return Spring(duration: duration, bounce: 1 + share / (Double.pi * Double.pi + share * share).squareRoot())
        }
    }
    
    // 弹簧与 Python motion.spring_for 对齐：生长弹簧按 MOTION_GROW_BOUNCE 回弹，
    // 收缩弹簧临界阻尼（无超调），OVERSHOOT_LIMIT=12。时长按 1 / animation_speed
    // 缩放（速度越高越早结束）。reduce-motion 把生长回弹强制为 0——形变照跑，
    // 只是单调不回弹（Python spring_for reduce_motion）。
    private static var speedScale: Double {
        let s = Settings.shared.animationSpeed
        return s > 0.01 ? 1.0 / s : 1.0
    }
    private static var growBounce: Double {
        Settings.shared.reduceMotionResolved ? 0 : Settings.shared.motionGrowBounce
    }
    static var growingWidth: Spring { Spring(duration: 0.42 * speedScale, bounce: growBounce) }
    static var growingHeight: Spring { Spring(duration: 0.36 * speedScale, bounce: growBounce) }
    static var shrinkingWidth: Spring { Spring(duration: 0.30 * speedScale, bounce: 0.0) }
    static var shrinkingHeight: Spring { Spring(duration: 0.26 * speedScale, bounce: 0.0) }
    /// 超调位移上限（像素）。
    static let overshootLimit: CGFloat = 12
    /// 悬停重展开的回弹缩放：悬停触发展开用更弱的超调，避免收起后气泡明显"放大再缩小"。
    static let hoverBounceScale: Double = 0.4
    /// 判定"已落定"的距离阈值。
    static let settledDistance: CGFloat = 0.5
    
    /// 依据增长还是收缩、宽还是高，选出对应弹簧并按上限约束超调。
    /// `bounceScale` 仅缩放生长回弹（收缩本就临界阻尼无超调）；1 = 正常手感。
    static func spring(from: CGFloat, to: CGFloat, width: Bool, bounceScale: Double = 1) -> Spring {
        let base = to > from ? (width ? growingWidth : growingHeight) : (width ? shrinkingWidth : shrinkingHeight)
        let scaled = to > from ? Spring(duration: base.duration, bounce: base.bounce * bounceScale) : base
        return scaled.limited(travel: abs(to - from), limit: overshootLimit)
    }
    
    /// 在给定时刻插值出的尺寸（宽高各按自己的弹簧独立推进）。
    static func size(at time: TimeInterval, from: CGSize, to: CGSize, bounceScale: Double = 1) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            guard start != end else { return end }
            let spring = spring(from: start, to: end, width: width, bounceScale: bounceScale)
            return max(0, start + (end - start) * CGFloat(spring.progress(at: time)))
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
    
    /// 以 240Hz 步长扫描，找出宽高都落定到目标所需的时长。
    static func settlingTime(from: CGSize, to: CGSize, bounceScale: Double = 1) -> TimeInterval {
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            let size = size(at: time, from: from, to: to, bounceScale: bounceScale)
            if abs(size.width - to.width) > settledDistance || abs(size.height - to.height) > settledDistance {
                settled = time + step
            }
            time += step
        }
        return settled
    }
    
    /// 生成逐帧尺寸与 keyTimes（供 CAKeyframeAnimation 驱动遮罩路径形变）。
    static func frames(from: CGSize, to: CGSize, bounceScale: Double = 1) -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let duration = settlingTime(from: from, to: to, bounceScale: bounceScale)
        // 采样率 = animation_fps（0 = 自动 → 120Hz，匹配 ProMotion）。
        let fps = Settings.shared.animationFps > 0 ? Double(Settings.shared.animationFps) : 120
        let count = max(1, Int((duration * fps).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? to : size(at: duration * $0, from: from, to: to, bounceScale: bounceScale) }
        return (sizes, keyTimes, duration)
    }
    
    /// 动画期间尺寸可能达到的最大包络（含超调），供窗口预留足够空间避免裁切。
    static func envelope(from: CGSize, to: CGSize, bounceScale: Double = 1) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            let swing = end > start ? spring(from: start, to: end, width: width, bounceScale: bounceScale).overshoot : 0
            guard swing > 0 else { return max(start, end) }
            return (end + (end - start) * CGFloat(swing)).rounded(.up)
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
}
