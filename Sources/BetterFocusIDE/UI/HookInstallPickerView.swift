// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 右键「安装 Hook」弹出的勾选面板。只列出本机已安装的受支持宿主。
struct HookInstallPickerView: View {
    @ObservedObject var model: HookInstallPickerModel
    var onInstall: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("安装 Hook / Plugin")
                .font(.system(size: 15, weight: .semibold))
            Text("检测到这些受支持的 IDE。默认全部勾选，取消勾选的不会安装。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($model.items) { $item in
                        Toggle(item.label, isOn: $item.selected)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 13))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("安装", action: onInstall)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
