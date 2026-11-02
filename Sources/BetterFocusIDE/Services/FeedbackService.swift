// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// Plays notification sounds and trackpad haptics. Reads Settings at call
/// time so a change takes effect immediately. Failures are logged, never
/// silent, so "I turned it on but nothing happens" has a paper trail.
enum FeedbackService {
    /// The currently playing sound; stopped before the next one so two
    /// chimes never overlap.
    private static var current: NSSound?

    /// Play a system sound; empty name = no sound. Returns whether it played.
    @discardableResult
    static func playSound(_ nameOverride: String? = nil) -> Bool {
        let settings = Settings.shared
        let name = (nameOverride ?? settings.notifySound).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            Log.debug("提示音未选，本次不播放", topic: "feedback")
            return false
        }
        let volume = max(0.0, min(1.0, settings.notifyVolume))
        // Deliberately not caching the NSSound instance: stopping then playing
        // the same instance is dropped by the system (first chime sounds, the
        // rest are silent). The .aiff file itself is cached by macOS.
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

    static func stopSound() {
        current?.stop()
        current = nil
    }

    /// Give one trackpad haptic. Returns whether the API was invoked.
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

    /// A new card appeared on screen.
    static func onArrive() {
        let s = Settings.shared
        if s.soundOnArrive { playSound() }
        if s.hapticOnArrive { buzz() }
    }

    /// The user finished answering / decided.
    static func onAnswer() {
        let s = Settings.shared
        if s.soundOnAnswer { playSound() }
        if s.hapticOnAnswer { buzz() }
    }
}
