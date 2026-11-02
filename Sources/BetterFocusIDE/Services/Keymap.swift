// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// Keyboard → action mapping (mirrors the Python `keymap.py`). Pure logic: it
/// takes a normalized key, modifier bits, and a state snapshot, and returns the
/// **same action a mouse click would produce** — so keyboard and pointer share
/// one decision path and can never drift apart ("click allows, key does
/// something else").
///
/// Four layers of protection, each matched to the click path:
/// - `editing`  — a text field has focus: bare keys belong to typing, not the island.
/// - `guarded`  — the anti-mistouch window right after a card appears: ignore, so
///                a hand resting where "allow" will appear can't approve a `rm -rf`.
/// - `closing`  — the card is fading out (already answered / dismissed): can't change it.
/// - `visible`  — the card is tucked in the bubble: the keyboard must not answer an
///                invisible card.
enum Keymap {
    enum Kind { case none, question, permission }

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

    struct Modifiers: OptionSet {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift   = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let option  = Modifiers(rawValue: 1 << 3)
    }

    // Named keys (arrows / return / esc arrive as control chars or private-area
    // code points; folding them to names keeps the mapping table readable).
    static let escape = "escape"
    static let returnKey = "return"
    static let tabKey = "tab"
    static let leftKey = "left"
    static let rightKey = "right"

    // Layout-independent macOS key codes.
    private static let keyCodeNames: [UInt16: String] = [
        53: escape, 36: returnKey, 76: returnKey, 48: tabKey, 123: leftKey, 124: rightKey,
    ]
    private static let charNames: [String: String] = [
        "\u{1b}": escape, "\r": returnKey, "\u{03}": returnKey, "\n": returnKey,
        "\t": tabKey, "\u{F702}": leftKey, "\u{F703}": rightKey,
    ]
    // Digit key codes: an IME can rewrite `characters`, so fall back to the code.
    private static let digitCodes: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    // Permission: letters for people reading the text, digits for people counting buttons.
    static let permissionKeys: [String: PermissionDecisionValue] = [
        "y": .allowOnce, "1": .allowOnce,
        "a": .allowAlways, "2": .allowAlways,
        "n": .reject, "3": .reject,
    ]

    static let maxDigitOptions = 9

    // MARK: - Event normalization

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var m = Modifiers()
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        return m
    }

    /// Fold a key event into a named key or a lowercased character; nil if unrecognized.
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

    // MARK: - Resolve

    /// key + modifiers + context → action; nil means "not ours" (hand it back to the system).
    static func resolve(key rawKey: String?, modifiers: Modifiers, context: Context) -> Action? {
        guard let rawKey else { return nil }
        let key = rawKey.lowercased()

        // ⌘ combos first: card-independent, and honored even while editing (text
        // fields don't consume these two).
        if modifiers.contains(.command) {
            if key == "," && modifiers.isDisjoint(with: [.shift, .option, .control]) {
                return .settings
            }
            if key == "p" && modifiers.contains(.shift) {
                return .togglePin
            }
            return nil // ⌘C / ⌘V / ⌘Q … belong to the system
        }
        if modifiers.contains(.control) || modifiers.contains(.option) {
            return nil // Ctrl/Option combos are IME + system territory
        }

        if context.editing { return nil }          // typing wins over the island
        if context.guarded || context.closing { return nil }

        if key == escape {
            // Only claim Esc when there's a card to collapse; otherwise let AppKit
            // handle it so we don't swallow a stray Esc.
            return context.kind != .none ? .collapse : nil
        }
        if !context.visible { return nil }

        switch context.kind {
        case .question: return questionAction(key, context)
        case .permission: return permissionAction(key)
        case .none: return nil
        }
    }

    private static func questionAction(_ key: String, _ ctx: Context) -> Action? {
        if ctx.answered { return nil } // answered: only waiting to collapse, no re-answer
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

    private static func permissionAction(_ key: String) -> Action? {
        // Return / Enter is deliberately not accepted: a high-risk action needs a
        // deliberate Y/A/N, not an accidental keystroke.
        guard let decision = permissionKeys[key] else { return nil }
        return .decide(decision)
    }
}
