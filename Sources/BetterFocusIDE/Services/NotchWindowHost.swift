// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI
import QuartzCore

// MARK: - NotchPanel

final class NotchPanel: NSPanel {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    var acceptsKeyFocus = false

    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

// MARK: - NotchHostingView

final class NotchHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow clicks to pass through transparent areas
        guard let superview = self.superview else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - NotchCanvas

/// The window's content view. A black base layer masked to the island
/// silhouette, a frosted-glass `NSVisualEffectView` that fades in on an
/// expanded card, and the SwiftUI content hosted on top — all clipped to the
/// morphing silhouette.
///
/// During a resize the window is held at the *envelope* size (the widest the
/// spring swings to, plus shadow padding) while the mask path morphs
/// frame-by-frame, so the notch corners and shoulders stay true as the sides
/// swing apart. The padding around the island is transparent, which is where
/// the window's drop shadow renders.
final class NotchCanvas: NSView {
    let host: NotchHostingView
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let glass = NSVisualEffectView()
    /// A dark wash over the frosted glass. `.hudWindow` blurs whatever sits
    /// behind the window, and at the top of the screen that's the (often light)
    /// menu bar, which washed the whole card to a pale grey. This constant dim
    /// pulls the frost back to a dark, subtle one. When collapsed the glass is
    /// transparent, so the dim simply sits on the black base and stays black.
    private let dim = NSView()
    /// The size the island is heading to / resting at (content size).
    private var contentSize: CGSize
    private var trackingArea: NSTrackingArea?

    // MARK: - Mouse callbacks (wired by NotchWindowHost → NotchService)
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
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        applyBaseColor()
        layer?.masksToBounds = true
        layer?.mask = silhouette

        // Frosted dark material behind the content. It blurs what's behind the
        // window, so it only reads on an expanded card; the collapsed strip
        // stays solid black to blend into the physical notch.
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.alphaValue = 0
        addSubview(glass, positioned: .below, relativeTo: host)
        addSubview(host)

        // Dark wash above the glass, below the content (constant alpha).
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

    // MARK: Geometry helpers

