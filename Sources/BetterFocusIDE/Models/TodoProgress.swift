// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import CoreGraphics
import Foundation

// MARK: - 状态

/// 待办项状态。
///
/// 各宿主的原始取值并不统一，映射关系见 `init(hostValue:)`：
/// - Claude / Qoder / Cursor / Trae：`pending` / `in_progress` / `completed` / `cancelled`
/// - Kimi Code CLI：`pending` / `in_progress` / `done`
/// - Claude Code V2 与 WorkBuddy 的 Task 家族：`pending` / `in_progress` / `completed` / `deleted`
enum TodoStatus: String, Equatable, CaseIterable {
    case pending
    case inProgress
    case completed
    case cancelled

    /// 解析宿主原始值：兼容连字符、大小写与各家别名。
    ///
    /// 认不出的值一律落到 `.pending`——宁可显示成「未开始」，也不要把一条
    /// 任务整条丢掉（丢掉会让段数突变，进度条看起来像在乱跳）。
    init(hostValue: String?) {
        let raw = (hostValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "completed", "complete", "done", "finished", "success":
            self = .completed
        case "cancelled", "canceled", "deleted", "skipped", "abandoned":
            self = .cancelled
        case "in_progress", "in-progress", "inprogress", "active", "running", "doing":
            self = .inProgress
        default:
            self = .pending
        }
    }

    /// 是否仍占用「剩余任务」计数。
    var isOpen: Bool {
        switch self {
        case .pending, .inProgress: return true
        case .completed, .cancelled: return false
        }
    }
}

// MARK: - 待办项

struct TodoItem: Identifiable, Equatable {
    /// 稳定标识：宿主给了 id 就用它，没给就用正文的哈希。
    let id: String
    var content: String
    var status: TodoStatus

    init(id: String, content: String, status: TodoStatus) {
        self.id = id
        self.content = content
        self.status = status
    }

