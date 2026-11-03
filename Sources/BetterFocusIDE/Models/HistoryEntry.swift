// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 最近通知历史中的一条记录：发生了什么、由哪个应用产生、如何跳回。
///
/// 仅驻留内存（保留最近 N 条），不落盘。
struct HistoryEntry: Identifiable, Equatable {
    let id = UUID()
    /// 内容标题（问题头部 / 工具动作名 / 会话标题）。
    let title: String
    /// 副文字（回答内容 / 详情），在卡片中以"答："前缀展示。
    let body: String
    /// 结果行，如 "已回答" / "已拒绝" / "回复完成"。
    let state: String
    /// 来源展示名（宿主应用名或提供方名）。
    let source: String
    /// 作为淡色元数据显示的项目叶子名（路径末级目录）。
    let project: String
    /// 提供方可用于跳回 IDE 的标识。
    let provider: String?
    /// 宿主应用信息（bundle/name/path），用于精确跳转。
    let host: HostInfo?
    /// 徽章主题色 RGB 分量。
    let tintRGB: (red: Double, green: Double, blue: Double)
    let timestamp: Date

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }

    /// 格式化后的时间文本（HH:mm）。
    var clockText: String {
        HistoryEntry.formatter.string(from: timestamp)
    }

    /// 24 小时制时:分格式化器（英文区域，避免中文数字干扰）。
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 来源首字母大写——徽章上显示的字符。
    var badgeText: String {
        let base = source.isEmpty ? "?" : source
        return String(base.prefix(1)).uppercased()
    }
}
