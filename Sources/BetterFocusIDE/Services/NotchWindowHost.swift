// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import QuartzCore

// MARK: - NotchPanel

/// 灵动岛的窗口壳（无边框、透明的 NSPanel）。
///
/// 关键不变量：`level = statusBar + 1` 让它浮在菜单栏之上；`collectionBehavior`
/// 使其跨所有空间、全屏辅助层常驻且固定不随窗口循环切换。`canBecomeKey` 仅在
/// 有卡片需要接收键盘输入时返回 true。
final class NotchPanel: NSPanel {
    /// 覆盖式 collectionBehavior：所有空间可见 + 全屏辅助 + 固定 + 不参与窗口循环。
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    /// 窗口层级：菜单栏之上 1 级。
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// 是否允许成为 key 窗口（有交互卡片时才置 true）。
    var acceptsKeyFocus = false

    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

// MARK: - NotchHostingView

/// 承载 SwiftUI 内容的 NSHostingView 子类。
///
/// 自定义 `hitTest`：落在自身边界外的点返回 nil，让透明区域的点击穿透到下方窗口。
final class NotchHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 让点击穿过透明区域
        guard let superview = self.superview else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - NotchCanvas

/// 窗口的内容视图。一层被裁成灵动岛轮廓的黑色底、一层在卡片展开时淡入的磨砂玻璃
/// `NSVisualEffectView`、以及叠在最上的 SwiftUI 内容——全部裁切到随帧形变的轮廓内。
///
/// 缩放期间窗口保持在*包络*尺寸（弹簧摆到的最宽处 + 阴影留白），而遮罩路径逐帧形变，
/// 于是两侧摆开时刘海的圆角与肩部始终保真。岛四周的留白是透明的，窗口的投影正是在
/// 这里绘制。
final class NotchCanvas: NSView {
    let host: NotchHostingView
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let glass = NSVisualEffectView()
    /// 覆在磨砂玻璃上的一层暗色洗色。`.hudWindow` 会模糊窗口后面的内容，而屏幕顶部
    /// 往往是（偏亮的）菜单栏，会把整张卡片冲成浅灰。这层恒定暗化把磨砂拉回深邃、
    /// 含蓄的暗色。收起时玻璃透明，暗层直接落在黑色底上、保持纯黑。
    private let dim = NSView()
    /// 岛正在趋向 / 静止于的尺寸（内容尺寸）。
    private var contentSize: CGSize
    private var trackingArea: NSTrackingArea?

