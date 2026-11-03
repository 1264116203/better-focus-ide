// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// Permission card shown on the island when a tool call requires approval.
struct NotchPermissionView: View {
    @ObservedObject var controller: PermissionController
    var pinned = false
    var onTogglePin: () -> Void = {}

    private var request: PermissionRequest? { controller.request }

    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    var body: some View {
        if let req = request {
            VStack(alignment: .leading, spacing: 8) {
                header(req)
                bodyText(req)
                if !req.detail.isEmpty {
                    detailBlock(req)
                }
                buttonsView(req)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Header

    private func header(_ req: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            Text(String(req.provider.displayName.prefix(1)))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(req.provider.tint.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 4))
                .layoutPriority(1)
            Text("\(req.provider.displayName) · \(req.title)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 0)
            if controller.pendingCount > 0 {
                Text("+\(controller.pendingCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.12),
                                in: Capsule())
                    .layoutPriority(1)
            }
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .foregroundStyle(pinned ? AnyShapeStyle(req.provider.tint)
                                     : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help(pinned ? "取消固定（按需收起）" : "固定（保持展开）")
        }
    }

    // MARK: - Body

    private func bodyText(_ req: PermissionRequest) -> some View {
        let agent = req.agent.isEmpty ? "" : "（\(req.agent)）"
        return Text("Agent\(agent) 请求执行「\(req.title)」，是否允许？")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Detail

    private func detailBlock(_ req: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(req.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Buttons

    private func buttonsView(_ req: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            permissionButton("允许", decision: .allowOnce,
                             color: req.provider.tint, req: req)
            permissionButton("始终允许", decision: .allowAlways,
                             color: req.provider.tint.opacity(0.7), req: req)
            permissionButton("拒绝", decision: .reject,
                             color: Color(red: 0.9, green: 0.3, blue: 0.3), req: req)
        }
    }

    private func permissionButton(_ label: String, decision: PermissionDecisionValue,
                                   color: Color, req: PermissionRequest) -> some View {
        let chosen = controller.choice == decision
        return Button {
            controller.decide(decision)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(chosen ? color : color.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(controller.choice != nil)
    }
}
