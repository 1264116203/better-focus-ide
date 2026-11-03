// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 唯一的日志入口（对齐 Python 的 `log.py`）。所有模块都经此记录而非直接用
/// `NSLog`，让问题在 `…/BetterFocusIDE/logs/betterfocus.log` 里留下真实痕迹，
/// 而不是凭空消失。
///
/// - 文件：`<AppSupport>/BetterFocusIDE/logs/betterfocus.log`，5 MB × 3 轮转。
/// - 控制台：默认关闭；`BETTERFOCUS_LOG_STDERR=1` 打开（或磁盘不可写时也打开，
///   使日志从不阻塞启动）。
/// - 级别：默认 `DEBUG`（轮转能吸收体量），可用 `BETTERFOCUS_LOG_LEVEL` 覆盖。
/// - **绝不记录用户内容**：命令正文、问题文本、文件内容一律不落日志。跨进程消息
///   经 `describe(...)` 处理，只保留事件 / 提供方 / id 前缀。
///
/// 日志本身从不抛错、也从不把灵动岛拖垮。
enum LogLevel: Int, Comparable {
    case debug = 0, info, warning, error
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
    /// 定宽级别标签，便于日志列对齐。
    var label: String {
        switch self {
        case .debug: return "DEBUG  "
        case .info: return "INFO   "
        case .warning: return "WARNING"
        case .error: return "ERROR  "
        }
    }
}

final class Log {
    static let shared = Log()

    /// 单文件上限 5 MB。
    static let maxBytes = 5 * 1024 * 1024
    /// 保留的历史备份数。
    static let backupCount = 3
    /// `describe` 中 id 前缀截断长度。
    private static let idPrefix = 8

    private let queue = DispatchQueue(label: "com.betterfocus.log")
    private let formatter = DateFormatter()
    private var fileURL: URL?
    private var currentSize: Int = 0
    private var minLevel: LogLevel = .debug
    private var console = false
    private var configured = false

    private init() {
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    // MARK: - 初始化配置

    /// 配置一次（幂等）。在任何日志之前调用都安全。
    static func setup() { shared.configure() }

    private func configure() {
        queue.sync {
            guard !configured else { return }
            configured = true

            minLevel = Self.levelFromEnv() ?? .debug

            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("BetterFocusIDE/logs", isDirectory: true)
            let target = dir.appendingPathComponent("betterfocus.log")

            // 尝试建目录 + touch 文件；若卷只读或权限失败，降级为仅输出到 stderr。
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: target.path) {
                    FileManager.default.createFile(atPath: target.path, contents: nil)
                }
                fileURL = target
                currentSize = (try? FileManager.default
                    .attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
            } catch {
                fileURL = nil
                FileHandle.standardError.write(
                    "⚠ 日志文件不可写（\(error.localizedDescription)），仅输出到终端\n".data(using: .utf8)!)
            }

            console = ProcessInfo.processInfo.environment["BETTERFOCUS_LOG_STDERR"] == "1"
                || fileURL == nil
        }
    }

    /// 从环境变量解析日志级别；无法识别返回 nil（由调用方回退默认）。
    private static func levelFromEnv() -> LogLevel? {
        guard let name = ProcessInfo.processInfo.environment["BETTERFOCUS_LOG_LEVEL"]?
            .trimmingCharacters(in: .whitespaces).uppercased(), !name.isEmpty else { return nil }
        switch name {
        case "DEBUG": return .debug
        case "INFO": return .info
        case "WARNING", "WARN": return .warning
        case "ERROR": return .error
        default: return nil
        }
    }

    // MARK: - 写入

    /// 组装一行日志并按需写文件 / stderr（在串行队列上异步执行）。
    private func write(_ level: LogLevel, topic: String, _ message: String) {
        // 即便没显式调用 setup() 也确保已配置。
        if !configured { configure() }
        guard level >= minLevel else { return }
        let line = "\(formatter.string(from: Date())) \(level.label) \(topic): \(message)\n"
        let data = line.data(using: .utf8) ?? Data()
        queue.async {
            if let url = self.fileURL {
                self.rotateIfNeeded(incoming: data.count, url: url)
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                    self.currentSize += data.count
                }
            }
            if self.console {
                FileHandle.standardError.write(data)
            }
        }
    }

    /// 当文件将超过 `maxBytes` 时轮转：`log → log.1 → … → log.N`。
    private func rotateIfNeeded(incoming: Int, url: URL) {
        guard currentSize + incoming > Log.maxBytes else { return }
        let base = url.path
        try? FileManager.default.removeItem(atPath: "\(base).\(Log.backupCount)")
        var i = Log.backupCount - 1
        while i >= 1 {
            let from = "\(base).\(i)", to = "\(base).\(i + 1)"
            if FileManager.default.fileExists(atPath: from) {
                try? FileManager.default.moveItem(atPath: from, toPath: to)
            }
            i -= 1
        }
        if FileManager.default.fileExists(atPath: base) {
            try? FileManager.default.moveItem(atPath: base, toPath: "\(base).1")
        }
        FileManager.default.createFile(atPath: base, contents: nil)
        currentSize = 0
    }

    // MARK: - 公开 API

    static func debug(_ message: String, topic: String = "app") { shared.write(.debug, topic: topic, message) }
    static func info(_ message: String, topic: String = "app") { shared.write(.info, topic: topic, message) }
    static func warning(_ message: String, topic: String = "app") { shared.write(.warning, topic: topic, message) }
    static func error(_ message: String, topic: String = "app") { shared.write(.error, topic: topic, message) }

    /// 对一条 socket 消息做脱敏的单行摘要——只含事件类型、提供方、id 前缀，
    /// 绝不含 payload（用户内容）。
    static func describe(event: String?, provider: String?, session: String?, request: String?) -> String {
        func cut(_ s: String?) -> String {
            let v = s ?? "-"
            return String(v.prefix(idPrefix))
        }
        return "event=\(event ?? "-") provider=\(provider ?? "-") "
            + "session=\(cut(session)) request=\(cut(request))"
    }
}
