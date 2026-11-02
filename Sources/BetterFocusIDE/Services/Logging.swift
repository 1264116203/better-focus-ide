// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// The single logging entry point (mirrors the Python `log.py`). Every module
/// logs through this instead of raw `NSLog`, so problems leave a real trail in
/// `…/BetterFocusIDE/logs/betterfocus.log` rather than vanishing.
///
/// - File: `<AppSupport>/BetterFocusIDE/logs/betterfocus.log`, 5 MB × 3 rotation.
/// - Console: off by default; on with `BETTERFOCUS_LOG_STDERR=1` (or when the
///   disk isn't writable, so logging never blocks startup).
/// - Level: `DEBUG` by default (the rotation absorbs the volume), overridable
///   with `BETTERFOCUS_LOG_LEVEL`.
/// - **Never logs user content**: command bodies, question text, file contents
///   stay out. Cross-process messages go through `describe(...)` which keeps
///   only event / provider / id prefixes.
///
/// Logging itself never throws and never takes the island down.
enum LogLevel: Int, Comparable {
    case debug = 0, info, warning, error
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
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

    static let maxBytes = 5 * 1024 * 1024
    static let backupCount = 3
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

    // MARK: - Setup

    /// Configure once (idempotent). Safe to call before anything else logs.
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

            // Try to make the directory + touch the file; if the volume is
            // read-only or permission fails, degrade to stderr only.
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

    // MARK: - Writing

    private func write(_ level: LogLevel, topic: String, _ message: String) {
        // Ensure configured even if setup() wasn't called explicitly.
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

    /// Roll `log → log.1 → … → log.N` when the file would exceed `maxBytes`.
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

    // MARK: - Public API

    static func debug(_ message: String, topic: String = "app") { shared.write(.debug, topic: topic, message) }
    static func info(_ message: String, topic: String = "app") { shared.write(.info, topic: topic, message) }
    static func warning(_ message: String, topic: String = "app") { shared.write(.warning, topic: topic, message) }
    static func error(_ message: String, topic: String = "app") { shared.write(.error, topic: topic, message) }

    /// A desensitized one-line summary of a socket message — event type,
    /// provider, and id prefixes only. Never the payload (user content).
    static func describe(event: String?, provider: String?, session: String?, request: String?) -> String {
        func cut(_ s: String?) -> String {
            let v = s ?? "-"
            return String(v.prefix(idPrefix))
        }
        return "event=\(event ?? "-") provider=\(provider ?? "-") "
            + "session=\(cut(session)) request=\(cut(request))"
    }
}