    /// 从宿主载荷构造。
    ///
    /// **id 稳定性是动画正确性的前提**：`TodoWrite` / `todowrite` 是整表覆盖语义，
    /// 每次都把完整列表重发一遍。若拿数组下标当 id，SwiftUI 会认为「每一行都换了」，
    /// 于是每来一次更新整张卡片重建、所有过渡动画全部重播。正文哈希能保证
    /// 内容不变的任务在多次覆盖之间是同一个 id。
    init?(hostPayload payload: AnyCodableValue) {
        guard let dict = payload.dictValue else { return nil }

        // 正文：兼容 content / title / subject / text 四种叫法
        //（Claude 系用 content，Claude Code V2 与 WorkBuddy 的 Task 用 subject，
        //  Kimi 的 SetTodoList 用 title）。
        let content = (dict["content"]?.stringValue
            ?? dict["title"]?.stringValue
            ?? dict["subject"]?.stringValue
            ?? dict["text"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        // 状态：兼容 status / state / completed 三种写法。
        var status = TodoStatus(hostValue: dict["status"]?.stringValue
            ?? dict["state"]?.stringValue)
        if let done = dict["completed"]?.boolValue, done { status = .completed }

        let hostID = dict["id"]?.stringValue
            ?? dict["task_id"]?.stringValue
            ?? dict["taskId"]?.stringValue

        self.init(id: hostID.flatMap { $0.isEmpty ? nil : $0 } ?? Self.stableID(for: content),
                  content: content,
                  status: status)
    }

    /// 由正文推导稳定 id（FNV-1a 32 位，够短且无需引入 CryptoKit）。
    static func stableID(for content: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for byte in content.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return "t" + String(hash, radix: 16)
    }
}

// MARK: - 卡片布局度量

/// 待办卡片的内容高度（纯函数，便于单测与与视图逐段对齐）。
///
/// 与 `QuestionCardLayout` 同构：视图按这些常量排布，`NotchService` 按同一个
/// 函数算窗口高度，两边不许各写一份魔数。
enum TodoCardLayout {
    /// 卡片上下内边距。
    static let verticalPadding: CGFloat = 10
    /// 头部高度（徽章 24pt 行高）。
    static let headerHeight: CGFloat = 26
    /// 头部与进度条之间。
    static let headerGap: CGFloat = 12
    /// 进度条高度。
    static let barHeight: CGFloat = 6
    /// 进度条与当前任务行之间。
    static let barGap: CGFloat = 14
    /// 当前任务行高度。
    static let currentRowHeight: CGFloat = 18
    /// 两行之间。
    static let rowGap: CGFloat = 8
    /// 「下一步」行高度。
    static let nextRowHeight: CGFloat = 16
    /// 进度条最多显示多少段。
    ///
    /// 8 段上限会让「10 项任务」被压成 8 段，段数与总数对不上、易被误解成丢数据。
    /// 提高到 16：刘海卡片宽约 449pt，16 段时每段约 22pt，胶囊依然清晰；
    /// 绝大多数 todo ≤ 16 项，段数 == 总数，一眼对得上。超过才分桶压缩。
    static let maxSegments: Int = 16

    /// 内容高度（不含刘海安全区）。
    static func contentHeight(showsNext: Bool) -> CGFloat {
        var height = verticalPadding * 2 + headerHeight + headerGap + barHeight + barGap
            + currentRowHeight
        if showsNext {
            height += rowGap + nextRowHeight
        }
        return height
    }

    /// 含刘海安全区的卡片高度。
    static func cardHeight(safeContentTop: CGFloat, showsNext: Bool) -> CGFloat {
        safeContentTop + contentHeight(showsNext: showsNext)
    }
}

// MARK: - 列表视图模型

/// 一份待办快照的派生量：进度、当前项、下一项、分段映射。
struct TodoProgress {
    let items: [TodoItem]

    init(items: [TodoItem]) {
        self.items = items
    }

    var total: Int { items.count }
    var completed: Int { items.filter { $0.status == .completed }.count }
    /// 剩余（含进行中与未开始；已取消不计）。
    var remaining: Int { items.filter { $0.status.isOpen }.count }

    var current: TodoItem? {
        items.first { $0.status == .inProgress }
    }

    /// 下一项：当前项之后第一个未开始的项。
    var next: TodoItem? {
        guard let index = items.firstIndex(where: { $0.status == .inProgress }) else {
            return items.first { $0.status == .pending }
        }
        return items[(index + 1)...].first { $0.status == .pending }
    }

    /// 是否全部结束（完成或取消），且确实有任务。
    var isFinished: Bool {
        !items.isEmpty && items.allSatisfy { !$0.status.isOpen }
    }

    /// 整体进度 0…1（取消项按「已处理」计）。
    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// 头部计数文案：`3 / 6`。
    var countText: String { "\(completed) / \(total)" }

    /// 分段条的每段填充比例。
    ///
    /// - 任务数 ≤ 16：一段一个任务，填充 0 或 1。
    /// - 任务数 > 16：均分成 16 桶，每桶按「桶内已完成比例」部分填充——
    ///   这样段数恒定、进度仍然连续，比「只显示前 16 项」诚实得多。
    var segmentFills: [Double] {
        guard !items.isEmpty else { return [] }
        let limit = TodoCardLayout.maxSegments
        if total <= limit {
            return items.map { $0.status == .completed || $0.status == .cancelled ? 1 : 0 }
        }
        var fills: [Double] = []
        for bucket in 0..<limit {
            let start = Int((Double(bucket) * Double(total) / Double(limit)).rounded(.down))
            let end = Int((Double(bucket + 1) * Double(total) / Double(limit)).rounded(.down))
            let slice = items[start..<max(start + 1, end)]
            let done = slice.filter { !$0.status.isOpen }.count
            fills.append(Double(done) / Double(slice.count))
        }
        return fills
    }

    /// 当前段（进行中）在分段条中的下标；全部完成时为 nil。
    var activeSegment: Int? {
        guard !items.isEmpty, !isFinished else { return nil }
        guard let index = items.firstIndex(where: { $0.status == .inProgress }) else {
            return items.firstIndex { $0.status == .pending }
        }
        if total <= TodoCardLayout.maxSegments { return index }
        // 分桶模式下按比例换算桶序号。
        let limit = TodoCardLayout.maxSegments
        return min(limit - 1, index * limit / total)
    }
}

// MARK: - 载荷解析

/// 各宿主 todo 载荷的形状差异全部收在这里。
///
/// 已知形态：
/// - `{ "todos": [...] }` —— Claude / Qoder / Cursor / Trae 的 `TodoWrite`
/// - `{ "todos": [...] }` —— OpenCode `todowrite`（字段是 `content` + `status`）
/// - `{ "todos": [...] }` —— Kimi `SetTodoList`（字段是 `title` + `status: done`）
/// - `{ "task": {...} }` / 裸对象 —— Claude Code V2 与 WorkBuddy 的 `TaskCreate/Update`
///
/// 解析失败一律返回 nil 而不是空数组：空数组在覆盖语义里等同于「宿主清空了列表」，
/// 会把卡片错误地推进收尾态。
enum TodoPayloadParser {
    /// 常见的列表容器键（按宿主血统排序）。
    private static let listKeys = ["todos", "tasks", "items", "list", "plan"]
    /// 常见的单项容器键。
    private static let itemKeys = ["task", "todo", "item"]

    /// 整表列表；载荷里没有列表时返回 nil。
    static func list(from payload: AnyCodableValue?) -> [TodoItem]? {
        if case .array(let array) = payload {
            return array.compactMap(TodoItem.init(hostPayload:))
        }
        for key in listKeys {
            if let value = dict(payload)?[key], case .array(let array) = value {
                return array.compactMap(TodoItem.init(hostPayload:))
            }
        }
        return nil
    }

    /// 单个待办；载荷里没有可识别的正文时返回 nil。
    static func single(from payload: AnyCodableValue?) -> TodoItem? {
        if let item = TodoItem(hostPayload: payload ?? .null) { return item }
        for key in itemKeys {
            if let value = dict(payload)?[key], let item = TodoItem(hostPayload: value) {
                return item
            }
        }
        return nil
    }

    private static func dict(_ payload: AnyCodableValue?) -> [String: AnyCodableValue]? {
        if case .dictionary(let d) = payload { return d }
        return nil
    }
}
