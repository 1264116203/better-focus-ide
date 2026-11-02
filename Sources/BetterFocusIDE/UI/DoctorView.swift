// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// Shows the doctor self-check report in a window, with a re-run button.
struct DoctorView: View {
    @State private var checks: [DoctorCheck] = Doctor.run()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