    // MARK: - 鼠标回调（由 NotchWindowHost → NotchService 接线）
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    var onMouseMove: ((NSPoint) -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(content: AnyView, size: CGSize) {
        contentSize = size
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.masksToBounds = true  // 裁剪溢出 host bounds 的 SwiftUI 内容
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        applyBaseColor()
        layer?.masksToBounds = true
        layer?.mask = silhouette

        // 内容之后的暗色磨砂材质。它模糊窗口后面的东西，故只在展开卡片时才显现；
        // 收起的细条保持纯黑以融入物理刘海。
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.alphaValue = 0
        addSubview(glass, positioned: .below, relativeTo: host)
        addSubview(host)

        // 暗色洗色层：在玻璃之上、内容之下（恒定 alpha）。
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        addSubview(dim, positioned: .below, relativeTo: host)

        edge.fillColor = nil
        edge.lineWidth = 0.75
        edge.zPosition = 2
        layer?.addSublayer(edge)

        setContentSize(size)
        updateContrast()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: 几何辅助

    /// `size` 对应的岛矩形：在当前画布宽度内水平居中、顶部对齐画布顶边。
    func islandRect(for size: CGSize) -> CGRect {
        return CGRect(x: (bounds.width - size.width) / 2, y: 0,
                      width: size.width, height: size.height)
    }

    /// `size` 在当前画布边界内的轮廓路径。
    func morphPath(for size: CGSize) -> CGPath {
        let shape = NotchShape(attached: true,
                               radius: NotchLayout.surfaceRadius(height: size.height),
                               floatingGap: nil)
        return shape.path(in: islandRect(for: size)).cgPath
    }

    /// 当前绘制出的岛尺寸（读取 presentation 路径，使被打断的动画从屏幕上的实际
    /// 形态续接，而非从目标值重新开始）。
    var visibleSize: CGSize? {
        guard let path = (silhouette.presentation()?.path ?? silhouette.path) else { return nil }
        let box = path.boundingBoxOfPath
        guard !box.isNull else { return nil }
        return CGSize(width: box.width, height: max(0, box.maxY))
    }

    // MARK: 静止布局

    func setContentSize(_ size: CGSize) {
        contentSize = size
        needsLayout = true
    }

    /// 静止布局：在一个禁用隐式动画的 CATransaction 里，把各层摆到 contentSize
    /// 对应的矩形并刷新遮罩路径、底色与对比度。
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = islandRect(for: contentSize)
        host.frame = rect
        glass.frame = rect
        dim.frame = rect
        let path = morphPath(for: contentSize)
        if silhouette.path != path { silhouette.path = path }
        edge.path = path
        applyBaseColor()
        updateContrast()
        CATransaction.commit()
    }

    /// 从 Settings 取岛底色（background_color × background_alpha），取代固定刘海黑，
    /// 使外观改动实时生效。每次 layout 都重读，而设置变更会触发重新 present。
    private func applyBaseColor() {
        let c = Settings.shared.backgroundRGB
        let alpha = CGFloat(min(1, max(0, Settings.shared.backgroundAlpha)))
        layer?.backgroundColor = NSColor(
            srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha
        ).cgColor
    }

    /// 磨砂只在展开卡片时出现；细条静止态关闭它，让岛读作实心刘海黑。发丝描边也只在
    /// 展开时出现（Python `_draw_hairline`）。
    private func updateContrast() {
        let expanded = contentSize.height > 60
        // 边缘高光：仅展开卡片有细微白描边。
        let targetWidth: CGFloat = expanded ? 0.75 : 0
        if edge.lineWidth != targetWidth {
            edge.lineWidth = targetWidth
            edge.strokeColor = expanded
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : nil
        }
        if glass.layer?.animation(forKey: "fade") == nil {
            glass.alphaValue = expanded ? 1 : 0
        }
    }

    /// 给定点是否落在当前遮罩轮廓内（自定义命中测试）。
    func containsVisiblePoint(_ point: NSPoint) -> Bool {
        guard let path = silhouette.path else { return false }
        return path.contains(point)
    }

    // MARK: - 鼠标追踪

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMove?(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onRightClick?(point)
    }

    // MARK: 形变

    /// 开始一次弹簧驱动的形变到 `size`。调用方已把窗口置于包络 frame，故 `bounds`
    /// 是带留白的包络。
    func startMorph(_ animation: CAKeyframeAnimation, to size: CGSize, expanding: Bool) {
        contentSize = size
        let final = morphPath(for: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = islandRect(for: size)
        glass.frame = host.frame
        dim.frame = host.frame
        silhouette.path = final
        edge.path = final
        silhouette.add(animation, forKey: "morph")
        if let edgeAnim = animation.copy() as? CAKeyframeAnimation {
            edgeAnim.delegate = nil
            edge.add(edgeAnim, forKey: "morph")
        }
        CATransaction.commit()

        // 内容与玻璃随生长形状揭幕（展开），或先于收缩形状离场（收起），使飞行途中
        // 没有任何东西被挤压。淡入淡出窗口对齐 Python：展开 p=0.15→0.65，收起 p=0.40→0.06。
        let totalDuration = animation.duration
        let fadeStart: CFTimeInterval
        let fadeDuration: CFTimeInterval
        if expanding {
            // 内容在动画 15%→65% 期间浮现。
            fadeStart = totalDuration * 0.15
            fadeDuration = totalDuration * 0.50
        } else {
            // 内容在动画 0%→40% 期间消失（立即开始）。
            fadeStart = 0
            fadeDuration = totalDuration * 0.40
        }
        fadeLayer(host.layer, from: expanding ? 0 : 1, to: expanding ? 1 : 0,
                  duration: fadeDuration, delay: fadeStart, easeIn: !expanding)
        fadeGlass(to: expanding ? 1 : 0, duration: fadeDuration, delay: fadeStart)
    }

    /// 对某层做 opacity 淡入淡出（可选 easeIn，带延迟）。
    private func fadeLayer(_ layer: CALayer?, from: Float, to: Float,
                           duration: CFTimeInterval, delay: CFTimeInterval = 0,
                           easeIn: Bool) {
        guard let layer else { return }
        layer.removeAnimation(forKey: "fade")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = duration
        fade.beginTime = CACurrentMediaTime() + delay
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: easeIn ? .easeIn : .easeOut)
        layer.opacity = to
        layer.add(fade, forKey: "fade")
    }

    /// 对磨砂玻璃层做 opacity 淡入淡出（从当前 presentation 值起）。
    private func fadeGlass(to: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        guard let layer = glass.layer else { return }
        layer.removeAnimation(forKey: "fade")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = Float(to)
        fade.duration = duration
        fade.beginTime = CACurrentMediaTime() + delay
        fade.fillMode = .backwards
        glass.alphaValue = to
        layer.opacity = Float(to)
        layer.add(fade, forKey: "fade")
    }

    /// 弹簧落定后提交形变：撤掉动画、按静止（== 内容）尺寸布局。调用时 `bounds`
    /// 已是带留白的目标。
    func settleMorph(to size: CGSize) {
        contentSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.removeAnimation(forKey: "morph")
        edge.removeAnimation(forKey: "morph")
        host.layer?.removeAnimation(forKey: "fade")
        host.layer?.opacity = 1
        glass.layer?.removeAnimation(forKey: "fade")
        let rect = islandRect(for: size)
        host.frame = rect
        glass.frame = rect
        dim.frame = rect
        let path = morphPath(for: size)
        silhouette.path = path
        edge.path = path
        updateContrast()
        CATransaction.commit()
    }
}

// MARK: - NotchWindowHost

/// 窗口宿主：持有 NotchPanel + NotchCanvas，负责把内容呈现到正确的窗口 frame，
/// 并驱动弹簧形变动画（作为 CAAnimationDelegate 在落定后收尾）。
final class NotchWindowHost: NSObject, CAAnimationDelegate {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private var currentGeometry: NotchGeometry
    private var appliedFrame = CGRect.zero
    /// 动画代号：每次新动画自增，落定回调里比对以丢弃被抢占的旧动画。
    private var animationGeneration = 0
    private var isAnimating = false
    private var settleCompletion: (() -> Void)?
    private(set) var targetSize: CGSize
    /// 岛是否正在展示内容卡片（相对于收起胶囊）。
    private var showsContent = false

