// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import CoreGraphics

// MARK: - NotchLayout

enum NotchLayout {
    static let shoulder: CGFloat = 14
    static let horizontalInset: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let spacing: CGFloat = 12
    static let bottomInset: CGFloat = 16
    static var chromeHeight: CGFloat { headerHeight + spacing + bottomInset }
    
    // MARK: - Python-aligned sizes (read live from Settings so edits apply at once)
    
    /// Notification banner (Python EXPANDED_WIDTH × EXPANDED_HEIGHT).
    static var expandedWidth: CGFloat { CGFloat(Settings.shared.notifyWidth) }
    static var expandedHeight: CGFloat { CGFloat(Settings.shared.notifyHeight) }
    /// Question / permission card width (Python QUESTION_CARD_WIDTH).
    static var questionCardWidth: CGFloat { CGFloat(Settings.shared.cardWidth) }
    /// History panel width (Python HISTORY_WIDTH = EXPANDED_WIDTH).
    static var historyWidth: CGFloat { CGFloat(Settings.shared.notifyWidth) }
    
    // Card layout metrics (Python config.py)
    static var cardInset: CGFloat { CGFloat(Settings.shared.cardInset) }
    static let cardHeaderHeight: CGFloat = 26
    static let cardGap: CGFloat = 8
    static var questionBodyFont: CGFloat { CGFloat(Settings.shared.bodyFont) }
    static var questionOptionRowMin: CGFloat { CGFloat(Settings.shared.optionRowMin) }
    static let questionOtherRowHeight: CGFloat = 30
    static let questionSendHeight: CGFloat = 30
    static let questionMaxBodyLines: Int = 4
    static let permissionButtonHeight: CGFloat = 32
    static let permissionButtonGap: CGFloat = 8
    
    // Idle dot (Python IDLE_DOT_RADIUS / IDLE_DOT_PULSE)
    static let idleDotRadius: CGFloat = 3.0
    static let idleDotPulse: CGFloat = 1.2
    static var idlePulsePeriod: TimeInterval { Settings.shared.idlePulsePeriod }
    
    // Accent color (Python ACCENT_COLOR)
    static var accentColor: (r: Double, g: Double, b: Double) {
        let c = Settings.shared.accentRGB
        return (r: c.r, g: c.g, b: c.b)
    }
    
    /// Corners of a surface of this height (cap = radius_expanded).
    static func surfaceRadius(height: CGFloat) -> CGFloat {
        min(CGFloat(Settings.shared.radiusExpanded), height * 0.34)
    }
    static func shoulder(height: CGFloat) -> CGFloat { min(shoulder, height * 0.19) }
    
    /// The optional outline's stroke.
    static let outlineWidth: CGFloat = 2
    
    // MARK: Capsule
    
    /// The menu bar a capsule leaves above and below itself.
    static let capsuleMargin: CGFloat = 2
    
    /// A closed capsule is round at its ends (cap = radius_bubble).
    static func capsuleRadius(height: CGFloat) -> CGFloat {
        min(max(0, height) / 2, CGFloat(Settings.shared.radiusBubble))
    }
    
    /// The capsule outline path.
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
    
    /// The capsule body within a rect.
    static func capsuleBody(in rect: CGRect, gap: CGFloat) -> CGRect {
        let width = max(0, rect.width), height = max(0, rect.height)
        let side = min(shoulder(height: height), width / 2)
        let inset = min(max(0, gap), height / 2)
        return CGRect(x: rect.minX + side, y: rect.minY + inset,
                      width: width - side * 2, height: height - inset * 2)
    }
}

// MARK: - NotchGeometry

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
    
    var floats: Bool { floatingGap != nil }
    
    var safeContentTop: CGFloat { floats ? NotchLayout.bottomInset : cameraHeight + 10 }
    
    var stripHeight: CGFloat { cameraHeight }
    
    var collapsed: CGSize {
        CGSize(width: min(screen.width - 24, cameraWidth), height: stripHeight)
    }
    
    func restingSize(showsContent: Bool) -> CGSize {
        if showsContent { return collapsed }
        guard floats else { return CGSize(width: cameraWidth, height: cameraHeight) }
        let shoulders = NotchLayout.shoulder(height: stripHeight) * 2
        return CGSize(width: min(cameraWidth, cameraWidth + shoulders), height: cameraHeight)
    }
    
    func frame(for size: CGSize) -> CGRect {
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - NotchMotion

enum NotchMotion {
    struct Spring: Equatable {
        var duration: TimeInterval
        var bounce: Double
        
        func progress(at time: TimeInterval) -> Double {
            guard time > 0 else { return 0 }
            let natural = 2 * Double.pi / duration
            let damping = 1 - bounce
            if damping >= 1 { return 1 - exp(-natural * time) * (1 + natural * time) }
            let damped = natural * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * natural * time)
                * (cos(damped * time) + damping * natural / damped * sin(damped * time))
        }
        
        var overshoot: Double {
            guard bounce > 0 else { return 0 }
            let damping = 1 - bounce
            return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
        }
        
        func limited(travel: CGFloat, limit: CGFloat) -> Spring {
            guard bounce > 0, travel > 0, Double(travel) * overshoot > Double(limit) else { return self }
            let share = log(Double(max(limit, 0.01) / travel))
            return Spring(duration: duration, bounce: 1 + share / (Double.pi * Double.pi + share * share).squareRoot())
        }
    }
    
    // Springs aligned with Python motion.spring_for: grow springs bounce by
    // MOTION_GROW_BOUNCE, shrink springs are critically damped (no overshoot),
    // OVERSHOOT_LIMIT=12. Durations scale by 1 / animation_speed (a higher
    // speed finishes sooner). Reduce-motion forces grow bounce to 0 — the morph
    // still runs, just monotonic with no rebound (Python spring_for reduce_motion).
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
    static let overshootLimit: CGFloat = 12
    static let settledDistance: CGFloat = 0.5
    
    static func spring(from: CGFloat, to: CGFloat, width: Bool) -> Spring {
        let spring = to > from ? (width ? growingWidth : growingHeight) : (width ? shrinkingWidth : shrinkingHeight)
        return spring.limited(travel: abs(to - from), limit: overshootLimit)
    }
    
    static func size(at time: TimeInterval, from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            guard start != end else { return end }
            let spring = spring(from: start, to: end, width: width)
            return max(0, start + (end - start) * CGFloat(spring.progress(at: time)))
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
    
    static func settlingTime(from: CGSize, to: CGSize) -> TimeInterval {
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            let size = size(at: time, from: from, to: to)
            if abs(size.width - to.width) > settledDistance || abs(size.height - to.height) > settledDistance {
                settled = time + step
            }
            time += step
        }
        return settled
    }
    
    static func frames(from: CGSize, to: CGSize) -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let duration = settlingTime(from: from, to: to)
        // Sample rate = animation_fps (0 = auto → 120Hz, matching ProMotion).
        let fps = Settings.shared.animationFps > 0 ? Double(Settings.shared.animationFps) : 120
        let count = max(1, Int((duration * fps).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? to : size(at: duration * $0, from: from, to: to) }
        return (sizes, keyTimes, duration)
    }
    
    static func envelope(from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            let swing = end > start ? spring(from: start, to: end, width: width).overshoot : 0
            guard swing > 0 else { return max(start, end) }
            return (end + (end - start) * CGFloat(swing)).rounded(.up)
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
}
