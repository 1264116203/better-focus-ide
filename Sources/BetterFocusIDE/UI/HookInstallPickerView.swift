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
            Text("下面是这台 Mac 上已安装、而且受支持的 IDE，默认全部勾选。取消勾选的不会安装。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($model.items) { $item in
                        HookInstallRow(item: $item)
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
        .frame(width: 420)
    }
}

/// 勾选行：名称下面一行说明这个 IDE 接到岛上之后的表现。
struct HookInstallRow: View {
    @Binding var item: HookInstallPickerModel.Item

    var body: some View {
        Toggle(isOn: $item.selected) {
            HStack(alignment: .top, spacing: 8) {
                IDEIconProvider.badgeView(
                    hostName: item.label,
                    fallbackText: String(item.label.prefix(1)).uppercased(),
                    tint: .white.opacity(0.85),
                    size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 13))
                    Text(item.installed ? item.hint : "未安装。\(item.hint)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!item.installed)
    }
}
