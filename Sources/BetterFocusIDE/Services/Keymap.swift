// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// 键盘 → 动作映射（对齐 Python 的 `keymap.py`）。纯逻辑：接收归一化后的按键、
/// 修饰键位、状态快照，返回**鼠标点击本应产生的同一个动作**——于是键盘与指针共用
/// 一条决策路径，永远不会分叉（"点击是允许、按键却做了别的事"）。
///
/// 四层防护，每层都与点击路径一一对应：
/// - `editing`  —— 文本框有焦点：裸键属于打字，不属于灵动岛。
/// - `guarded`  —— 卡片刚出现后的防误触窗口：忽略，免得手正搭在"允许"即将出现的位置
///                就误批了一条 `rm -rf`。
/// - `closing`  —— 卡片正在淡出（已应答/已关闭）：不能再改它。
/// - `visible`  —— 卡片缩在气泡里：键盘绝不能去应答一张看不见的卡片。
enum Keymap {
    /// 当前活动卡片种类。
    enum Kind { case none, question, permission }

    /// 按键解析出的动作。
    enum Action: Equatable {
        case option(Int)
        case nav(Int)
        case other
        case send
        case decide(PermissionDecisionValue)
        case collapse
        case settings
        case togglePin
    }

    /// 决策所需的上下文状态快照。
    struct Context {
        var kind: Kind = .none
        var visible = false
        var editing = false
        var guarded = false
        var closing = false
        var answered = false
        var optionCount = 0
        var index = 0
        var questionCount = 1
    }

    /// 修饰键集合（与 AppKit 的 modifierFlags 解耦，便于纯逻辑测试）。
    struct Modifiers: OptionSet {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift   = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let option  = Modifiers(rawValue: 1 << 3)
    }

    // 具名键（方向键 / 回车 / esc 到达时是控制字符或私用区码点；折叠成名字
    // 能让映射表保持可读）。
    static let escape = "escape"
    static let returnKey = "return"
    static let tabKey = "tab"
    static let leftKey = "left"
    static let rightKey = "right"

    // 与键盘布局无关的 macOS keyCode 映射。
    private static let keyCodeNames: [UInt16: String] = [
        53: escape, 36: returnKey, 76: returnKey, 48: tabKey, 123: leftKey, 124: rightKey,
    ]
    // 字符到具名键的映射（控制字符形态）。
    private static let charNames: [String: String] = [
        "\u{1b}": escape, "\r": returnKey, "\u{03}": returnKey, "\n": returnKey,
        "\t": tabKey, "\u{F702}": leftKey, "\u{F703}": rightKey,
    ]
    // 数字键 keyCode：输入法可能改写 `characters`，故回退到 keyCode。
    private static let digitCodes: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    // 权限：给读文字的人用字母，给数按钮的人用数字。
    static let permissionKeys: [String: PermissionDecisionValue] = [
        "y": .allowOnce, "1": .allowOnce,
        "a": .allowAlways, "2": .allowAlways,
        "n": .reject, "3": .reject,
    ]

    /// 数字键最多可选的前 N 个选项（1–9）。
    static let maxDigitOptions = 9

    // MARK: - 事件归一化

    /// 把 AppKit 的 modifierFlags 转成内部 Modifiers 集合。
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var m = Modifiers()
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        return m
    }

    /// 把按键事件折叠成具名键或小写字符；无法识别返回 nil。
    static func key(from event: NSEvent) -> String? {
        let code = event.keyCode
        if let named = keyCodeNames[code] { return named }
        if let chars = event.charactersIgnoringModifiers {
            if let named = charNames[chars] { return named }
            if chars.count == 1, let scalar = chars.unicodeScalars.first,
               scalar.value >= 32, scalar.value != 127 {
                return chars.lowercased()
            }
        }
        return digitCodes[code]
    }

    // MARK: - 解析

    /// 按键 + 修饰键 + 上下文 → 动作；返回 nil 表示"不归我们管"（交还系统）。
    static func resolve(key rawKey: String?, modifiers: Modifiers, context: Context) -> Action? {
        guard let rawKey else { return nil }
        let key = rawKey.lowercased()

        // 先处理 ⌘ 组合：与卡片无关，且即便在编辑态也生效（文本框不消费这两个）。
        if modifiers.contains(.command) {
            if key == "," && modifiers.isDisjoint(with: [.shift, .option, .control]) {
                return .settings
            }
            if key == "p" && modifiers.contains(.shift) {
                return .togglePin
            }
            return nil // ⌘C / ⌘V / ⌘Q … 归系统
        }
        if modifiers.contains(.control) || modifiers.contains(.option) {
            return nil // Ctrl/Option 组合是输入法 + 系统的领地
        }

        if context.editing { return nil }          // 打字优先于灵动岛
        if context.guarded || context.closing { return nil }

        if key == escape {
            // 只有确实有卡片可收起时才认领 Esc；否则交给 AppKit，免得吞掉一次游离的 Esc。
            return context.kind != .none ? .collapse : nil
        }
        if !context.visible { return nil }

        switch context.kind {
        case .question: return questionAction(key, context)
        case .permission: return permissionAction(key)
        case .none: return nil
        }
    }

    /// 问题卡片的按键解析：数字选项、左右翻页、回车发送、tab 进入"其他…"。
    private static func questionAction(_ key: String, _ ctx: Context) -> Action? {
        if ctx.answered { return nil } // 已应答：只等收起，不能再改答案
        if key.count == 1, let digit = key.first, digit.isNumber, digit != "0",
           let value = digit.wholeNumberValue {
            let index = value - 1
            return index < min(ctx.optionCount, maxDigitOptions) ? .option(index) : nil
        }
        switch key {
        case leftKey: return ctx.index > 0 ? .nav(ctx.index - 1) : nil
        case rightKey: return ctx.index + 1 < ctx.questionCount ? .nav(ctx.index + 1) : nil
        case returnKey: return .send
        case tabKey: return .other
        default: return nil
        }
    }

    /// 权限卡片的按键解析。
    private static func permissionAction(_ key: String) -> Action? {
        // 故意不接受 Return/Enter：高风险动作需要一个刻意的 Y/A/N，而不是一次误触按键。
        guard let decision = permissionKeys[key] else { return nil }
        return .decide(decision)
    }
}
