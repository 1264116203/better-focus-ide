// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import QuartzCore
import CoreImage

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

/// 鼠标穿透的容器视图：自身不吞噬事件（不在子视图上命中时返回 nil），
/// 让事件继续落到下层 NotchCanvas 处理，同时其子视图（SwiftUI 内容）照常接收点击。
///
/// 关键：必须 `isFlipped = true`，与 NotchCanvas 的翻转坐标系保持一致，否则挂在它
/// 下面的轮廓遮罩（silhouette）会被垂直翻转，气泡跑到下方、方向与辉光相反。
private final class PassthroughView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// 窗口的内容视图。一层被裁成灵动岛轮廓的岛底、一层在卡片展开时出现的玻璃
/// （macOS 26+ 为 `NSGlassEffectView`，更早系统为 `NSVisualEffectView`）、
/// 以及叠在最上的 SwiftUI 内容——全部裁切到随帧形变的轮廓内。
///
/// 缩放期间窗口保持在*包络*尺寸（弹簧摆到的最宽处 + 阴影留白）。玻璃框、圆角、
/// 洗色和轮廓遮罩吃同一组弹簧采样：透镜的边就是每一帧看见的边。不能先把玻璃铺到
/// 最终卡片尺寸、再用一块小遮罩去揭——洗色在玻璃外缘是透明的，揭开会先露出一圈
/// 发白的清玻璃，落定帧再一次性补上暗洗色和畸变遮罩，看起来就是白闪一下然后卡住。
final class NotchCanvas: NSView {
    let host: NotchHostingView
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    /// 展开卡片时的玻璃层。
    ///
    /// macOS 26+ 是系统液态玻璃（`NSGlassEffectView`）；更早系统仍是 `.hudWindow`
    /// 磨砂。只在展开卡片时显现，收起的细条保持纯色融入物理刘海。
    /// 圆角由 `lensRadius` 按当前玻璃框实时计算：直线边几乎不折光，畸变要把
    /// 左右收到胶囊才看得见。遮罩跟着这只圆角走，避免把侧棱切掉。
    private let glass: NSView
    /// 覆在旧式磨砂上的一层暗色洗色。`.hudWindow` 会模糊窗口后面的内容，而屏幕顶部
    /// 往往是（偏亮的）菜单栏，会把整张卡片冲成浅灰。液态玻璃自己有对比度，这层关掉，
    /// 否则会把折射盖成一块灰膜。
    private let dim = NSView()
    /// 承载被轮廓遮罩裁剪的岛面内容（黑底 / 磨砂 / 暗层 / SwiftUI / 发丝描边）。
    ///
    /// 关键：遮罩（silhouette）只作用在这一层，而非 canvas 根层，于是独立加在根层上的
    /// 辉光层（glowLayer）不会被裁成轮廓，得以向气泡外缘扩散。
    private let body = PassthroughView()
    /// 气泡外缘呼吸辉光：单层 CALayer，contents 是「轮廓填充 + 高斯模糊」的预渲染位图。
    ///
    /// 为什么预渲染而不是交给图层：CALayer.filters 的 CIGaussianBlur 对 CAShapeLayer
    /// 的矢量内容不生效（实测整层不可见）；CALayer.shadow 在透明窗口下只出一圈硬边。
    /// 用 CGContext 画实心轮廓、在 Core Image 里模糊、把结果作为单层 contents，
    /// 效果确定可控，且只有一层、天然连续渐变（无描边叠加的台阶）。
    /// 该层插在 body 之下，内部被不透明的岛面盖住，只露出向外扩散的光晕——
    /// 因此**不需要**额外遮罩挖洞（遮罩还会引入坐标系翻转的坑）。
    private let glowLayer = CALayer()
    /// 复用 Core Image 上下文，避免每次渲染重建。
    private static let ciContext = CIContext(options: nil)
    /// 辉光期望颜色（nil = 关闭）。由 NotchService 经 setGlow 注入。
    private var glowColor: NSColor?
    /// 辉光是否呼吸（reduce motion 关闭时为静态）。
    private var glowBreathing = false
    /// 当前已装入图层的呼吸参数（幅度, 周期）。设置改动后与它比对，不一致才重装动画。
    private var appliedBreath: (amplitude: Double, period: Double)?
    /// 岛正在趋向 / 静止于的尺寸（内容尺寸，不含外缘扩展）。
    private var contentSize: CGSize
    /// 弹簧形变进行中。这段时间 `layout` 不再改玻璃框和遮罩，
    /// 否则包络尺寸会先闪成整张卡片，动画再从胶囊长回去。
    private var morphing = false
    /// 形变中屏幕上的内容尺寸（不含外缘、不含透镜留白）。打断动画时从这里续，
    /// 而不是从遮罩的包围盒——包围盒含 pad，会把下一次弹簧的起点撑大。
    private var liveSample: CGSize?
    /// 0 = 收起气泡，1 = 展开卡片。形变按它插值外缘、洗色和畸变，落定后与静止态对齐。
    private var displayedOpenness: CGFloat = 0
    /// 本次弹簧起点的张开程度。中途被新动画打断时接着这个值，避免跳回 0 或 1。
    private var morphFromOpen: CGFloat = 0
    private var morphToOpen: CGFloat = 0
    /// 投影跟随的轮廓。畸变开启时比遮罩更贴玻璃框，避免把透镜留白也投进去。
    private var shadowOutline: CGPath?
    /// 畸变开启时遮罩比玻璃框再松出的宽度，盖住侧棱折光，又不切到玻璃自己的边上。
    private static let distortLensPad: CGFloat = 14
    private var trackingArea: NSTrackingArea?
    /// 羽化洗色的位图缓存。形变期间 `layout` 每帧都会进来，尺寸和圆角没变就直接复用。
    private var featherWashCache: (key: FeatherWashKey, image: CGImage)?

