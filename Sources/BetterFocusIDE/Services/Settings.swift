// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import AppKit
import Combine
import SwiftUI

/// Persistent user settings, loaded from and saved to
/// `~/Library/Application Support/BetterFocusIDE/settings.json`.
///
/// This is the single live configuration source (the Swift counterpart of the
/// Python reference's `config` module): every consumer reads these values at
/// call time, so a change takes effect immediately without a restart. The
/// settings panel writes through `SettingCatalog`, which calls
/// `changes.send()` so the island can re-layout (Python `settings.on_change`).
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Emitted after any setting is mutated through the catalog, so the island
    /// and panel can react (re-layout / refresh greying).
    let changes = PassthroughSubject<Void, Never>()

    private let settingsURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterFocusIDE/settings.json")
    }()

    // MARK: - 提醒 (alerts)
    @Published var permissionEnabled = true
    @Published var questionEnabled = true
    @Published var turnNotifyEnabled = true
    @Published var turnNotifyJump = true
    @Published var permissionNoticeJump = true

    // MARK: - 尺寸 (sizes)
    @Published var cardWidth: Double = 540
    @Published var cardMinHeight: Double = 200
    @Published var cardInset: Double = 18
    @Published var bodyFont: Double = 12
    @Published var optionFont: Double = 12
    @Published var descFont: Double = 10.5
    @Published var optionRowMin: Double = 30
    @Published var bubbleWidth: Double = 44
    @Published var bubbleHeight: Double = 26
    @Published var notifyWidth: Double = 380
    @Published var notifyHeight: Double = 74

    // MARK: - 外观 (appearance); colors stored as "r,g,b"
    @Published var backgroundColor = "0.05,0.05,0.07"
    @Published var backgroundAlpha: Double = 0.96
    @Published var accentColor = "0.29,0.62,1.0"
    @Published var qoderTint = "0.58,0.45,0.82"
    @Published var opencodeTint = "0.06,0.73,0.51"
    @Published var radiusExpanded: Double = 22
    @Published var radiusBubble: Double = 13

    // MARK: - 动画 (motion)
    @Published var motionGrowBounce: Double = 0.25
    /// Tri-state: "system" follows the accessibility setting, "on"/"off" force.
    @Published var reduceMotion = "system"
    @Published var animationSpeed: Double = 1.0
    @Published var animationFps = 0
    @Published var hoverExpandDelay: Double = 0.18
    @Published var hoverCollapseDelay: Double = 0.35
    @Published var notifyBannerDuration = 5.0
    @Published var historyDuration: Double = 8
    @Published var idlePulsePeriod: Double = 2.4

    // MARK: - 声音与触感 (sound & haptics)
    @Published var notifySound = "Ping"
    @Published var notifyVolume = 1.0
    @Published var soundOnArrive = true
    @Published var soundOnAnswer = false
    @Published var hapticOnArrive = true
    @Published var hapticOnAnswer = false
    @Published var hapticPattern = "generic"

    // MARK: - 行为 (behavior)
    @Published var pinByDefault = true
    @Published var clickGuard: Double = 0.5
    @Published var manualCollapseHold: Double = 3
    @Published var questionHold = true
    @Published var permissionHold = true

    // MARK: - 超时与排队 (timeouts & queues)
    @Published var agentWaitLimit = 600
    @Published var questionQueueLimit = 8
    @Published var permissionQueueLimit = 8
    @Published var sweepInterval = 15
    @Published var sweepGrace = 45

    /// Available system sounds (name, display label).
    static let soundChoices: [(String, String)] = [
        ("", "不播放"), ("Ping", "Ping（清脆）"), ("Glass", "Glass（玻璃）"),
        ("Hero", "Hero（上扬）"), ("Frog", "Frog（蛙鸣）"), ("Funk", "Funk（放克）"),
        ("Blow", "Blow（吹气）"), ("Bottle", "Bottle（瓶口）"), ("Morse", "Morse（摩尔斯）"),
        ("Pop", "Pop（气泡）"), ("Purr", "Purr（呼噜）"), ("Sosumi", "Sosumi"),
        ("Submarine", "Submarine（潜艇）"), ("Tink", "Tink（轻击）"), ("Basso", "Basso（低沉）"),
    ]

    static let hapticChoices: [(String, String)] = [
        ("generic", "通用（推荐）"), ("levelChange", "变化（档位）"),
    ]

    static let fpsChoices: [(String, String)] = [
        ("0", "自动（跟随屏幕，ProMotion 120Hz）"), ("60", "60 fps"),
        ("90", "90 fps"), ("120", "120 fps"),
    ]

    // MARK: - Derived colors

    var backgroundRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(backgroundColor, fallback: (0.05, 0.05, 0.07)) }
    var accentRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(accentColor, fallback: (0.29, 0.62, 1.0)) }
    var qoderTintRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(qoderTint, fallback: (0.58, 0.45, 0.82)) }
    var opencodeTintRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(opencodeTint, fallback: (0.06, 0.73, 0.51)) }

    /// Resolved reduce-motion flag (tri-state → bool).
    var reduceMotionResolved: Bool {
        switch reduceMotion {
        case "on": return true
        case "off": return false
        default: return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    static func parseRGB(_ text: String, fallback: (Double, Double, Double)) -> (r: Double, g: Double, b: Double) {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return (fallback.0, fallback.1, fallback.2) }
        return (parts[0], parts[1], parts[2])
    }

    static func rgbString(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "%.4g,%.4g,%.4g", r, g, b)
    }

    /// Notify subscribers that a setting changed (island re-layouts).
    func markChanged() { changes.send() }

    private init() {
        load()
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var version: Int
        var values: [String: AnyCodableValue]
    }

    func load() {
        guard let data = try? Data(contentsOf: settingsURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        let v = stored.values
        permissionEnabled = v["permissionEnabled"]?.boolValue ?? permissionEnabled
        questionEnabled = v["questionEnabled"]?.boolValue ?? questionEnabled
        turnNotifyEnabled = v["turnNotifyEnabled"]?.boolValue ?? turnNotifyEnabled
        turnNotifyJump = v["turnNotifyJump"]?.boolValue ?? turnNotifyJump
        permissionNoticeJump = v["permissionNoticeJump"]?.boolValue ?? permissionNoticeJump
        cardWidth = v["cardWidth"]?.doubleValue ?? cardWidth
        cardMinHeight = v["cardMinHeight"]?.doubleValue ?? cardMinHeight
        cardInset = v["cardInset"]?.doubleValue ?? cardInset
        bodyFont = v["bodyFont"]?.doubleValue ?? bodyFont
        optionFont = v["optionFont"]?.doubleValue ?? optionFont
        descFont = v["descFont"]?.doubleValue ?? descFont
        optionRowMin = v["optionRowMin"]?.doubleValue ?? optionRowMin
        bubbleWidth = v["bubbleWidth"]?.doubleValue ?? bubbleWidth
        bubbleHeight = v["bubbleHeight"]?.doubleValue ?? bubbleHeight
        notifyWidth = v["notifyWidth"]?.doubleValue ?? notifyWidth
        notifyHeight = v["notifyHeight"]?.doubleValue ?? notifyHeight
        backgroundColor = v["backgroundColor"]?.stringValue ?? backgroundColor
        backgroundAlpha = v["backgroundAlpha"]?.doubleValue ?? backgroundAlpha
        accentColor = v["accentColor"]?.stringValue ?? accentColor
        qoderTint = v["qoderTint"]?.stringValue ?? qoderTint
        opencodeTint = v["opencodeTint"]?.stringValue ?? opencodeTint
        radiusExpanded = v["radiusExpanded"]?.doubleValue ?? radiusExpanded
        radiusBubble = v["radiusBubble"]?.doubleValue ?? radiusBubble
        motionGrowBounce = v["motionGrowBounce"]?.doubleValue ?? motionGrowBounce
        reduceMotion = v["reduceMotion"]?.stringValue ?? reduceMotion
        animationSpeed = v["animationSpeed"]?.doubleValue ?? animationSpeed
        animationFps = v["animationFps"]?.intValue ?? animationFps
        hoverExpandDelay = v["hoverExpandDelay"]?.doubleValue ?? hoverExpandDelay
        hoverCollapseDelay = v["hoverCollapseDelay"]?.doubleValue ?? hoverCollapseDelay
        notifyBannerDuration = v["notifyBannerDuration"]?.doubleValue ?? notifyBannerDuration
        historyDuration = v["historyDuration"]?.doubleValue ?? historyDuration
        idlePulsePeriod = v["idlePulsePeriod"]?.doubleValue ?? idlePulsePeriod
        notifySound = v["notifySound"]?.stringValue ?? notifySound
        notifyVolume = v["notifyVolume"]?.doubleValue ?? notifyVolume
        soundOnArrive = v["soundOnArrive"]?.boolValue ?? soundOnArrive
        soundOnAnswer = v["soundOnAnswer"]?.boolValue ?? soundOnAnswer
        hapticOnArrive = v["hapticOnArrive"]?.boolValue ?? hapticOnArrive
        hapticOnAnswer = v["hapticOnAnswer"]?.boolValue ?? hapticOnAnswer
        hapticPattern = v["hapticPattern"]?.stringValue ?? hapticPattern
        pinByDefault = v["pinByDefault"]?.boolValue ?? pinByDefault
        clickGuard = v["clickGuard"]?.doubleValue ?? clickGuard
        manualCollapseHold = v["manualCollapseHold"]?.doubleValue ?? manualCollapseHold
        questionHold = v["questionHold"]?.boolValue ?? questionHold
        permissionHold = v["permissionHold"]?.boolValue ?? permissionHold
        agentWaitLimit = v["agentWaitLimit"]?.intValue ?? agentWaitLimit
        questionQueueLimit = v["questionQueueLimit"]?.intValue ?? questionQueueLimit
        permissionQueueLimit = v["permissionQueueLimit"]?.intValue ?? permissionQueueLimit
        sweepInterval = v["sweepInterval"]?.intValue ?? sweepInterval
        sweepGrace = v["sweepGrace"]?.intValue ?? sweepGrace
    }

    func save() {
        var values: [String: AnyCodableValue] = [:]
        values["permissionEnabled"] = .bool(permissionEnabled)
        values["questionEnabled"] = .bool(questionEnabled)
        values["turnNotifyEnabled"] = .bool(turnNotifyEnabled)
        values["turnNotifyJump"] = .bool(turnNotifyJump)
        values["permissionNoticeJump"] = .bool(permissionNoticeJump)
        values["cardWidth"] = .double(cardWidth)
        values["cardMinHeight"] = .double(cardMinHeight)
        values["cardInset"] = .double(cardInset)
        values["bodyFont"] = .double(bodyFont)
        values["optionFont"] = .double(optionFont)
        values["descFont"] = .double(descFont)
        values["optionRowMin"] = .double(optionRowMin)
        values["bubbleWidth"] = .double(bubbleWidth)
        values["bubbleHeight"] = .double(bubbleHeight)
        values["notifyWidth"] = .double(notifyWidth)
        values["notifyHeight"] = .double(notifyHeight)
        values["backgroundColor"] = .string(backgroundColor)
        values["backgroundAlpha"] = .double(backgroundAlpha)
        values["accentColor"] = .string(accentColor)
        values["qoderTint"] = .string(qoderTint)
        values["opencodeTint"] = .string(opencodeTint)
        values["radiusExpanded"] = .double(radiusExpanded)
        values["radiusBubble"] = .double(radiusBubble)
        values["motionGrowBounce"] = .double(motionGrowBounce)
        values["reduceMotion"] = .string(reduceMotion)
        values["animationSpeed"] = .double(animationSpeed)
        values["animationFps"] = .int(animationFps)
        values["hoverExpandDelay"] = .double(hoverExpandDelay)
        values["hoverCollapseDelay"] = .double(hoverCollapseDelay)
        values["notifyBannerDuration"] = .double(notifyBannerDuration)
        values["historyDuration"] = .double(historyDuration)
        values["idlePulsePeriod"] = .double(idlePulsePeriod)
        values["notifySound"] = .string(notifySound)
        values["notifyVolume"] = .double(notifyVolume)
        values["soundOnArrive"] = .bool(soundOnArrive)
        values["soundOnAnswer"] = .bool(soundOnAnswer)
        values["hapticOnArrive"] = .bool(hapticOnArrive)
        values["hapticOnAnswer"] = .bool(hapticOnAnswer)
        values["hapticPattern"] = .string(hapticPattern)
        values["pinByDefault"] = .bool(pinByDefault)
        values["clickGuard"] = .double(clickGuard)
        values["manualCollapseHold"] = .double(manualCollapseHold)
        values["questionHold"] = .bool(questionHold)
        values["permissionHold"] = .bool(permissionHold)
        values["agentWaitLimit"] = .int(agentWaitLimit)
        values["questionQueueLimit"] = .int(questionQueueLimit)
        values["permissionQueueLimit"] = .int(permissionQueueLimit)
        values["sweepInterval"] = .int(sweepInterval)
        values["sweepGrace"] = .int(sweepGrace)

        let stored = Stored(version: 1, values: values)
        let dir = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: - Debounced save (panel drags write once after the hand stops)

    private var saveWork: DispatchWorkItem?

    func scheduleSave(delay: TimeInterval = 0.5) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }

    // MARK: - Reset to factory defaults

    func resetAll() {
        permissionEnabled = true; questionEnabled = true; turnNotifyEnabled = true
        turnNotifyJump = true; permissionNoticeJump = true
        cardWidth = 540; cardMinHeight = 200; cardInset = 18; bodyFont = 12
        optionFont = 12; descFont = 10.5; optionRowMin = 30
        bubbleWidth = 44; bubbleHeight = 26; notifyWidth = 380; notifyHeight = 74
        backgroundColor = "0.05,0.05,0.07"; backgroundAlpha = 0.96
        accentColor = "0.29,0.62,1.0"; qoderTint = "0.58,0.45,0.82"; opencodeTint = "0.06,0.73,0.51"
        radiusExpanded = 22; radiusBubble = 13
        motionGrowBounce = 0.25; reduceMotion = "system"; animationSpeed = 1.0; animationFps = 0
        hoverExpandDelay = 0.18; hoverCollapseDelay = 0.35
        notifyBannerDuration = 5.0; historyDuration = 8; idlePulsePeriod = 2.4
        notifySound = "Ping"; notifyVolume = 1.0
        soundOnArrive = true; soundOnAnswer = false
        hapticOnArrive = true; hapticOnAnswer = false; hapticPattern = "generic"
        pinByDefault = true; clickGuard = 0.5; manualCollapseHold = 3
        questionHold = true; permissionHold = true
        agentWaitLimit = 600; questionQueueLimit = 8; permissionQueueLimit = 8
        sweepInterval = 15; sweepGrace = 45
        markChanged()
        save()
    }
}

private extension AnyCodableValue {
    var intValue: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
}
