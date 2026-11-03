// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 最近通知历史面板视图
///
/// 展示最近 N 条通知记录（问题、权限请求、轮次完成），点击行可跳转回对应的 IDE。
/// 通过点击空闲状态的灵动岛或菜单栏"最近通知"打开。
///
/// ## 布局结构（对齐 Python 参考实现 `history_card.py`）
///
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 最近通知                              3 条   │  ← header (20pt)
/// ├─────────────────────────────────────────────┤
/// │ [Q] 标题文字              状态               │  ← row (40pt)
/// │     答：回答文字          来源 · 时间         │
/// │                                             │
/// │ [Q] 标题文字              状态               │  ← gap (4pt)
/// │     答：回答文字          来源 · 时间         │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## 设计要点
///
/// - **固定宽度元数据列**：右侧状态+来源时间列固定 104pt，标题占据剩余空间
/// - **无行背景**：原型图无行背景色块，依赖间距区分行
/// - **文字层级**：标题(13pt 半粗) > 状态(10pt) > 回答(10pt 淡灰) > 来源时间(10pt 更淡)
/// - **回答前缀**：body 文本以"答："前缀显示，区分标题和回答内容
struct NotchHistoryView: View {
    /// 历史控制器，提供通知条目数据
    @ObservedObject var controller: HistoryController
    /// 点击行的回调，用于跳转回对应 IDE
    var onRowTap: (HistoryEntry) -> Void

    // MARK: - 布局常量

    /// 水平内边距 (14pt)
    ///
    /// 必须达到灵动岛轮廓的肩部宽度 (NotchLayout.shoulder = 14)，
    /// 因为黑色遮罩在此处裁切，12pt 会裁掉每行 2pt 的内容。
    private let horizontalInset: CGFloat = 14

    /// 垂直内边距 (12pt)
    ///
    /// 与窗口高度公式匹配：NotchService.showHistory 使用 `12*2 + header + rows`
    private let verticalInset: CGFloat = 12

    /// 标题栏高度 (20pt)
    private let headerHeight: CGFloat = 20

    /// 单行高度 (40pt)
    ///
    /// 包含徽章(24pt) + 标题(13pt) + 回答(10pt) + 间距，
    /// 比原型略高以容纳双行文本
    private let rowHeight: CGFloat = 40

    /// 行间距 (4pt)
    private let rowGap: CGFloat = 4

    /// 徽章尺寸 (24pt × 24pt)
    ///
    /// 圆角方形，显示提供者首字母，背景色为提供者主题色
    private let badgeSize: CGFloat = 24

    /// 元数据列宽度 (104pt)
    ///
    /// 固定宽度，包含状态文本和"来源 · 时间"文本，
    /// 过长时截断显示省略号
    private let metaWidth: CGFloat = 104

    // MARK: - 主视图

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

    // MARK: - 标题栏

    /// 标题栏：左侧"最近通知"，右侧条目计数
    ///
    /// 字体 11pt，标题半粗体透明度 0.6，计数透明度 0.4
    private var header: some View {
        HStack(spacing: 0) {
            Text("最近通知")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 30)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            Text("\(controller.entries.count) 条")
                .font(.system(size: 11))
                .padding(.horizontal, 30)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(height: headerHeight)
    }

    // MARK: - 空状态

