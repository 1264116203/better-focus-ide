// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 设置里的权限页：列出自动化目标的授权状态，并跳到系统设置去改。
struct PermissionStatusView: View {
    @StateObject private var report = AutomationPermissionReport()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("权限")
                    .font(.system(size: 13, weight: .semibold))
                Text("点击通知跳回 IDE、把浏览器里已经打开的标签页带到前台，需要「自动化」权限。系统按目标应用分别授权。尚未询问的项会在第一次跳转时弹出授权；已拒绝的项要在系统设置里打开。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("在系统设置中授权") {
                        AutomationPermission.openSettings()
                    }
                    .controlSize(.small)
                    Button(report.checking ? "正在检查…" : "重新检查") {
                        report.refresh()
                    }
                    .controlSize(.small)
                    .disabled(report.checking)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AutomationPermission.Kind.allCases, id: \.self) { kind in
                        section(kind)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { report.refresh() }
    }

    @ViewBuilder
    private func section(_ kind: AutomationPermission.Kind) -> some View {
        let rows = report.rows.filter { $0.target.kind == kind }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind.rawValue)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                ForEach(rows) { row in
                    targetRow(row)
                }
            }
        }
    }

    private func targetRow(_ row: AutomationPermission.Row) -> some View {
        HStack(spacing: 8) {
            Text(row.target.name)
                .font(.system(size: 11.5))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(row.grant.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color(row.grant))
        }
        .frame(height: 22)
    }

    private func color(_ grant: AutomationPermission.Grant) -> Color {
        switch grant {
        case .allowed: return .green
        case .denied: return .red
        case .notDetermined, .notRunning, .unknown: return .secondary
        }
    }
}

extension AutomationPermission.Kind: CaseIterable {
    static var allCases: [AutomationPermission.Kind] { [.system, .ide, .terminal, .browser] }
}
