// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import SwiftUI

/// The value a setting row reads / writes. `choice` rows always carry a
/// `String` (the option value); `color` rows carry device RGB.
enum SettingValue: Equatable {
    case bool(Bool)
    case double(Double)
    case int(Int)
    case string(String)
    case rgb(Double, Double, Double)
}

enum SettingKind {
    case slider, toggle, color, choice
}

/// One configurable item. Mirrors the Python reference's `Setting` dataclass:
/// the fields up to `defaultValue` participate in read/write & persistence
/// (via the closures); `section` / `enabledWhen` / `enabledBy` / `advanced` /
/// `keywords` only describe presentation & filtering.
struct SettingDefinition: Identifiable {
    let key: String
    let label: String
    let kind: SettingKind
    let group: String
    var section: String = ""
    var min: Double = 0
    var max: Double = 1
    var step: Double = 0
    var unit: String = ""
    var digits: Int = 2
    var choices: [(String, String)] = []
    var note: String = ""
    var needsReinstall: Bool = false
    var enabledBy: [String] = []
    var enabledWhen: (() -> Bool)? = nil
    var advanced: Bool = false
    var keywords: [String] = []
    let defaultValue: SettingValue
    let get: () -> SettingValue
    let set: (SettingValue) -> Void

    var id: String { key }

    func isEnabled() -> Bool { enabledWhen?() ?? true }

    /// Search hit: label / group / key / keywords, any contains (case-insensitive).
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let haystack = ([label, group, key] + keywords).joined(separator: " ").lowercased()
        return haystack.contains(q)
    }
}

/// KeyPath-based accessors keep the catalog compact and type-safe.
private func getD(_ kp: KeyPath<Settings, Double>) -> () -> SettingValue {
    { .double(Settings.shared[keyPath: kp]) }
}
private func setD(_ kp: ReferenceWritableKeyPath<Settings, Double>) -> (SettingValue) -> Void {
    { if case .double(let v) = $0 { Settings.shared[keyPath: kp] = v; Settings.shared.markChanged() } }
}
private func getB(_ kp: KeyPath<Settings, Bool>) -> () -> SettingValue {
    { .bool(Settings.shared[keyPath: kp]) }
}
private func setB(_ kp: ReferenceWritableKeyPath<Settings, Bool>) -> (SettingValue) -> Void {
    { if case .bool(let v) = $0 { Settings.shared[keyPath: kp] = v; Settings.shared.markChanged() } }
}
private func getI(_ kp: KeyPath<Settings, Int>) -> () -> SettingValue {
    { .int(Settings.shared[keyPath: kp]) }
}
private func setI(_ kp: ReferenceWritableKeyPath<Settings, Int>) -> (SettingValue) -> Void {
    { if case .int(let v) = $0 { Settings.shared[keyPath: kp] = v; Settings.shared.markChanged() } }
}
private func getS(_ kp: KeyPath<Settings, String>) -> () -> SettingValue {
    { .string(Settings.shared[keyPath: kp]) }
}
private func setS(_ kp: ReferenceWritableKeyPath<Settings, String>) -> (SettingValue) -> Void {
    { if case .string(let v) = $0 { Settings.shared[keyPath: kp] = v; Settings.shared.markChanged() } }
}
private func getRGB(_ kp: KeyPath<Settings, String>) -> () -> SettingValue {
    { let c = Settings.parseRGB(Settings.shared[keyPath: kp], fallback: (0, 0, 0)); return .rgb(c.r, c.g, c.b) }
}
private func setRGB(_ kp: ReferenceWritableKeyPath<Settings, String>) -> (SettingValue) -> Void {
    { if case .rgb(let r, let g, let b) = $0 { Settings.shared[keyPath: kp] = Settings.rgbString(r, g, b); Settings.shared.markChanged() } }
}
/// Int-backed value exposed to the panel as a String choice.
private func getIS(_ kp: KeyPath<Settings, Int>) -> () -> SettingValue {
    { .string(String(Settings.shared[keyPath: kp])) }
}
private func setIS(_ kp: ReferenceWritableKeyPath<Settings, Int>) -> (SettingValue) -> Void {
    { if case .string(let v) = $0 { Settings.shared[keyPath: kp] = Int(v) ?? 0; Settings.shared.markChanged() } }
}