    /// The island's rect for `size`, centered horizontally in the current
    /// canvas width, hanging from the top edge (flipped, so y=0 is screen top).
    func islandRect(for size: CGSize) -> CGRect {
        CGRect(x: (bounds.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    /// The silhouette path for `size` within the current canvas bounds.
    func morphPath(for size: CGSize) -> CGPath {
        let shape = NotchShape(attached: true,
                               radius: NotchLayout.surfaceRadius(height: size.height),
                               floatingGap: nil)
        return shape.path(in: islandRect(for: size)).cgPath
    }

    /// The island's size as currently drawn (reads the presentation path so an
    /// interrupted animation resumes from what's on screen, not the target).
    var visibleSize: CGSize? {
        guard let path = (silhouette.presentation()?.path ?? silhouette.path) else { return nil }
        let box = path.boundingBoxOfPath
        guard !box.isNull else { return nil }
        return CGSize(width: box.width, height: max(0, box.maxY))
    }

    // MARK: Resting layout

    func setContentSize(_ size: CGSize) {
        contentSize = size
        needsLayout = true
    }

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

    /// Base island color from Settings (background_color × background_alpha),
    /// replacing the fixed notch black so appearance edits apply live. Re-read
    /// on every layout, which the settings-change re-present triggers.
    private func applyBaseColor() {
        let c = Settings.shared.backgroundRGB
        let alpha = CGFloat(min(1, max(0, Settings.shared.backgroundAlpha)))
        layer?.backgroundColor = NSColor(
            srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha
        ).cgColor
    }

    /// The glass appears only on an expanded card; on the thin resting strip it
    /// is off so the island reads as solid notch black. The hairline edge stroke
    /// appears only when expanded (Python `_draw_hairline`).
    private func updateContrast() {
        let expanded = contentSize.height > 60
        // Edge highlight: subtle white stroke on expanded cards only.
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

    func containsVisiblePoint(_ point: NSPoint) -> Bool {
        guard let path = silhouette.path else { return false }
        return path.contains(point)
    }

    // MARK: - Mouse tracking

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

    // MARK: Morph

    /// Begin a spring-driven shape morph to `size`. The caller has already put
    /// the window at the envelope frame, so `bounds` is the padded envelope.
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

        // Content and glass unveil with the growing shape (expand) or leave
        // ahead of the shrinking shape (collapse) so nothing is squashed mid-flight.
        // Fade windows aligned with Python: expand p=0.15→0.65, collapse p=0.40→0.06.
        let totalDuration = animation.duration
        let fadeStart: CFTimeInterval
        let fadeDuration: CFTimeInterval
        if expanding {
            // Content appears from 15% to 65% of the animation.
            fadeStart = totalDuration * 0.15
            fadeDuration = totalDuration * 0.50
        } else {
            // Content disappears from 0% to 40% of the animation (starts immediately).
            fadeStart = 0
            fadeDuration = totalDuration * 0.40
        }
        fadeLayer(host.layer, from: expanding ? 0 : 1, to: expanding ? 1 : 0,
                  duration: fadeDuration, delay: fadeStart, easeIn: !expanding)
        fadeGlass(to: expanding ? 1 : 0, duration: fadeDuration, delay: fadeStart)
    }

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

    /// Commit the morph once the spring settles: drop the animations and lay
    /// out for the resting (== content) size. `bounds` is already the padded
    /// target when this is called.
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

final class NotchWindowHost: NSObject, CAAnimationDelegate {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private var currentGeometry: NotchGeometry
    private var appliedFrame = CGRect.zero
    private var animationGeneration = 0
    private var isAnimating = false
    private var settleCompletion: (() -> Void)?
    private(set) var targetSize: CGSize
    /// Whether the island is displaying content cards (vs. collapsed capsule).
    private var showsContent = false

    /// Transparent room around the island so the window's drop shadow has space
    /// to render within the window bounds (top is flush with the screen edge).
    private let shadowPad: CGFloat = 26

    /// Wire mouse tracking callbacks on the canvas.
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

    /// The padded window frame that holds an island of `islandSize` at the top
    /// centre: `shadowPad` on the sides and bottom, none on top (it's flush
    /// with the screen edge, where a shadow would fall off-screen anyway).
    /// When `showsContent` is `false` the frame sits just below the notch
    /// cutout so the collapsed capsule doesn't overlap the camera housing.
    private func panelFrame(for islandSize: CGSize, showsContent: Bool = true) -> CGRect {
        let base = currentGeometry.frame(for: islandSize, showsContent: showsContent)
        return CGRect(x: base.minX - shadowPad,
                      y: base.minY - shadowPad,
                      width: base.width + shadowPad * 2,
                      height: base.height + shadowPad)
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, showsContent: Bool) {
        targetSize = size
        currentGeometry = geometry
        self.showsContent = showsContent

        let fromSize = canvas.visibleSize ?? size
        // Reduce-motion is resolved inside NotchMotion (grow bounce forced to 0),
        // matching Python spring_for: the morph still runs, just without rebound.
        // So the spring is allowed whenever we animate to a different size, and
        // the tri-state (system/on/off) is honored through the bounce, not here.
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

    /// Hold the window at the envelope (the widest/tallest the spring reaches,
    /// padded for the shadow) so the overshoot never clips, then morph the mask
    /// path through the spring's interpolated sizes.
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
        canvas.layoutSubtreeIfNeeded()
        CATransaction.commit()

        // Paths are computed after the window is at the padded envelope, so the
        // canvas bounds already centre the island correctly.
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

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag,
              anim.value(forKey: "notchGeneration") as? Int == animationGeneration else { return }
        isAnimating = false
        let completion = settleCompletion
        settleCompletion = nil
        // Shrink the window from the envelope back to the resting padded size,
        // then commit the settled silhouette against the new bounds.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(pixelAligned(panelFrame(for: targetSize, showsContent: showsContent)), display: true)
        appliedFrame = panelFrame(for: targetSize, showsContent: showsContent)
        canvas.layoutSubtreeIfNeeded()
        canvas.settleMorph(to: targetSize)
        CATransaction.commit()
        completion?()
    }

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
