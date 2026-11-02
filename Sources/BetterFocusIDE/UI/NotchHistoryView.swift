// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// The recent-notifications panel: one row per entry, tapping a row jumps back
/// to the app that produced it. Opened by clicking the idle island.
///
/// Layout mirrors the Python reference (`history_card.py`): a two-layer row
/// with the content title/body on the left and a *fixed-width* result + source
/// · time column on the right, fronted by a tinted app badge. The title band
/// takes whatever width the 104pt meta column leaves and truncates — a row is
/// only ~34pt tall, and letting both ends fight for the same width would clip
/// the one line you actually want to read.
struct NotchHistoryView: View {
    @ObservedObject var controller: HistoryController
    var onRowTap: (HistoryEntry) -> Void

    // Reference metrics (config.HISTORY_*). Horizontal padding must reach the
    // island silhouette's shoulder (NotchLayout.shoulder = 14) — the black mask
    // clips at that edge, so a 12pt inset shaved 2pt off every row. Vertical
    // stays at the reference 12 to match the window-height formula in
    // NotchService.showHistory (12*2 + header + rows).
    private let horizontalInset: CGFloat = 14
    private let verticalInset: CGFloat = 12
    private let headerHeight: CGFloat = 20
    private let rowHeight: CGFloat = 34
    private let rowGap: CGFloat = 2
    private let badgeSize: CGFloat = 22
    private let metaWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            header
            if controller.entries.isEmpty {
                emptyRow
            } else {
                ForEach(controller.entries) { entry in
                    row(entry)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("最近通知")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 4)
            Text("\(controller.entries.count) 条")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(height: headerHeight)
    }

    private var emptyRow: some View {
        Text("暂无通知")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button { onRowTap(entry) } label: {
            GeometryReader { geo in
                // Explicit widths mirroring the reference's rect math, so the
                // greedy title and the fixed meta column never fight for the
                // same pixels: pad + badge + gaps + title + meta == row width.
                let leadingPad: CGFloat = 5
                let trailingPad: CGFloat = 8
                let gap: CGFloat = 9
                let titleW = max(40, geo.size.width - leadingPad - trailingPad
                                 - badgeSize - gap * 2 - metaWidth)
                HStack(spacing: gap) {
                    Text(entry.badgeText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Color(red: entry.tintRGB.red, green: entry.tintRGB.green,
                                          blue: entry.tintRGB.blue).opacity(0.9),
                                    in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 1, blue: 1, opacity: 0.92))
                            .lineLimit(1)
                        if !entry.body.isEmpty {
                            Text(entry.body)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.80, green: 0.82, blue: 0.87, opacity: 0.95))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: titleW, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 1) {
                        if !entry.state.isEmpty {
                            Text(entry.state)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.90, green: 0.92, blue: 0.96))
                                .lineLimit(1)
                        }
                        Text(metaText(entry))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.72, green: 0.74, blue: 0.78))
                            .lineLimit(1)
                    }
                    .frame(width: metaWidth, alignment: .trailing)
                }
                .padding(.leading, leadingPad)
                .padding(.trailing, trailingPad)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Project name leads (the badge already carries the app identity); fall
    /// back to the source, then a generic label — matching the reference.
    private func metaText(_ entry: HistoryEntry) -> String {
        let base = entry.project.isEmpty ? (entry.source.isEmpty ? "通知" : entry.source) : entry.project
        return entry.clockText.isEmpty ? base : "\(base) · \(entry.clockText)"
    }
}