// Dependency predicates (Python `_question_on` / `_sound_on` / …).
private let questionOn: () -> Bool = { Settings.shared.questionEnabled }
private let permissionOn: () -> Bool = { Settings.shared.permissionEnabled }
private let anyCardOn: () -> Bool = { Settings.shared.questionEnabled || Settings.shared.permissionEnabled }
private let turnNotifyOn: () -> Bool = { Settings.shared.turnNotifyEnabled }
private let soundOn: () -> Bool = { !Settings.shared.notifySound.isEmpty }
private let hapticOn: () -> Bool = { Settings.shared.hapticOnArrive || Settings.shared.hapticOnAnswer }

/// The full setting catalog, ordered exactly like the Python reference so the
/// panel's groups / sections / rows line up one-for-one.
enum SettingCatalog {
    static let groups = ["提醒", "尺寸", "外观", "动画", "声音与触感", "行为", "超时与排队"]

    static let groupHints: [String: String] = [
        "提醒": "总开关：关掉即把请求交回 IDE 自己的弹窗与提问框",
        "尺寸": "卡片、气泡与通知卡片的尺寸与字号",
        "外观": "颜色、圆角与淡入层次",
        "动画": "展开 / 收起的节奏与悬停手感",
        "声音与触感": "提示音与触控板震动",
        "行为": "卡片上屏后的固定、防误触与让位",
        "超时与排队": "等多久、同时排几项",
    ]

    static let groupSymbols: [String: String] = [
        "提醒": "bell", "尺寸": "ruler", "外观": "paintpalette", "动画": "sparkles",
        "声音与触感": "speaker.wave.2", "行为": "hand.tap", "超时与排队": "clock",
    ]

