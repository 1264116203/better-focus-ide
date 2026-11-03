// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 在窗口中展示自检（Doctor）报告，并提供重新运行按钮。
struct DoctorView: View {
    /// 检查结果列表，初次进入即运行一遍。
    @State private var checks: [DoctorCheck] = Doctor.run()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏 + 汇总状态（全部通过 / N 项待处理）。
            HStack {
                Text("自检 (Doctor)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(Doctor.failedCount(checks) == 0
                     ? "全部通过"
                     : "\(Doctor.failedCount(checks)) 项待处理")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Doctor.failedCount(checks) == 0 ? .green : .orange)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                        row(check)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("重新自检") { checks = Doctor.run() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 420)
    }

    /// 单条检查行：✔/✗ 图标 + 标签 + 详情，失败时附一行修复建议。
    private func row(_ check: DoctorCheck) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Text(check.ok ? "✔" : "✗")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(check.ok ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.label)
                        .font(.system(size: 12, weight: .semibold))
                    Text(check.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let hint = check.hint {
                Text("修复建议：\(hint)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.leading, 21)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
/// Xcode Canvas 预览：直接渲染自检面板（Doctor.run() 会在预览构建时执行）。
struct DoctorView_Previews: PreviewProvider {
    static var previews: some View {
        DoctorView()
            .preferredColorScheme(.dark)
    }
}
#endif
