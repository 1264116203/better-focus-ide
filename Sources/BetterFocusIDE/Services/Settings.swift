// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import AppKit
import Combine
import SwiftUI

/// 持久化的用户设置，从 `~/Library/Application Support/BetterFocusIDE/settings.json`
/// 加载并保存回该文件。
///
/// 这是唯一的实时配置来源（对应 Python 参考实现的 `config` 模块）：所有消费者都在
/// 调用时读取这些值，因此改动无需重启即刻生效。设置面板经 `SettingCatalog` 写入，
/// 后者调用 `changes.send()`，让灵动岛重新布局（对应 Python `settings.on_change`）。
final class Settings: ObservableObject {
    static let shared = Settings()

    /// 任一设置经 catalog 变更后发出，让灵动岛与面板做出反应（重新布局 / 刷新置灰）。
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
    @Published var cardMinHeight: Double = 0
    @Published var cardInset: Double = 32
    @Published var bodyFont: Double = 12
    @Published var optionFont: Double = 12
    @Published var descFont: Double = 10.5
    @Published var optionRowMin: Double = 30
    @Published var bubbleWidth: Double = 44
    @Published var bubbleHeight: Double = 26
    @Published var notifyWidth: Double = 380
    @Published var notifyHeight: Double = 74
    /// 刘海屏下卡片内容到摄像头区域的额外间距（pt），可为负值使内容更贴近刘海
    @Published var notchTopPadding: Double = 4

    // MARK: - 外观 (appearance)；颜色以 "r,g,b" 字符串存储
    @Published var backgroundColor = "0.05,0.05,0.07"
    @Published var backgroundAlpha: Double = 0.96
    @Published var accentColor = "0.29,0.62,1.0"
    @Published var qoderTint = "0.58,0.45,0.82"
    @Published var opencodeTint = "0.06,0.73,0.51"
    @Published var radiusExpanded: Double = 22
    @Published var radiusBubble: Double = 13

    // MARK: - 动画 (motion)
    @Published var motionGrowBounce: Double = 0.25
    /// 三态："system" 跟随无障碍设置，"on"/"off" 强制。
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

    /// 可选的系统提示音（名字，展示标签）。
    static let soundChoices: [(String, String)] = [
        ("", "不播放"), ("Ping", "Ping（清脆）"), ("Glass", "Glass（玻璃）"),
        ("Hero", "Hero（上扬）"), ("Frog", "Frog（蛙鸣）"), ("Funk", "Funk（放克）"),
        ("Blow", "Blow（吹气）"), ("Bottle", "Bottle（瓶口）"), ("Morse", "Morse（摩尔斯）"),
        ("Pop", "Pop（气泡）"), ("Purr", "Purr（呼噜）"), ("Sosumi", "Sosumi"),
        ("Submarine", "Submarine（潜艇）"), ("Tink", "Tink（轻击）"), ("Basso", "Basso（低沉）"),
    ]

    /// 可选的触感反馈模式。
    static let hapticChoices: [(String, String)] = [
        ("generic", "通用（推荐）"), ("levelChange", "变化（档位）"),
    ]

    /// 可选的动画帧率（"0" = 自动跟随屏幕）。
    static let fpsChoices: [(String, String)] = [
        ("0", "自动（跟随屏幕，ProMotion 120Hz）"), ("60", "60 fps"),
        ("90", "90 fps"), ("120", "120 fps"),
    ]

    // MARK: - 派生颜色

    var backgroundRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(backgroundColor, fallback: (0.05, 0.05, 0.07)) }
    var accentRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(accentColor, fallback: (0.29, 0.62, 1.0)) }
    var qoderTintRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(qoderTint, fallback: (0.58, 0.45, 0.82)) }
    var opencodeTintRGB: (r: Double, g: Double, b: Double) { Self.parseRGB(opencodeTint, fallback: (0.06, 0.73, 0.51)) }

    /// 解析后的 reduce-motion 布尔值（三态 → bool）。
    var reduceMotionResolved: Bool {
        switch reduceMotion {
        case "on": return true
        case "off": return false
        default: return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    /// 把 "r,g,b" 字符串解析成三元组；字段不足时回退到 fallback。
    static func parseRGB(_ text: String, fallback: (Double, Double, Double)) -> (r: Double, g: Double, b: Double) {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return (fallback.0, fallback.1, fallback.2) }
        return (parts[0], parts[1], parts[2])
    }

    /// 把三元组格式化为 "r,g,b" 字符串（4 位有效数字）。
    static func rgbString(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "%.4g,%.4g,%.4g", r, g, b)
    }

    /// 通知订阅者某设置已变更（灵动岛据此重新布局）。
    func markChanged() { changes.send() }

    private init() {
        load()
    }

    // MARK: - 持久化

    /// 落盘结构：版本号 + 键值映射。缺键读取时用 `??` 回退，保证向后兼容。
    private struct Stored: Codable {
        var version: Int
        var values: [String: AnyCodableValue]
    }

    /// 从 settings.json 加载；文件缺失或解码失败时保留当前（默认）值。
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
        notchTopPadding = v["notchTopPadding"]?.doubleValue ?? notchTopPadding
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

    /// 把所有 @Published 字段序列化进 values 并原子写盘。
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
        values["notchTopPadding"] = .double(notchTopPadding)
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

    // MARK: - 去抖保存（面板拖动时手停下后只写一次）

    private var saveWork: DispatchWorkItem?

    /// 安排一次延迟保存：反复调用只保留最后一次，避免拖动滑块时高频写盘。
    func scheduleSave(delay: TimeInterval = 0.5) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 取消待执行的保存并立即落盘。
    func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }

    // MARK: - 恢复出厂默认

    /// 把所有字段重置为默认值，随后广播变更并落盘。
    func resetAll() {
        permissionEnabled = true; questionEnabled = true; turnNotifyEnabled = true
        turnNotifyJump = true; permissionNoticeJump = true
        cardWidth = 540; cardMinHeight = 0; cardInset = 32; bodyFont = 12
        optionFont = 12; descFont = 10.5; optionRowMin = 30
        bubbleWidth = 44; bubbleHeight = 26; notifyWidth = 380; notifyHeight = 100
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
    /// 宽松取 Int：int 直接取，double 截断取整，其余 nil。
    var intValue: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
    /// 宽松取 Double：double 直接取，int 提升为 Double，其余 nil。
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
}