    /// 洗色位图的缓存键：像素尺寸 + 圆角（像素）。羽化宽度是常量，不必写入。
    private struct FeatherWashKey: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var radiusPx: Int
        var peak: Int
        var falloffPx: Int
    }
    /// 洗色视图的标识，避免以后 contentView 里多了别的子视图时铺错层。
    private static let washIdentifier = NSUserInterfaceItemIdentifier("betterfocus.feather-wash")

    // MARK: - 鼠标回调（由 NotchWindowHost → NotchService 接线）
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    var onMouseMove: ((NSPoint) -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 当前系统能否用原生液态玻璃。卡片控件侧的判断在 `LiquidGlassPlate`。
    private var usesLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// 构建展开卡片的玻璃层。macOS 26+ 用系统液态玻璃，否则退回 `.hudWindow` 磨砂。
    private static func makeGlass() -> NSView {
        if #available(macOS 26, *) {
            let liquid = NSGlassEffectView()
            // clear 才能看见背后画面在棱边上的扭曲。regular 在这块透明高窗里
            // 会退成一块不透的深灰，边缘没有可折的光。
            liquid.style = .clear
            liquid.cornerRadius = 28
            liquid.appearance = NSAppearance(named: .darkAqua)
            // 没有 contentView 时系统不画完整的透镜棱边。
            // 洗色铺满整块玻璃：中心约 0.5 黑，沿同一圆角向外缘羽化到全透明。
            // 不再内缩一块实心圆角矩形，否则会在折射棱边上切出一道缝。
            let filler = NSView()
            filler.autoresizingMask = [.width, .height]
            let wash = NSView()
            wash.identifier = Self.washIdentifier
            wash.wantsLayer = true
            // 位图由我们写入 layer.contents。视图自己重绘会把这张图清掉。
            wash.layerContentsRedrawPolicy = .never
            wash.autoresizingMask = [.width, .height]
            filler.addSubview(wash)
            liquid.contentView = filler
            if #available(macOS 27, *) {
                liquid.effectIsInteractive = true
            }
            return liquid
        }
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        return glass
    }

    init(content: AnyView, size: CGSize) {
        contentSize = size
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.masksToBounds = true  // 裁剪溢出 host bounds 的 SwiftUI 内容
        host.autoresizingMask = []
        // 磨砂玻璃层须在 super.init 前完成初始化（let 属性）。
        glass = NotchCanvas.makeGlass()
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        // 根层保持透明且不被轮廓裁剪：遮罩改由 body 承担，使辉光层能越出轮廓。
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        // body：承载全部被轮廓裁剪的岛面内容。遮罩只作用于此层。
        body.wantsLayer = true
        body.frame = bounds
        body.layer?.masksToBounds = true
        body.layer?.mask = silhouette
        addSubview(body)

        // 磨砂玻璃淡入：仅展开卡片时可见（由 updateContrast 按 contentSize 控制 alpha）。
        glass.alphaValue = 0
        body.addSubview(glass, positioned: .below, relativeTo: host)
        body.addSubview(host)

        // 暗色洗色层：在玻璃之上、内容之下。液态玻璃自己提供对比度，洗色会把折射盖住。
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(usesLiquidGlass ? 0 : 0.55).cgColor
        body.addSubview(dim, positioned: .below, relativeTo: host)

        edge.fillColor = nil
        edge.lineWidth = 0.75
        edge.zPosition = 2
        body.layer?.addSublayer(edge)

        // 辉光层：单个位图层（轮廓填充 + 高斯模糊），插到 body 之下，内部被不透明
        // 的岛面盖住，只露出向外扩散的渐变光晕。
        glowLayer.masksToBounds = false
        glowLayer.opacity = 0
        glowLayer.contentsGravity = .resize
        layer?.insertSublayer(glowLayer, at: 0)

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

    /// 屏幕上的内容尺寸。形变中取弹簧采样（不含外缘和透镜留白），静止时取 contentSize。
    /// 被打断的动画从这里续接，而不是从目标值重新开始。
    var visibleSize: CGSize? {
        liveSample ?? contentSize
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
        body.frame = bounds
        // 形变期间玻璃框、圆角、洗色和遮罩由垂直同步时钟驱动。这里若按 contentSize
        // （包络或目标）重铺，会把正在长大的透镜一帧打回整张卡片。
        if morphing {
            CATransaction.commit()
            return
        }
        updateContrast()
        glowLayer.contentsScale = window?.backingScaleFactor ?? 2
        setGlowPaths(morphPath(for: contentSize))
        CATransaction.commit()
    }

    /// 从 Settings 取岛底色（background_color × background_alpha），取代固定刘海黑，
    /// 使外观改动实时生效。底色设在 body 层上（受轮廓遮罩裁剪），根层保持透明。
    ///
    /// 液态玻璃只要看得见，岛底就必须是透明的，否则透镜只模糊这块纯色。
    /// 收起的细条（玻璃已藏起）保持用户设置的实色，用来融入物理刘海。
    private func applyBaseColor(glassVisible: Bool) {
        if usesLiquidGlass && glassVisible {
            body.layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        let c = Settings.shared.backgroundRGB
        let alpha = CGFloat(min(1, max(0, Settings.shared.backgroundAlpha)))
        body.layer?.backgroundColor = NSColor(
            srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha
        ).cgColor
    }

    /// 静止态对比度：展开卡片玻璃全开，收起细条回到实心刘海。
    /// 形变不走这里——`layout` 在 `morphing` 时直接返回，避免把包络重铺成整张卡片。
    private func updateContrast() {
        let open: CGFloat = contentSize.height > 60 ? 1 : 0
        displayedOpenness = open
        applySurface(content: contentSize, openness: open, hostOpacity: 1,
                     moving: false, placeHost: true)
        applyGlow()
    }

    /// 玻璃圆角随畸变幅度收到胶囊。直线边几乎不折光，左右要弯起来才看得见。
    private func lensRadius(in size: CGSize) -> CGFloat {
        let base = CGFloat(max(0, Settings.shared.glassCorner))
        let cap = max(0, min(size.width, size.height) / 2)
        let amount = CGFloat(min(1, max(0, Settings.shared.glassDistort)))
        return min(cap, base + (cap - base) * amount)
    }

    /// 透镜曲率、样式、染色和中心洗色都读设置，拖动滑块后下一次 layout 就生效。
    /// `moving` 为真时洗色用半分辨率、按约 24pt 量化，避免弹簧每帧重跑整张位图。
    private func updateLiquidCorner(moving: Bool) {
        guard #available(macOS 26, *), let liquid = glass as? NSGlassEffectView else { return }
        let radius = lensRadius(in: liquid.bounds.size)
        if liquid.cornerRadius != radius {
            liquid.cornerRadius = radius
        }
        let style: NSGlassEffectView.Style = Settings.shared.glassStyle == "regular" ? .regular : .clear
        if liquid.style != style {
            liquid.style = style
        }
        let amount = Settings.shared.glassTintAmount
        if amount > 0.01 {
            let c = Settings.parseRGB(Settings.shared.glassTint, fallback: (1, 1, 1))
            liquid.tintColor = NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g),
                                       blue: CGFloat(c.b), alpha: CGFloat(min(1, amount)))
        } else if liquid.tintColor != nil {
            liquid.tintColor = nil
        }
        if #available(macOS 27, *) {
            liquid.effectIsInteractive = Settings.shared.glassInteractive
        }
        let b = liquid.bounds
        liquid.contentView?.frame = b
        guard let wash = liquid.contentView?.subviews.first(where: {
            $0.identifier == Self.washIdentifier
        }) else { return }
        // 铺满玻璃边界。羽化做在位图 alpha 里，不再内缩出第二块矩形。
        wash.frame = CGRect(origin: .zero, size: b.size)
        applyFeatheredWash(to: wash, radius: radius, moving: moving)
    }

    /// 把羽化洗色写进洗色视图的 `layer.contents`。
    ///
    /// 运动中不按视网膜全分辨率重绘：尺寸量化到约 24pt、缩放降到一半，
    /// 位图靠 `contentsGravity = .resize` 铺满当前玻璃框。尺寸和圆角没跨过
    /// 量化档就直接复用缓存。落定帧 `moving = false`，补一张全清晰的。
    private func applyFeatheredWash(to wash: NSView, radius: CGFloat, moving: Bool) {
        guard let layer = wash.layer else { return }
        let backing = max(1, window?.backingScaleFactor ?? 2)
        let scale = moving ? max(1, backing * 0.5) : backing
        let quantum: CGFloat = moving ? max(8, scale * 24) : 1
        let rawWidth = wash.bounds.width * scale
        let rawHeight = wash.bounds.height * scale
        var pixelWidth = Int((rawWidth / quantum).rounded() * quantum)
        var pixelHeight = Int((rawHeight / quantum).rounded() * quantum)
        if pixelWidth < 2 { pixelWidth = max(2, Int(rawWidth.rounded())) }
        if pixelHeight < 2 { pixelHeight = max(2, Int(rawHeight.rounded())) }
        guard wash.bounds.width > 1, wash.bounds.height > 1 else {
            layer.contents = nil
            featherWashCache = nil
            return
        }
        // 位图比视图粗，圆角和羽化按同一比例缩进像素，拉伸回去后曲率不变。
        let radiusPx = Int((min(radius, min(wash.bounds.width, wash.bounds.height) / 2)
                            * CGFloat(pixelWidth) / wash.bounds.width).rounded())
        let peak = Int((min(1, max(0, Settings.shared.glassWash)) * 100).rounded())
        // 羽化按量化后的高度取值，同一档尺寸不会因为张开程度的小数变化而重绘。
        // 小玻璃把羽化收进短边的 35%，中心才到得了设定黑度；长到超过用户羽化后
        // 就和落定帧用的宽度相同。落定帧始终用用户设定的全宽。
        let fullFalloff = CGFloat(max(1, Settings.shared.glassWashFalloff))
        let pointHeight = CGFloat(pixelHeight) / scale
        let falloffPoints = moving ? min(fullFalloff, max(8, pointHeight * 0.35)) : fullFalloff
        let falloffPx = max(1, Int((falloffPoints * scale).rounded()))
        let key = FeatherWashKey(pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                 radiusPx: radiusPx, peak: peak, falloffPx: falloffPx)
        if featherWashCache?.key != key {
            guard let image = Self.renderFeatheredWash(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                radiusPx: CGFloat(radiusPx),
                falloffPx: CGFloat(falloffPx),
                peakAlpha: CGFloat(peak) / 100
            ) else { return }
            featherWashCache = (key, image)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = nil
        layer.cornerRadius = 0
        layer.masksToBounds = false
        layer.isOpaque = false
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        layer.contents = featherWashCache?.image
        CATransaction.commit()
    }

    /// 圆角矩形的距离场：中心黑度 `washPeakAlpha`，沿外缘 `falloffPx` 内 smoothstep 到 0。
    ///
    /// 等值线是玻璃同一圆角的偏移曲线，外缘 alpha 为 0，所以不会出现内缩矩形的硬边。
    /// 黑是预乘的（RGB = 0），避免半透明边缘被抬成灰雾。
    private static func renderFeatheredWash(pixelWidth: Int, pixelHeight: Int,
                                            radiusPx: CGFloat, falloffPx: CGFloat,
                                            peakAlpha: CGFloat) -> CGImage? {
        guard pixelWidth > 1, pixelHeight > 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let raw = ctx.data else { return nil }

        let rowBytes = ctx.bytesPerRow
        let pixels = raw.bindMemory(to: UInt8.self, capacity: rowBytes * pixelHeight)
        let hw = Float(pixelWidth) * 0.5
        let hh = Float(pixelHeight) * 0.5
        let rad = Float(max(0, radiusPx))
        let falloff = Float(max(1, falloffPx))
        let peak = Float(min(1, max(0, peakAlpha))) * 255

        for y in 0..<pixelHeight {
            let qy = abs((Float(y) + 0.5) - hh) - hh + rad
            let row = pixels.advanced(by: y * rowBytes)
            for x in 0..<pixelWidth {
                let qx = abs((Float(x) + 0.5) - hw) - hw + rad
                let ox = max(qx, 0)
                let oy = max(qy, 0)
                let outside = sqrt(ox * ox + oy * oy)
                let inside = min(max(qx, qy), 0)
                let dist = rad - (outside + inside)
                var byte: UInt8 = 0
                if dist > 0 {
                    let t = min(1, dist / falloff)
                    let s = t * t * (3 - 2 * t)
                    byte = UInt8(min(255, max(0, Int((peak * s).rounded()))))
                }
                let i = x * 4
                row[i] = 0
                row[i + 1] = 0
                row[i + 2] = 0
                row[i + 3] = byte
            }
        }
        return ctx.makeImage()
    }

    /// 外缘扩展只加在左右和下方，顶边仍贴住屏幕。
    private func rimAmount(expanded: Bool) -> CGFloat {
        guard usesLiquidGlass, expanded else { return 0 }
        return CGFloat(max(0, Settings.shared.glassRim))
    }

    /// 玻璃框在岛矩形之外再撑开 `rim`。内容框不动，文字位置不跟着漂。
    private func expandedGlassRect(_ island: CGRect, rim: CGFloat) -> CGRect {
        guard rim > 0 else { return island }
        return CGRect(x: island.minX - rim, y: island.minY,
                      width: island.width + rim * 2, height: island.height + rim)
    }

    /// 把玻璃、遮罩、洗色和投影摆到「张开程度 `openness`」对应的样子。
    ///
    /// `openness` 0 是收起气泡（无外缘、无透镜留白、玻璃藏起），1 是展开卡片
    /// （外缘、畸变圆角和 14pt 留白都到位）。形变的每一帧和落定帧都走这里，
    /// 所以最后一帧和 `settleMorph` 是同一套数，不会再跳一下。
    ///
    /// `placeHost == false` 时内容框保持目标尺寸，SwiftUI 不跟着弹簧重排，
    /// 只被遮罩裁切，再用 `hostOpacity` 跟着张开淡入。
    private func applySurface(content: CGSize, openness: CGFloat, hostOpacity: CGFloat,
                              moving: Bool, placeHost: Bool) {
        let open = min(1, max(0, openness))
        let expanded = open > 0.999
        let distortOn = usesLiquidGlass && Settings.shared.glassDistort > 0.001
        // 轮廓从刘海肩部收到透镜的过程比整段弹簧短：刚离开气泡就成为透镜，
        // 之后全程都是「当前尺寸」的玻璃在长大，而不是收起轮廓一路撑到落定再换形。
        let lensBlend: CGFloat = distortOn ? min(1, open / 0.18) : 0
        // 外缘和透镜留白跟着张开程度从 0 长到落定值。收起气泡上两者都是 0，
        // 不会留下一圈固定外缘把气泡撑大。
        let rim = rimAmount(expanded: true) * open
        let pad = distortOn ? Self.distortLensPad * open : 0
        let island = islandRect(for: content)
        let glassRect = expandedGlassRect(island, rim: rim)

        if placeHost {
            host.frame = island
        }
        dim.frame = glassRect
        glass.frame = glassRect

        let alpha = glassOpacity(openness: open)
        glass.layer?.removeAnimation(forKey: "fade")
        glass.alphaValue = alpha
        glass.layer?.opacity = Float(alpha)
        // 玻璃还藏着时不重绘洗色。看得见的那一帧再铺，和透明度同一次提交。
        updateLiquidCorner(moving: moving && alpha > 0.02)

        if body.layer?.mask !== silhouette {
            body.layer?.mask = silhouette
        }
        let path = maskPath(glassRect: glassRect, lensBlend: lensBlend, pad: pad)
        silhouette.path = path
        edge.path = path
        if lensBlend > 0.999 {
            let tightR = min(lensRadius(in: glassRect.size), min(glassRect.width, glassRect.height) / 2)
            shadowOutline = CGPath(roundedRect: glassRect, cornerWidth: tightR,
                                   cornerHeight: tightR, transform: nil)
            host.layer?.masksToBounds = false
        } else {
            shadowOutline = path
            host.layer?.masksToBounds = true
        }

        // 边缘高光：旧式磨砂才需要自绘发丝描边。液态玻璃自带折射棱边，再描一条会成双轮廓。
        let showEdge = expanded && !usesLiquidGlass
        let targetWidth: CGFloat = showEdge ? 0.75 : 0
        if edge.lineWidth != targetWidth {
            edge.lineWidth = targetWidth
            edge.strokeColor = showEdge
                ? NSColor.white.withAlphaComponent(0.06).cgColor
                : nil
        }

        host.layer?.removeAnimation(forKey: "fade")
        host.layer?.opacity = Float(hostOpacity)
        // 玻璃还没盖住时岛底保持实色。清得太早，半透明透镜会把菜单栏当成一块白闪。
        applyBaseColor(glassVisible: alpha > 0.72)
        let shadowStrength: CGFloat = morphing ? open : (content.height > 60 ? 1 : 0)
        updateBodyShadow(strength: shadowStrength)
    }

    /// 液态玻璃在离开气泡后很快就完全显现，之后是同一块材料在长大。
    /// 两端钉死：0 与收起气泡重合，1 与展开卡片重合。
    private func glassOpacity(openness: CGFloat) -> CGFloat {
        let span = min(1, max(0, openness))
        if !usesLiquidGlass { return span }
        if span <= 0 { return 0 }
        if span >= 1 { return 1 }
        let t = min(1, span / 0.10)
        return t * t * (3 - 2 * t)
    }

    /// 内容不透明度。展开时先送走气泡上的圆点，再把卡片文字淡进来；
    /// 收起是反向，并且在回到刘海前把不透明度送回 1，落定不必再从 0 弹回去。
    private func contentOpacity(openness: CGFloat, opening: Bool) -> CGFloat {
        let span = min(1, max(0, openness))
        if opening {
            if span < 0.10 {
                let t = span / 0.10
                let s = t * t * (3 - 2 * t)
                return 1 - s
            }
            let t = min(1, max(0, (span - 0.16) / 0.44))
            return t * t * (3 - 2 * t)
        }
        if span >= 0.42 {
            let t = min(1, max(0, (span - 0.42) / 0.38))
            return t * t * (3 - 2 * t)
        }
        let t = min(1, max(0, (0.28 - span) / 0.28))
        return t * t * (3 - 2 * t)
    }

    /// 遮罩。`lensBlend == 0` 是刘海轮廓；`== 1` 是玻璃圆角矩形再向外松 `pad`，
    /// 和落定态 `applySurface` 用的是同一条路径。中间帧用同一族三次曲线，
    /// 肩部收到 0、圆角收到透镜半径，避免两套路径在切换时跳。
    private func maskPath(glassRect: CGRect, lensBlend: CGFloat, pad: CGFloat) -> CGPath {
        let u = min(1, max(0, lensBlend))
        if u <= 0.0001 {
            return notchPath(in: glassRect)
        }
        if u >= 0.999 {
            return lensMaskPath(glassRect: glassRect, pad: pad)
        }
        return blendedContour(glassRect: glassRect, blend: u, pad: pad)
    }

    private func notchPath(in rect: CGRect) -> CGPath {
        NotchShape(attached: true,
                   radius: NotchLayout.surfaceRadius(height: rect.height),
                   floatingGap: nil).path(in: rect).cgPath
    }

    /// 畸变落定形态：玻璃框向左右和下方松出 `pad`，圆角比玻璃自己的再大 `pad`，
    /// 侧棱折光留在遮罩内，又不会切到玻璃边上。顶边不外扩，仍贴住屏幕。
    private func lensMaskPath(glassRect: CGRect, pad: CGFloat) -> CGPath {
        var loose = glassRect
        loose.origin.x -= pad
        loose.size.width += pad * 2
        loose.size.height += pad
        let glassR = lensRadius(in: glassRect.size)
        let looseR = min(glassR + pad, min(loose.width, loose.height) / 2)
        return CGPath(roundedRect: loose, cornerWidth: looseR, cornerHeight: looseR, transform: nil)
    }

    /// 刘海轮廓收到透镜圆角矩形的中间态。`blend` 为 0 时几何上回到 NotchShape，
    /// 为 1 时肩部为 0、上下半径等于玻璃圆角加 `pad`。
    private func blendedContour(glassRect: CGRect, blend: CGFloat, pad: CGFloat) -> CGPath {
        let u = min(1, max(0, blend))
        var loose = glassRect
        loose.origin.x -= pad
        loose.size.width += pad * 2
        loose.size.height += pad
        let glassR = lensRadius(in: glassRect.size)
        let notchBottom = NotchLayout.surfaceRadius(height: glassRect.height)
        let notchSide = NotchLayout.shoulder(height: glassRect.height)
        let topR = (glassR + pad) * u
        let botR = notchBottom * (1 - u) + (glassR + pad) * u
        let side = notchSide * (1 - u)
        return contourPath(in: loose, topRadius: topR, bottomRadius: botR, shoulder: side)
    }

    /// 顶边贴屏的轮廓。`shoulder == 0` 且上下半径相等时是圆角矩形；
    /// `topRadius == 0` 时控制点与 NotchShape 的肩部、底角一致。
    private func contourPath(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat,
                             shoulder: CGFloat) -> CGPath {
        let width = max(0, rect.width)
        let height = max(0, rect.height)
        guard width > 1, height > 1 else {
            return CGPath(rect: rect, transform: nil)
        }
        let tangent: CGFloat = 0.55228475
        var side = min(max(0, shoulder), width / 2)
        var topR = max(0, topRadius)
        var botR = max(0, bottomRadius)
        topR = min(topR, max(0, width / 2 - side), height / 2)
        botR = min(botR, max(0, width / 2 - side), height / 2)
        if side + topR + botR > height, side + topR + botR > 0 {
            let scale = height / (side + topR + botR)
            side *= scale
            topR *= scale
            botR *= scale
        }

        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let path = CGMutablePath()

        path.move(to: CGPoint(x: left + topR, y: top))
        path.addLine(to: CGPoint(x: right - topR, y: top))

        let trFrom = CGPoint(x: right - topR, y: top)
        let trTo = CGPoint(x: right - side, y: top + side + topR)
        addCorner(path, from: trFrom, to: trTo, tangent: tangent, verticalFirst: false)

        path.addLine(to: CGPoint(x: right - side, y: bottom - botR))

        let brFrom = CGPoint(x: right - side, y: bottom - botR)
        let brTo = CGPoint(x: right - side - botR, y: bottom)
        addCorner(path, from: brFrom, to: brTo, tangent: tangent, verticalFirst: true)

        path.addLine(to: CGPoint(x: left + side + botR, y: bottom))

        let blFrom = CGPoint(x: left + side + botR, y: bottom)
        let blTo = CGPoint(x: left + side, y: bottom - botR)
        addCorner(path, from: blFrom, to: blTo, tangent: tangent, verticalFirst: false)

        path.addLine(to: CGPoint(x: left + side, y: top + side + topR))

        let tlFrom = CGPoint(x: left + side, y: top + side + topR)
        let tlTo = CGPoint(x: left + topR, y: top)
        addCorner(path, from: tlFrom, to: tlTo, tangent: tangent, verticalFirst: true)

        path.closeSubpath()
        return path
    }

    /// 圆角的三次近似。`verticalFirst` 表示离开起点时沿垂直方向（底角、左上角），
    /// 否则沿水平方向（右上角）。到达时换到另一条轴。κ = 0.55228475。
    private func addCorner(_ path: CGMutablePath, from: CGPoint, to: CGPoint,
                           tangent: CGFloat, verticalFirst: Bool) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let c1: CGPoint
        let c2: CGPoint
        if verticalFirst {
            c1 = CGPoint(x: from.x, y: from.y + dy * tangent)
            c2 = CGPoint(x: to.x - dx * tangent, y: to.y)
        } else {
            c1 = CGPoint(x: from.x + dx * tangent, y: from.y)
            c2 = CGPoint(x: to.x, y: to.y - dy * tangent)
        }
        path.addCurve(to: to, control1: c1, control2: c2)
    }

    /// 弹簧采样在起点和终点之间的进度，按有位移的轴平均。超调钳在 0...1，
    /// 尺寸本身仍用没钳过的采样，所以回弹只撑大玻璃框，不把畸变推过落定值。
    private static func clampedProgress(_ sample: CGSize, from: CGSize, to: CGSize) -> CGFloat {
        var acc: CGFloat = 0
        var n: CGFloat = 0
        func take(_ value: CGFloat, _ start: CGFloat, _ end: CGFloat) {
            let delta = end - start
            guard abs(delta) >= 0.5 else { return }
            acc += (value - start) / delta
            n += 1
        }
        take(sample.width, from.width, to.width)
        take(sample.height, from.height, to.height)
        guard n > 0 else { return 1 }
        return min(1, max(0, acc / n))
    }

    /// 弹簧开始前调用，让接下来的 layout 不要提前揭掉轮廓遮罩。
    func setMorphing(_ active: Bool) {
        morphing = active
    }

    /// 岛自身的投影。
    ///
    /// 窗口级投影已在 init 里关掉（系统按**整窗 alpha** 生成，会把半透明辉光一起压暗，
    /// 并在衰减末端多出一条对比边）。改由 body 层投影：body 被 silhouette 裁成岛形，
    /// 投影只跟随岛轮廓。`strength` 为 0 时收起气泡不投影；展开后才乘上用户设置的浓度。
    private func updateBodyShadow(strength: CGFloat) {
        guard let layer = body.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let settings = Settings.shared
        let color = Settings.parseRGB(settings.cardShadowColor, fallback: (0, 0, 0))
        let amount = min(1, max(0, strength))
        layer.shadowColor = NSColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g),
                                     blue: CGFloat(color.b), alpha: 1).cgColor
        layer.shadowOpacity = Float(min(1, max(0, settings.cardShadowOpacity)) * amount)
        layer.shadowRadius = CGFloat(max(0, settings.cardShadowRadius))
        layer.shadowOffset = CGSize(width: settings.cardShadowOffsetX,
                                    height: settings.cardShadowOffsetY)
        // 液态玻璃展开时岛底是透明的，投影不再能从层内容里长出来，改跟轮廓路径走。
        if usesLiquidGlass {
            layer.shadowPath = amount > 0.001 ? (shadowOutline ?? silhouette.path) : nil
        }
        CATransaction.commit()
    }

    // MARK: 呼吸辉光

    /// 设置 / 清除气泡外缘辉光。`color` = nil 时关闭；`breathing` = true 时做呼吸动画，
    /// false 时静态显示（reduce motion）。
    func setGlow(color: NSColor?, breathing: Bool) {
        glowColor = color
        glowBreathing = breathing
        applyGlow()
    }

    /// 依据当前期望（颜色 + 呼吸）与展开状态，把辉光层落到正确外观。
    /// 展开态（大尺寸卡片）隐藏辉光，仅收起态气泡显示。
    ///
    /// 每次可见都会重渲染位图并重读呼吸灯的三项设置（范围 / 幅度 / 频率），
    /// 因此拖动任一滑块都立即生效（设置变更会触发重新 present → layout → applyGlow）。
    private func applyGlow() {
        // 形变期间先把辉光摘掉。收起目标若提前按「高度 ≤ 60」点亮，
        // 卡片还没缩回去辉光就已经铺在刘海上了。
        if morphing {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glowLayer.removeAnimation(forKey: "breathe")
            appliedBreath = nil
            glowLayer.opacity = 0
            CATransaction.commit()
            return
        }
        let visible = glowColor != nil && contentSize.height <= 60
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let color = glowColor, visible else {
            glowLayer.removeAnimation(forKey: "breathe")
            appliedBreath = nil
            glowLayer.opacity = 0
            CATransaction.commit()
            return
        }
        renderGlowImage(color: color)
        // 模型值也置为可见：动画只影响呈现层，若动画被移除（如 reduce motion 切换），
        // 模型值决定最终外观——留 0 会让辉光整体消失。
        glowLayer.opacity = 1
        CATransaction.commit()

        if glowBreathing {
            // CAAnimation 是值拷贝，改了设置不会自动生效；参数变了必须重装才能看到效果。
            let amplitude = min(1, max(0, Settings.shared.glowBreathAmplitude))
            let period = max(0.4, Settings.shared.glowBreathPeriod)
            if let applied = appliedBreath, applied.amplitude == amplitude,
               applied.period == period, glowLayer.animation(forKey: "breathe") != nil {
                return
            }
            let breathe = CAKeyframeAnimation(keyPath: "opacity")
            // 用余弦采样做关键帧，而不是 easeInEaseOut + autoreverses：
            // 后者在最亮 / 最暗两端各驻留约 1/4 周期（实测 ~0.3s 平台），看起来像
            // 「闪一下停一下」，中间过渡被压成少数几档。余弦曲线速度连续、两端只是
            // 感知均匀配速：人眼对「深浅」的响应是 CIE L*（非线性）。直接对 opacity
            // 做余弦时幅度越大越失真——100% 时大半周期停在「几乎看不见」的浅端、
            // 深色端一闪而过（实测 t=0.4 周期处 L*=92.6，等速应为 ~50），观感即卡顿。
            // 这里把余弦放在 L* 空间再反解 opacity，任何幅度下深浅都等速过渡。
            let core = 0.84   // 贴边位图覆盖率 Φ(inflate/σ)，与 renderGlowImage 参数一致
            func lStar(_ s: Double) -> Double {
                let y = s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
                return y <= 0.008856 ? y * 903.3 : 116 * pow(y, 1 / 3) - 16
            }
            func srgb(_ l: Double) -> Double {
                let y = l <= 8 ? l / 903.3 : pow((l + 16) / 116, 3)
                return y <= 0.0031308 ? y * 12.92 : 1.055 * pow(y, 1 / 2.4) - 0.055
            }
            let lDeep = lStar(1 - core)                    // opacity=1：最深
            let lPale = lStar(1 - core * (1 - amplitude))  // opacity=低谷：最浅
            // 240 档采样 + cubic 插值保证梯度足够细
            // （120Hz 屏上一个周期约 288 帧，关键帧密度与之同量级）。
            let steps = 240
            var values: [Float] = []
            values.reserveCapacity(steps + 1)
            for i in 0...steps {
                let phase = Double(i) / Double(steps) * 2 * .pi
                let wave = (1 - cos(phase)) / 2   // 0 → 1 → 0，首尾同值便于无缝循环
                let target = lDeep + (lPale - lDeep) * wave
                let opacity = (1 - srgb(target)) / core
                values.append(Float(min(1, max(1 - amplitude, opacity))))
            }
            breathe.values = values
            breathe.duration = period
            breathe.calculationMode = .cubic
            breathe.repeatCount = .infinity
            glowLayer.add(breathe, forKey: "breathe")
            appliedBreath = (amplitude, period)
        } else {
            glowLayer.removeAnimation(forKey: "breathe")
            appliedBreath = nil
        }
    }

    /// 把「实心轮廓 + 高斯模糊」渲染成一张位图，作为单层辉光的 contents。
    ///
    /// 整张图只有一条单调衰减的曲线：没有描边叠加形成的同心环，也没有饱和平台，
    /// 因此不存在「最外侧那条淡蓝色边线」。
    ///
    /// **浓度必须做在「源图形状」上，不能做在模糊后的像素上**：模糊后的位图是预乘
    /// alpha，对 RGB 做增益会把颜色推向白（实测整圈变成奶白色雾，主题色全丢）。
    /// 这里改用「先把轮廓向外膨胀 inflate，再模糊」：膨胀带在模糊后仍接近不透明，
    /// 于是紧贴气泡的一圈显示的是**真正的主题色**，再往外才是高斯衰减。
    private func renderGlowImage(color: NSColor) {
        let scale = max(1, glowLayer.contentsScale)
        let pixelWidth = Int((bounds.width * scale).rounded())
        let pixelHeight = Int((bounds.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }

        func makeContext() -> CGContext? {
            CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                      bitsPerComponent: 8, bytesPerRow: 0,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        // canvas 是 isFlipped（原点左上、y 向下），把同一套变换套到上下文上，
        // 位图里的轮廓位置才与屏幕上的气泡一致。
        func applyViewTransform(_ c: CGContext) {
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: 0, y: bounds.height)
            c.scaleBy(x: 1, y: -1)
        }

        let path = morphPath(for: contentSize)
        let range = CGFloat(max(1, Settings.shared.glowRadius))
        // 膨胀 0.5R、模糊 σ≈0.5R：贴边覆盖率 ≈ Φ(1.0) ≈ 0.84（仍是明显的实色），
        // 但衰减带更宽更缓（峰值梯度比 0.65/0.38 组合低约三成）。梯度越陡，呼吸时
        // 整条浓淡带上下平移越像「一档一档跳」；放缓后深浅过渡才连贯。
        // 总扩散 ≈ 0.5R + 2.5σ ≈ 1.75R，仍小于窗口留白 shadowPad。
        let inflate = range * 0.5
        let sigma = range * 0.5

        guard let source = makeContext() else { return }
        applyViewTransform(source)
        source.setFillColor(color.cgColor)
        source.addPath(path)
        source.fillPath()
        // 同一条路径再用 2×inflate 的粗描边画一遍 = 把形状向外膨胀 inflate
        //（描边内侧那一半被岛面盖住，看不见）。
        source.setStrokeColor(color.cgColor)
        source.setLineWidth(inflate * 2)
        source.setLineJoin(.round)
        source.addPath(path)
        source.strokePath()
        guard let base = source.makeImage() else { return }

        // 模糊在 Core Image 里完成（半径单位是像素，故乘屏幕缩放系数）：
        // 先 clampedToExtent 再裁回原尺寸，避免边缘被 clamp 出硬边。
        let input = CIImage(cgImage: base)
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur",
                            parameters: [kCIInputRadiusKey: sigma * scale])
            .cropped(to: input.extent)
        guard let tail = Self.ciContext.createCGImage(blurred, from: input.extent),
              let out = makeContext() else { return }
        let full = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        out.draw(tail, in: full)
        glowLayer.contents = out.makeImage()
    }

    /// 只同步辉光层的 frame：位图与图层同尺寸（contentsGravity = .resize），
    /// 轮廓形状已画进位图，无须再给图层设路径。
    private func setGlowPaths(_ path: CGPath) {
        glowLayer.frame = bounds
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

    /// 窗口已经停在包络上。记下张开程度的起点，把内容框放到目标尺寸（不再每帧重排），
    /// 辉光先关掉。玻璃框要等 `renderMorph` 按采样来放，不能在这里铺成最终卡片。
    func beginLiveMorph(from: CGSize, to: CGSize) {
        morphing = true
        morphFromOpen = displayedOpenness
        morphToOpen = to.height > 60 ? 1 : 0
        contentSize = to
        liveSample = from
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer?.removeAnimation(forKey: "fade")
        glass.layer?.removeAnimation(forKey: "fade")
        silhouette.removeAnimation(forKey: "morph")
        edge.removeAnimation(forKey: "morph")
        host.frame = islandRect(for: to)
        CATransaction.commit()
        applyGlow()
    }

    /// 用一帧弹簧采样同时改玻璃框、圆角、洗色和遮罩。`settled` 时钉在终点，
    /// 和随后的 `settleMorph` 同一套外观，只是窗口还停在包络里。
    func renderMorph(sample: CGSize, from: CGSize, to: CGSize, settled: Bool) {
        let progress = settled ? CGFloat(1) : Self.clampedProgress(sample, from: from, to: to)
        let open = morphFromOpen + (morphToOpen - morphFromOpen) * progress
        displayedOpenness = settled ? morphToOpen : open
        liveSample = settled ? nil : sample
        let crossing = abs(morphToOpen - morphFromOpen) > 0.05
        let opacity: CGFloat
        if settled || !crossing {
            opacity = 1
        } else {
            opacity = contentOpacity(openness: open, opening: morphToOpen > morphFromOpen)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applySurface(content: settled ? to : sample,
                     openness: settled ? morphToOpen : open,
                     hostOpacity: opacity,
                     moving: !settled,
                     placeHost: false)
        CATransaction.commit()
    }

    /// 弹簧落定后提交形变：撤掉动画、按静止（== 内容）尺寸布局。调用时 `bounds`
    /// 已是带留白的目标。
    func settleMorph(to size: CGSize) {
        morphing = false
        liveSample = nil
        contentSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.frame = bounds
        silhouette.removeAnimation(forKey: "morph")
        edge.removeAnimation(forKey: "morph")
        host.layer?.removeAnimation(forKey: "fade")
        glass.layer?.removeAnimation(forKey: "fade")
        updateContrast()
        glowLayer.contentsScale = window?.backingScaleFactor ?? 2
        setGlowPaths(morphPath(for: size))
        CATransaction.commit()
    }
}

// MARK: - NotchWindowHost

/// 窗口宿主：持有 NotchPanel + NotchCanvas，负责把内容呈现到正确的窗口 frame，
/// 并用与显示器垂直同步的 CADisplayLink 驱动弹簧形变。
final class NotchWindowHost: NSObject {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private var currentGeometry: NotchGeometry
    private var appliedFrame = CGRect.zero
    /// 动画代号：每次新动画自增，落定回调里比对以丢弃被抢占的旧动画。
    private var animationGeneration = 0
    private var isAnimating = false
    private var settleCompletion: (() -> Void)?
    /// 与屏幕刷新对齐的形变时钟。比 Timer 稳，也避免和遮罩关键帧各走各的。
    private var morphLink: CADisplayLink?
    private var morphFrom = CGSize.zero
    private var morphTo = CGSize.zero
    private var morphBounce = 1.0
    private var morphDuration: TimeInterval = 0
    private var morphStartedAt: CFTimeInterval = 0
    private var morphLastTick: CFTimeInterval = 0
    private(set) var targetSize: CGSize
    /// 岛是否正在展示内容卡片（相对于收起胶囊）。
    private var showsContent = false

    /// 岛四周的透明留白，让窗口投影和呼吸辉光有空间在窗口边界内绘制。
    ///
    /// 关键：必须随「呼吸灯范围」动态增长。窗口边界会硬裁辉光，若留白固定
    /// （旧值 26pt）小于辉光扩散半径，调大范围时辉光在窗口边缘被裁平，看起来
    /// 完全无效。高斯模糊的视觉扩散约 1.35 × range，这里取 1.5 × range + 14pt
    /// 余量，下限 26pt 保持原有窗口投影空间。
    private var shadowPad: CGFloat {
        max(26, CGFloat(Settings.shared.glowRadius) * 1.5 + 14)
    }

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

    /// 设置 / 清除气泡外缘呼吸辉光（转发到画布的 AppKit 辉光层）。
    ///
    /// `color` = nil 关闭；`breathing` = true 呼吸，false 静态（reduce motion）。
    func setGlow(color: NSColor?, breathing: Bool) {
        canvas.setGlow(color: color, breathing: breathing)
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
        // 关掉窗口阴影：无边框透明窗口的系统投影是按**整窗 alpha** 生成的，辉光本身就是
        // 半透明内容，于是辉光也会被投上一层阴影（压在旁边又暗又糊，还会在衰减末端多出
        // 一条对比边）。岛贴屏幕顶边，本来也看不到投影。
        panel.hasShadow = false
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
    /// 供辉光衰减。留白必须随 `glowRadius` 增长，否则窗口边界会把光晕硬裁出一条边。
    /// Frame 顶边始终对齐屏幕顶边，使气泡隐藏在刘海中。
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
    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, showsContent: Bool, gentle: Bool = false) {
        targetSize = size
        currentGeometry = geometry
        self.showsContent = showsContent

        let fromSize = canvas.visibleSize ?? size
        // reduce-motion 在 NotchMotion 内部解析（生长回弹强制为 0），对齐 Python
        // spring_for：形变照跑，只是不回弹。故只要动画到不同尺寸就允许弹簧，三态
        // （system/on/off）通过 bounce 体现，而非在此判断。
        let canSpring = animated && fromSize != size

        if canSpring {
            animateTo(size: size, geometry: geometry, from: fromSize, gentle: gentle)
        } else {
        stopMorphClock()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: size, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: size, showsContent: showsContent)
        canvas.setMorphing(false)
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
    /// 再用与垂直同步对齐的时钟，按同一组弹簧采样去改玻璃框、圆角、洗色和遮罩。
    private func animateTo(size: CGSize, geometry: NotchGeometry, from fromSize: CGSize,
                           completion: (() -> Void)? = nil, gentle: Bool = false) {
        animationGeneration += 1
        stopMorphClock()
        isAnimating = true
        settleCompletion = completion

        // 悬停重展开用更弱回弹，避免收起后气泡明显"放大再缩小"。
        let bounceScale = gentle ? NotchMotion.hoverBounceScale : 1
        let envelope = NotchMotion.envelope(from: fromSize, to: size, bounceScale: bounceScale)

        // 先挡住 layout，再改窗口。否则这一下会按包络把整张卡片闪出来。
        canvas.setMorphing(true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: envelope, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: envelope, showsContent: showsContent)
        CATransaction.commit()
        // 包络已经是当前 bounds。先让 body 跟上，再按这个宽度把玻璃居中，
        // 否则第一帧会按收起窗口的宽度算中心，下一帧再跳到包络中心。
        canvas.layoutSubtreeIfNeeded()

        canvas.beginLiveMorph(from: fromSize, to: size)
        // 第 0 帧就是当前气泡，和静止态重合，避免时钟响起来之前空一帧。
        canvas.renderMorph(sample: fromSize, from: fromSize, to: size, settled: false)
        panel.orderFrontRegardless()
        startMorphClock(from: fromSize, to: size, bounce: bounceScale)
    }

    /// 显示器刷新回调。弹簧时间取宿主时钟，不另起 Timer。
    @objc private func stepMorph(_ link: CADisplayLink) {
        let generation = animationGeneration
        guard link === morphLink else {
            link.invalidate()
            return
        }
        let stamp = link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime()
        let elapsed = max(0, stamp - morphStartedAt)
        let done = elapsed >= morphDuration - 0.0001
        if !done, Settings.shared.animationFps > 0 {
            let minInterval = 1.0 / Double(max(1, Settings.shared.animationFps))
            if stamp - morphLastTick < minInterval { return }
        }
        morphLastTick = stamp
        let sample = done
            ? morphTo
            : NotchMotion.size(at: elapsed, from: morphFrom, to: morphTo, bounceScale: morphBounce)
        canvas.renderMorph(sample: sample, from: morphFrom, to: morphTo, settled: done)
        if done {
            finishMorph(generation: generation)
        }
    }

    private func startMorphClock(from: CGSize, to: CGSize, bounce: Double) {
        stopMorphClock()
        morphFrom = from
        morphTo = to
        morphBounce = bounce
        morphDuration = NotchMotion.settlingTime(from: from, to: to, bounceScale: bounce)
        morphStartedAt = CACurrentMediaTime()
        morphLastTick = morphStartedAt
        guard morphDuration > 1.0 / 240 else {
            finishMorph(generation: animationGeneration)
            return
        }
        let link = panel.displayLink(target: self, selector: #selector(stepMorph(_:)))
        link.add(to: .main, forMode: .common)
        morphLink = link
    }

    private func stopMorphClock() {
        morphLink?.invalidate()
        morphLink = nil
    }

    /// 仅处理最新一代动画：停掉时钟，把窗口从包络缩回静止带留白尺寸，再提交落定轮廓。
    private func finishMorph(generation: Int) {
        guard generation == animationGeneration else { return }
        stopMorphClock()
        isAnimating = false
        let completion = settleCompletion
        settleCompletion = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: targetSize, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: targetSize, showsContent: showsContent)
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
