// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// The banner shown when an agent finishes a reply. Clicking it jumps back to
/// the IDE that produced the reply (when jump is enabled).
struct NotchNoticeView: View {
    let notice: TurnNotice
    var pinned = false
    var onTogglePin: () -> Void = {}
    let onTap: () -> Void
    /// When set, triggers the bell swing animation on the provider badge.
    var bellSwingStart: Date?

    @State private var bellAngle: Double = 0
    @State private var bellScale: CGFloat = 1.0

    private var tint: Color {
        AgentProvider(rawValue: notice.provider)?.tint ?? Color(red: 0.29, green: 0.62, blue: 1.0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    // Provider badge with bell swing animation
                    Text(String(notice.providerName.prefix(1)))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.9),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .rotationEffect(.degrees(bellAngle))
                        .scaleEffect(bellScale)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Text(notice.body)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        if !notice.project.isEmpty {
                            Text(notice.project)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if notice.jumpEnabled {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Pin toggle: hold the banner open instead of letting it retract.
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .foregroundStyle(pinned ? tint : Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 8)
            .help(pinned ? "取消固定（自动收起）" : "固定（不自动收起）")
        }
        .onAppear { startBellSwing() }
        .onChange(of: bellSwingStart) { startBellSwing() }
    }
    
    /// Bell swing: 4 sine cycles over 1.2s, amplitude 20° decaying to 0,
    /// scale from 1.35 decaying to 1.0 (Python BELL_SWING_*).
    private func startBellSwing() {
        // Animate scale up then settle.
        bellScale = 1.35
        bellAngle = 20
        withAnimation(.easeOut(duration: 1.2)) {
            bellAngle = 0
            bellScale = 1.0
        }
    }
}