    /// 岛四周的透明留白，让窗口投影有空间在窗口边界内绘制。
    private let shadowPad: CGFloat = 26

    /// 把鼠标追踪回调接到画布上。
    func setMouseCallbacks(enter: @escaping () -> Void,
                           exit: @escaping () -> Void,
                           move: @escaping (NSPoint) -> Void,
                           rightClick: @escaping (NSPoint) -> Void) {
        canvas.onMouseEnter = enter
        canvas.onMouseExit = exit
        canvas.onMouseMove = move
        canvas.onRightClick = rightClick
    }

    init(content: AnyView, geometry: NotchGeometry, size: CGSize) {
        targetSize = size
        currentGeometry = geometry
        panel = NotchPanel(contentRect: geometry.frame(for: size, showsContent: false),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        canvas = NotchCanvas(content: content, size: size)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.contentView = canvas
        panel.setFrame(pixelAligned(panelFrame(for: size, showsContent: false)), display: false)
        canvas.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
    }

    /// 容纳顶部居中岛的带留白窗口 frame：四周各留 `shadowPad`，底部额外留 `shadowPad`
    /// 供投影消散。`showsContent` 为 false 时 frame 落在刘海底沿，使收起胶囊悬挂于
    /// 摄像头下方。
    private func panelFrame(for islandSize: CGSize, showsContent: Bool = true) -> CGRect {
        let base = currentGeometry.frame(for: islandSize, showsContent: showsContent)
        return CGRect(x: base.minX - shadowPad,
                      y: base.minY - shadowPad,
                      width: base.width + shadowPad * 2,
                      height: base.height + shadowPad)
    }

    /// 呈现岛到 `size`。
    ///
    /// 关键不变量：末尾必须调用 `orderFrontRegardless()`——仅 setFrame 不会让窗口显示。
    /// 尺寸变化且允许动画时走弹簧；否则禁用隐式动画直接落位。
    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, showsContent: Bool) {
        targetSize = size
        currentGeometry = geometry
        self.showsContent = showsContent

        let fromSize = canvas.visibleSize ?? size
        // reduce-motion 在 NotchMotion 内部解析（生长回弹强制为 0），对齐 Python
        // spring_for：形变照跑，只是不回弹。故只要动画到不同尺寸就允许弹簧，三态
        // （system/on/off）通过 bounce 体现，而非在此判断。
        let canSpring = animated && fromSize != size

        if canSpring {
            animateTo(size: size, geometry: geometry, from: fromSize)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(pixelAligned(panelFrame(for: size, showsContent: showsContent)), display: true)
            appliedFrame = panelFrame(for: size, showsContent: showsContent)
            canvas.setContentSize(size)
            canvas.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
        panel.orderFrontRegardless()
    }

    /// 隐藏岛：不动画直接 orderOut；动画则先收回到静止尺寸再 orderOut。
    func hide(animated: Bool) {
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let collapsedSize = currentGeometry.restingSize(showsContent: false)
        animateTo(size: collapsedSize, geometry: currentGeometry,
                  from: canvas.visibleSize ?? targetSize) {
            self.panel.orderOut(nil)
        }
    }

    /// 把窗口保持在包络（弹簧摆到的最宽/最高处，含阴影留白）以免超调被裁切，
    /// 再让遮罩路径穿过弹簧插值出的各尺寸形变。
    private func animateTo(size: CGSize, geometry: NotchGeometry, from fromSize: CGSize,
                           completion: (() -> Void)? = nil) {
        animationGeneration += 1
        let generation = animationGeneration
        isAnimating = true
        settleCompletion = completion

        let motion = NotchMotion.frames(from: fromSize, to: size)
        let envelope = NotchMotion.envelope(from: fromSize, to: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: envelope, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: envelope, showsContent: showsContent)
        canvas.setContentSize(envelope)
        canvas.layoutSubtreeIfNeeded()
        CATransaction.commit()

        // 路径在窗口已处于带留白包络后才计算，此时画布边界已正确居中岛。
        let paths = motion.sizes.map { canvas.morphPath(for: $0) }
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = motion.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = motion.duration
        animation.delegate = self
        animation.setValue(generation, forKey: "notchGeneration")
        let expanding = size.height >= fromSize.height
        canvas.startMorph(animation, to: size, expanding: expanding)
    }

    /// 动画落定回调：仅处理最新一代动画，把窗口从包络缩回静止带留白尺寸，
    /// 并对新边界提交落定后的轮廓。
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag,
              anim.value(forKey: "notchGeneration") as? Int == animationGeneration else { return }
        isAnimating = false
        let completion = settleCompletion
        settleCompletion = nil
        // 把窗口从包络缩回静止的带留白尺寸，再对新边界提交落定轮廓。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: targetSize, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: targetSize, showsContent: showsContent)
        canvas.layoutSubtreeIfNeeded()
        canvas.settleMorph(to: targetSize)
        CATransaction.commit()
        completion?()
    }

    /// 把 rect 对齐到物理像素（按 backingScaleFactor 取整），避免半像素模糊。
    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = panel.screen?.backingScaleFactor ?? 2
        return CGRect(
            x: (rect.origin.x * scale).rounded() / scale,
            y: (rect.origin.y * scale).rounded() / scale,
            width: (rect.size.width * scale).rounded() / scale,
            height: (rect.size.height * scale).rounded() / scale
        )
    }
}