    static let all: [SettingDefinition] = [
        // ---------------- 提醒 ----------------
        SettingDefinition(key: "permissionEnabled", label: "权限申请提醒", kind: .toggle, group: "提醒",
            note: "Qoder：只弹提醒，去哪审批看 IDE 自己的弹窗（岛不再代拍板）；OpenCode：仍可在岛上直接审批。关掉后两者都不弹",
            keywords: ["权限", "授权", "permission", "approve", "allow", "提醒"],
            defaultValue: .bool(true), get: getB(\.permissionEnabled), set: setB(\.permissionEnabled)),
        SettingDefinition(key: "questionEnabled", label: "用户提问弹窗", kind: .toggle, group: "提醒",
            note: "关闭后用 IDE 自带的提问对话框，灵动岛不再接管",
            keywords: ["提问", "问题", "question", "ask"],
            defaultValue: .bool(true), get: getB(\.questionEnabled), set: setB(\.questionEnabled)),
        SettingDefinition(key: "turnNotifyEnabled", label: "回复完成通知", kind: .toggle, group: "提醒",
            note: "模型完成一轮回复后弹一条可点的气泡，按「通知停留时长」自动收起",
            keywords: ["完成", "回复", "通知", "done", "finished", "idle"],
            defaultValue: .bool(true), get: getB(\.turnNotifyEnabled), set: setB(\.turnNotifyEnabled)),
        SettingDefinition(key: "turnNotifyJump", label: "完成通知点击跳转", kind: .toggle, group: "提醒",
            note: "关掉后点气泡与历史里那一行都只是收起，不唤起 IDE",
            enabledBy: ["turnNotifyEnabled"], enabledWhen: turnNotifyOn,
            keywords: ["跳转", "唤起", "jump", "activate"],
            defaultValue: .bool(true), get: getB(\.turnNotifyJump), set: setB(\.turnNotifyJump)),
        SettingDefinition(key: "permissionNoticeJump", label: "权限提醒点击跳转", kind: .toggle, group: "提醒",
            note: "关掉后点提醒气泡与历史行都只是收起（审批仍去 IDE 原生弹窗）",
            enabledBy: ["permissionEnabled"], enabledWhen: permissionOn,
            keywords: ["跳转", "权限", "审批", "jump", "activate"],
            defaultValue: .bool(true), get: getB(\.permissionNoticeJump), set: setB(\.permissionNoticeJump)),

        // ---------------- 尺寸 ----------------
        SettingDefinition(key: "cardWidth", label: "卡片宽度", kind: .slider, group: "尺寸", section: "卡片",
            min: 360, max: 720, step: 10, unit: "pt", digits: 0,
            defaultValue: .double(540), get: getD(\.cardWidth), set: setD(\.cardWidth)),
        SettingDefinition(key: "cardMinHeight", label: "卡片最小高度", kind: .slider, group: "尺寸", section: "卡片",
            min: 0, max: 360, step: 10, unit: "pt", digits: 0,
            note: "0 = 完全按内容自适应；调大可减少卡片忽高忽低", advanced: true,
            defaultValue: .double(200), get: getD(\.cardMinHeight), set: setD(\.cardMinHeight)),
        SettingDefinition(key: "cardInset", label: "卡片内边距", kind: .slider, group: "尺寸", section: "卡片",
            min: 8, max: 40, step: 1, unit: "pt", digits: 0, advanced: true,
            defaultValue: .double(18), get: getD(\.cardInset), set: setD(\.cardInset)),
        SettingDefinition(key: "bodyFont", label: "问题正文字号", kind: .slider, group: "尺寸", section: "卡片",
            min: 10, max: 18, step: 0.5, unit: "pt", digits: 1,
            defaultValue: .double(12), get: getD(\.bodyFont), set: setD(\.bodyFont)),
        SettingDefinition(key: "optionFont", label: "选项文字字号", kind: .slider, group: "尺寸", section: "卡片",
            min: 10, max: 18, step: 0.5, unit: "pt", digits: 1,
            defaultValue: .double(12), get: getD(\.optionFont), set: setD(\.optionFont)),
        SettingDefinition(key: "descFont", label: "选项说明字号", kind: .slider, group: "尺寸", section: "卡片",
            min: 8, max: 16, step: 0.5, unit: "pt", digits: 1,
            defaultValue: .double(10.5), get: getD(\.descFont), set: setD(\.descFont)),
        SettingDefinition(key: "optionRowMin", label: "选项行最小高度", kind: .slider, group: "尺寸", section: "卡片",
            min: 24, max: 56, step: 1, unit: "pt", digits: 0,
            defaultValue: .double(30), get: getD(\.optionRowMin), set: setD(\.optionRowMin)),
        SettingDefinition(key: "bubbleWidth", label: "气泡宽度", kind: .slider, group: "尺寸", section: "气泡与通知",
            min: 34, max: 80, step: 2, unit: "pt", digits: 0,
            note: "仅无刘海 / 外接屏的悬浮胶囊生效；刘海屏收起态贴合盖板", advanced: true,
            defaultValue: .double(44), get: getD(\.bubbleWidth), set: setD(\.bubbleWidth)),
        SettingDefinition(key: "bubbleHeight", label: "气泡高度", kind: .slider, group: "尺寸", section: "气泡与通知",
            min: 20, max: 40, step: 1, unit: "pt", digits: 0,
            note: "仅无刘海 / 外接屏的悬浮胶囊生效；刘海屏收起态贴合盖板", advanced: true,
            defaultValue: .double(26), get: getD(\.bubbleHeight), set: setD(\.bubbleHeight)),
        SettingDefinition(key: "notifyWidth", label: "通知卡片宽度", kind: .slider, group: "尺寸", section: "气泡与通知",
            min: 260, max: 520, step: 10, unit: "pt", digits: 0,
            defaultValue: .double(380), get: getD(\.notifyWidth), set: setD(\.notifyWidth)),
        SettingDefinition(key: "notifyHeight", label: "通知卡片高度", kind: .slider, group: "尺寸", section: "气泡与通知",
            min: 56, max: 180, step: 2, unit: "pt", digits: 0,
            defaultValue: .double(74), get: getD(\.notifyHeight), set: setD(\.notifyHeight)),

        // ---------------- 外观 ----------------
        SettingDefinition(key: "backgroundColor", label: "卡片背景色", kind: .color, group: "外观",
            note: "只改色相，不透明度用下面那一项",
            defaultValue: .rgb(0.05, 0.05, 0.07), get: getRGB(\.backgroundColor), set: setRGB(\.backgroundColor)),
        SettingDefinition(key: "backgroundAlpha", label: "背景不透明度", kind: .slider, group: "外观",
            min: 0.3, max: 1.0, step: 0.01, digits: 2,
            defaultValue: .double(0.96), get: getD(\.backgroundAlpha), set: setD(\.backgroundAlpha)),
        SettingDefinition(key: "accentColor", label: "主题色", kind: .color, group: "外观",
            note: "空闲脉冲圆点、装饰色",
            defaultValue: .rgb(0.29, 0.62, 1.0), get: getRGB(\.accentColor), set: setRGB(\.accentColor)),
        SettingDefinition(key: "qoderTint", label: "Qoder 主题色", kind: .color, group: "外观",
            defaultValue: .rgb(0.58, 0.45, 0.82), get: getRGB(\.qoderTint), set: setRGB(\.qoderTint)),
        SettingDefinition(key: "opencodeTint", label: "OpenCode 主题色", kind: .color, group: "外观",
            defaultValue: .rgb(0.06, 0.73, 0.51), get: getRGB(\.opencodeTint), set: setRGB(\.opencodeTint)),
        SettingDefinition(key: "radiusExpanded", label: "卡片圆角", kind: .slider, group: "外观",
            min: 8, max: 34, step: 1, unit: "pt", digits: 0,
            defaultValue: .double(22), get: getD(\.radiusExpanded), set: setD(\.radiusExpanded)),
        SettingDefinition(key: "radiusBubble", label: "气泡圆角", kind: .slider, group: "外观",
            min: 6, max: 22, step: 1, unit: "pt", digits: 0,
            defaultValue: .double(13), get: getD(\.radiusBubble), set: setD(\.radiusBubble)),

        // ---------------- 动画 ----------------
        SettingDefinition(key: "motionGrowBounce", label: "弹簧回弹（展开）", kind: .slider, group: "动画",
            min: 0, max: 0.6, step: 0.05, digits: 2,
            note: "0 = 不回弹；越大越过目标后回摆越明显", advanced: true,
            defaultValue: .double(0.25), get: getD(\.motionGrowBounce), set: setD(\.motionGrowBounce)),
        SettingDefinition(key: "reduceMotion", label: "减弱动态效果", kind: .toggle, group: "动画",
            note: "开启后取消回弹与过冲；关掉会强制保留动画",
            defaultValue: .bool(false),
            get: { .bool(Settings.shared.reduceMotionResolved) },
            set: { if case .bool(let v) = $0 { Settings.shared.reduceMotion = v ? "on" : "off"; Settings.shared.markChanged() } }),
        SettingDefinition(key: "animationSpeed", label: "弹窗动画速度", kind: .slider, group: "动画",
            min: 0.4, max: 3.0, step: 0.1, unit: "×", digits: 2,
            note: "展开 / 收起时长同时按这个倍率缩放",
            defaultValue: .double(1.0), get: getD(\.animationSpeed), set: setD(\.animationSpeed)),
        SettingDefinition(key: "animationFps", label: "动画帧率上限", kind: .choice, group: "动画",
            choices: Settings.fpsChoices,
            note: "刘海屏选自动可跑满 120Hz；显示异常时降到 60", advanced: true,
            defaultValue: .string("0"), get: getIS(\.animationFps), set: setIS(\.animationFps)),
        SettingDefinition(key: "hoverExpandDelay", label: "悬停多久后展开", kind: .slider, group: "动画",
            min: 0, max: 1.0, step: 0.02, unit: "秒", digits: 2,
            defaultValue: .double(0.18), get: getD(\.hoverExpandDelay), set: setD(\.hoverExpandDelay)),
        SettingDefinition(key: "hoverCollapseDelay", label: "移开多久后收起", kind: .slider, group: "动画",
            min: 0.1, max: 2.0, step: 0.05, unit: "秒", digits: 2,
            defaultValue: .double(0.35), get: getD(\.hoverCollapseDelay), set: setD(\.hoverCollapseDelay)),
        SettingDefinition(key: "notifyBannerDuration", label: "通知停留时长", kind: .slider, group: "动画",
            min: 2, max: 30, step: 1, unit: "秒", digits: 0,
            note: "回复完成 / 权限提醒 / 外部推送都按它自动收起；卡片不受影响",
            keywords: ["时长", "通知", "duration", "seconds"],
            defaultValue: .double(5), get: getD(\.notifyBannerDuration), set: setD(\.notifyBannerDuration)),
        SettingDefinition(key: "historyDuration", label: "最近列表停留", kind: .slider, group: "动画",
            min: 3, max: 30, step: 1, unit: "秒", digits: 0,
            note: "空闲点气泡展开的那份列表；鼠标移开仍按「移开多久后收起」收",
            keywords: ["时长", "历史", "列表", "duration"],
            defaultValue: .double(8), get: getD(\.historyDuration), set: setD(\.historyDuration)),
        SettingDefinition(key: "idlePulsePeriod", label: "空闲脉冲周期", kind: .slider, group: "动画",
            min: 0.6, max: 6.0, step: 0.2, unit: "秒", digits: 1,
            note: "收起态圆点呼吸一次的时长",
            defaultValue: .double(2.4), get: getD(\.idlePulsePeriod), set: setD(\.idlePulsePeriod)),

        // ---------------- 声音与触感 ----------------
        SettingDefinition(key: "notifySound", label: "提示音", kind: .choice, group: "声音与触感", section: "提示音",
            choices: Settings.soundChoices,
            note: "新卡片上屏 / 作答时播放，可用右侧按钮试听",
            defaultValue: .string("Ping"), get: getS(\.notifySound), set: setS(\.notifySound)),
        SettingDefinition(key: "notifyVolume", label: "提示音音量", kind: .slider, group: "声音与触感", section: "提示音",
            min: 0, max: 1.0, step: 0.05, digits: 2,
            note: "与系统输出音量相乘；听不清先调大系统音量",
            enabledBy: ["notifySound"], enabledWhen: soundOn,
            defaultValue: .double(1.0), get: getD(\.notifyVolume), set: setD(\.notifyVolume)),
        SettingDefinition(key: "soundOnArrive", label: "新通知上屏时响", kind: .toggle, group: "声音与触感", section: "提示音",
            note: "提问 / 权限提醒、回复完成与外部推送都算“新通知”",
            defaultValue: .bool(true), get: getB(\.soundOnArrive), set: setB(\.soundOnArrive)),
        SettingDefinition(key: "soundOnAnswer", label: "作答后响", kind: .toggle, group: "声音与触感", section: "提示音",
            note: "默认关：提交 / 确认是按钮操作，确认感交给「作答后震动」",
            defaultValue: .bool(false), get: getB(\.soundOnAnswer), set: setB(\.soundOnAnswer)),
        SettingDefinition(key: "hapticOnArrive", label: "新通知上屏时震动", kind: .toggle, group: "声音与触感", section: "震动",
            note: "需要触控板机型；不支持时自动忽略",
            defaultValue: .bool(true), get: getB(\.hapticOnArrive), set: setB(\.hapticOnArrive)),
        SettingDefinition(key: "hapticOnAnswer", label: "作答后震动", kind: .toggle, group: "声音与触感", section: "震动",
            defaultValue: .bool(false), get: getB(\.hapticOnAnswer), set: setB(\.hapticOnAnswer)),
        SettingDefinition(key: "hapticPattern", label: "震动样式", kind: .choice, group: "声音与触感", section: "震动",
            choices: Settings.hapticChoices,
            enabledBy: ["hapticOnArrive", "hapticOnAnswer"], enabledWhen: hapticOn, advanced: true,
            defaultValue: .string("generic"), get: getS(\.hapticPattern), set: setS(\.hapticPattern)),

        // ---------------- 行为 ----------------
        SettingDefinition(key: "pinByDefault", label: "卡片默认固定展示", kind: .toggle, group: "行为",
            note: "关闭后新卡片只更新气泡计数，悬停才展开",
            defaultValue: .bool(true), get: getB(\.pinByDefault), set: setB(\.pinByDefault)),
        SettingDefinition(key: "clickGuard", label: "防误触窗口", kind: .slider, group: "行为",
            min: 0, max: 2.0, step: 0.05, unit: "秒", digits: 2,
            note: "卡片上屏后这段时间内忽略点击，0 = 关闭",
            enabledBy: ["permissionEnabled", "questionEnabled"], enabledWhen: anyCardOn, advanced: true,
            defaultValue: .double(0.5), get: getD(\.clickGuard), set: setD(\.clickGuard)),
        SettingDefinition(key: "manualCollapseHold", label: "手动收起让位时长", kind: .slider, group: "行为",
            min: 0, max: 30.0, step: 1.0, unit: "秒", digits: 0,
            note: "固定模式下手动收起后安静多久才允许自己再弹回来",
            defaultValue: .double(3), get: getD(\.manualCollapseHold), set: setD(\.manualCollapseHold)),
        SettingDefinition(key: "questionHold", label: "问题卡片常驻", kind: .toggle, group: "行为",
            note: "关闭后按「卡片等待上限」倒计时，超时写 -1",
            enabledBy: ["questionEnabled"], enabledWhen: questionOn,
            defaultValue: .bool(true), get: getB(\.questionHold), set: setB(\.questionHold)),
        SettingDefinition(key: "permissionHold", label: "权限卡片常驻", kind: .toggle, group: "行为",
            note: "仅 OpenCode：Qoder 的权限申请已不弹卡片，只弹提醒",
            enabledBy: ["permissionEnabled"], enabledWhen: permissionOn,
            defaultValue: .bool(true), get: getB(\.permissionHold), set: setB(\.permissionHold)),

        // ---------------- 超时与排队 ----------------
        SettingDefinition(key: "agentWaitLimit", label: "卡片等待上限", kind: .slider, group: "超时与排队",
            min: 60, max: 600, step: 30, unit: "秒", digits: 0,
            note: "卡片必须先于 Hook / Plugin 到期，所以 Hook 时限自动取本值 + 60 秒",
            needsReinstall: true,
            defaultValue: .int(600), get: getI(\.agentWaitLimit), set: setI(\.agentWaitLimit)),
        SettingDefinition(key: "questionQueueLimit", label: "提问排队上限", kind: .slider, group: "超时与排队",
            min: 1, max: 20, step: 1, unit: "组", digits: 0,
            note: "超出挤掉最旧的一组，那组回落到平台弹窗",
            enabledBy: ["questionEnabled"], enabledWhen: questionOn, advanced: true,
            defaultValue: .int(8), get: getI(\.questionQueueLimit), set: setI(\.questionQueueLimit)),
        SettingDefinition(key: "permissionQueueLimit", label: "权限排队上限", kind: .slider, group: "超时与排队",
            min: 1, max: 20, step: 1, unit: "项", digits: 0,
            note: "仅 OpenCode：同时能排队的权限卡片数",
            enabledBy: ["permissionEnabled"], enabledWhen: permissionOn, advanced: true,
            defaultValue: .int(8), get: getI(\.permissionQueueLimit), set: setI(\.permissionQueueLimit)),
        SettingDefinition(key: "sweepInterval", label: "兜底巡检周期", kind: .slider, group: "超时与排队",
            min: 5, max: 120, step: 5, unit: "秒", digits: 0, advanced: true,
            defaultValue: .int(15), get: getI(\.sweepInterval), set: setI(\.sweepInterval)),
        SettingDefinition(key: "sweepGrace", label: "兜底巡检宽限", kind: .slider, group: "超时与排队",
            min: 10, max: 300, step: 5, unit: "秒", digits: 0,
            note: "挂了「Hook 时限 + 本宽限」仍没人等的卡片会被收掉", advanced: true,
            defaultValue: .int(45), get: getI(\.sweepGrace), set: setI(\.sweepGrace)),
    ]

    static func byKey(_ key: String) -> SettingDefinition? {
        all.first { $0.key == key }
    }

    static func settings(in group: String) -> [SettingDefinition] {
        all.filter { $0.group == group }
    }
}
