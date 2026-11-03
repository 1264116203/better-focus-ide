// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// 播放提示音与触控板触感反馈。
///
/// 在调用时读取 Settings，因此改动立即生效。失败一律记录日志、绝不静默，
/// 让"我明明开了却没反应"留下可追查的线索。
enum FeedbackService {
    /// 当前正在播放的声音；播放下一个前先停掉它，避免两声提示重叠。
    private static var current: NSSound?

    /// 播放一个系统提示音；名字为空表示不出声。返回是否实际播放。
    @discardableResult
    static func playSound(_ nameOverride: String? = nil) -> Bool {
        let settings = Settings.shared
        let name = (nameOverride ?? settings.notifySound).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            Log.debug("提示音未选，本次不播放", topic: "feedback")
            return false
        }
        let volume = max(0.0, min(1.0, settings.notifyVolume))
        // 故意不缓存 NSSound 实例：对同一实例先 stop 再 play 会被系统丢弃
        // （第一声有、后续都哑）。.aiff 文件本身由 macOS 缓存，无需我们操心。
        guard let sound = NSSound(named: name) else {
            Log.warning("系统里没有提示音 \(name)", topic: "feedback")
            return false
        }
        current?.stop()
        sound.volume = Float(volume)
        current = sound
        if sound.play() { return true }
        Log.warning("提示音 \(name) 播放被系统拒绝（音量 \(volume)）", topic: "feedback")
        return false
    }

    /// 停止当前声音并释放引用。
    static func stopSound() {
        current?.stop()
        current = nil
    }

    /// 给一次触控板触感反馈。返回 API 是否被调用。
    @discardableResult
    static func buzz() -> Bool {
        let performer = NSHapticFeedbackManager.defaultPerformer
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch Settings.shared.hapticPattern {
        case "levelChange": pattern = .levelChange
        default: pattern = .generic
        }
        performer.perform(pattern, performanceTime: .now)
        return true
    }

    /// 新卡片上屏时的反馈。
    static func onArrive() {
        let s = Settings.shared
        if s.soundOnArrive { playSound() }
        if s.hapticOnArrive { buzz() }
    }

    /// 用户完成作答 / 做出决策时的反馈。
    static func onAnswer() {
        let s = Settings.shared
        if s.soundOnAnswer { playSound() }
        if s.hapticOnAnswer { buzz() }
    }
}