    /// 无通知时的占位文本
    private var emptyRow: some View {
        Text("暂无通知")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    // MARK: - 通知行

    /// 单条通知行视图
    ///
    /// 布局公式：`leadingPad + badge + gap + title + gap + meta + trailingPad = rowWidth`
    ///
    /// - 左侧：徽章 + 标题/回答文本（弹性宽度，最小 40pt）
    /// - 右侧：状态 + 来源时间（固定 104pt，右对齐）
    ///
    /// 点击整行触发 `onRowTap` 回调
    private func row(_ entry: HistoryEntry) -> some View {
        Button { onRowTap(entry) } label: {
            GeometryReader { geo in
                // 宽度计算：确保标题和元数据列不争夺空间
                // titleW = 总宽 - 内边距 - 徽章 - 间距×2 - 元数据列
                let leadingPad: CGFloat = 5
                let trailingPad: CGFloat = 8
                let gap: CGFloat = 9
                let titleW = max(40, geo.size.width - leadingPad - trailingPad
                                 - badgeSize - gap * 2 - metaWidth)

                HStack(spacing: gap) {
                    // 提供者徽章：圆角方形，显示首字母，主题色背景
                    Text(entry.badgeText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(
                            Color(red: entry.tintRGB.red,
                                  green: entry.tintRGB.green,
                                  blue: entry.tintRGB.blue)
                                .opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )

                    // 左侧内容：标题 + 回答文本
                    VStack(alignment: .leading, spacing: 2) {
                        // 标题：13pt 半粗体，白色高透明度
                        Text(entry.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 1, blue: 1, opacity: 0.92))
                            .lineLimit(1)

                        // 回答文本：10pt，淡灰色，带"答："前缀
                        if !entry.body.isEmpty {
                            Text("答：\(entry.body)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.70, green: 0.72, blue: 0.78, opacity: 0.9))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: titleW, alignment: .leading)

                    // 右侧元数据：状态 + 来源时间
                    VStack(alignment: .trailing, spacing: 2) {
                        // 状态文本：10pt，中灰色（如"已回答"、"回复完成"）
                        if !entry.state.isEmpty {
                            Text(entry.state)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 0.78, green: 0.80, blue: 0.86))
                                .lineLimit(1)
                        }

                        // 来源和时间：10pt，淡灰色（如"Qoder · 11:41"）
                        Text(metaText(entry))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.62, green: 0.64, blue: 0.70))
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
            .contentShape(Rectangle())  // 整行可点击
        }
        .buttonStyle(.plain)
    }

    // MARK: - 辅助方法

    /// 生成元数据文本：`来源 · 时间` 或 `项目名 · 时间`
    ///
    /// 优先级：项目名 > 来源 > "通知"
    /// 时间格式：HH:mm（24 小时制）
    private func metaText(_ entry: HistoryEntry) -> String {
        let base = entry.project.isEmpty
            ? (entry.source.isEmpty ? "通知" : entry.source)
            : entry.project
        return entry.clockText.isEmpty ? base : "\(base) · \(entry.clockText)"
    }
}

// MARK: - Xcode 预览

#if DEBUG
import SwiftUI

/// Xcode 预览：在 Xcode 中打开此文件后，点击右上角 "Resume" 按钮查看实时预览
///
/// 使用方法：
/// 1. 用 Xcode 打开 `Package.swift`
/// 2. 打开本文件
/// 3. 点击编辑器右上角的 "Resume" 按钮（或按 ⌥⌘P）
/// 4. 预览窗口会显示模拟数据的历史面板
struct NotchHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 预览 1：有数据状态
            NotchHistoryView(controller: createMockController(), onRowTap: { _ in })
                .frame(width: 380, height: 200)
                .background(Color.black)
                .previewDisplayName("历史面板 - 有数据")

            // 预览 2：空状态
            NotchHistoryView(controller: HistoryController(), onRowTap: { _ in })
                .frame(width: 380, height: 100)
                .background(Color.black)
                .previewDisplayName("历史面板 - 空状态")
        }
        .preferredColorScheme(.dark)
    }

    /// 创建模拟数据控制器
    static func createMockController() -> HistoryController {
        let controller = HistoryController()
        controller.remember(HistoryEntry(
            title: "要把这次改动部署到哪个环境？",
            body: "预发环境；产品经理",
            state: "已回答",
            source: "Qoder",
            project: "",
            provider: "qoder",
            host: nil,
            tintRGB: (red: 0.55, green: 0.35, blue: 0.95),
            timestamp: Date().addingTimeInterval(-120)
        ))
        controller.remember(HistoryEntry(
            title: "终端命令",
            body: "rm -rf node_modules && npm install",
            state: "已提醒",
            source: "Qoder",
            project: "",
            provider: "qoder",
            host: nil,
            tintRGB: (red: 0.55, green: 0.35, blue: 0.95),
            timestamp: Date().addingTimeInterval(-60)
        ))
        controller.remember(HistoryEntry(
            title: "终端命令",
            body: "rm -rf node_modules && npm install",
            state: "已提醒",
            source: "Qoder",
            project: "",
            provider: "qoder",
            host: nil,
            tintRGB: (red: 0.55, green: 0.35, blue: 0.95),
            timestamp: Date()
        ))
        return controller
    }
}
#endif
