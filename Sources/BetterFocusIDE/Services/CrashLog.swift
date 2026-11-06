// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Darwin
import Foundation

/// 崩溃记录。运行日志走 `Log`（异步、可轮转）；这里专门接住进程被打死的那一下，
/// 把异常或信号和调用栈同步写进 `logs/crash.log`，下次启动再指出上次没有正常退出。
///
/// 信号处理器里只能用 async-signal-safe 的调用，所以崩溃文件描述符在安装时就打开，
/// 栈缓冲也事先分配好。不在处理器里做 Swift 字符串或走 `Log` 的队列。
enum CrashLog {
    private static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE]
    /// 崩溃文件。安装时打开，处理器里只对它 `write`。
    private static var crashFD: Int32 = -1
    /// `backtrace` 用的缓冲，安装时分配，避免在信号里 malloc。
    private static var stackSlots: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    private static let stackCount: Int32 = 128
    private static var sessionURL: URL?

    /// 尽早安装。幂等。此时还不知道自己是不是主实例，不写会话锁。
    static func install() {
        guard crashFD < 0 else { return }
        guard let dir = Log.directoryURL else { return }
        let crashURL = dir.appendingPathComponent("crash.log")
        rotateCrashFileIfNeeded(crashURL)
        crashFD = open(crashURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        stackSlots = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(stackCount))
        publishCrashState(fd: crashFD, slots: stackSlots, count: stackCount)
        NSSetUncaughtExceptionHandler(recordException)
        for sig in signals {
            signal(sig, recordSignal)
        }
    }

    /// 主实例确认之后调用：记下本进程，并报告上一次有没有正常退出。
    static func noteSessionStart() {
        guard let dir = Log.directoryURL else { return }
        let url = dir.appendingPathComponent("session.pid")
        sessionURL = url
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if pid > 0, pid != getpid(), kill(pid, 0) != 0 {
                Log.warning("上次进程 pid=\(pid) 没有正常退出。调用栈在 logs/crash.log", topic: "crash")
            }
        }
        try? "\(getpid())\n".write(to: url, atomically: true, encoding: .utf8)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        Log.info("启动 pid=\(getpid()) 版本 \(version) (\(build)) macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                 topic: "app")
    }

    /// 正常退出时去掉会话锁。只删自己写下的那一份，避免把仍在运行的实例的锁清掉。
    static func markCleanExit() {
        Log.info("正常退出 pid=\(getpid())", topic: "app")
        Log.flush()
        guard let url = sessionURL,
              let text = try? String(contentsOf: url, encoding: .utf8),
              pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) == getpid() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 崩溃文件超过 1 MB 时留一份备份，避免无限涨。
    private static func rotateCrashFileIfNeeded(_ url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 1_048_576 else { return }
        let backup = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}

/// 未捕获的 Objective-C 异常。可以在这里用 Swift，但写崩溃文件仍走已经打开的描述符。
private func recordException(_ exception: NSException) {
    let frames = exception.callStackSymbols.joined(separator: "\n")
    let text = """
    ===== exception \(exception.name.rawValue) pid=\(getpid()) =====
    \(exception.reason ?? "")
    \(frames)

    """
    writeCrashText(text)
    signal(SIGABRT, SIG_DFL)
    abort()
}

/// 致命信号。只使用 write / backtrace，不碰 Swift 堆。
private func recordSignal(_ sig: Int32) {
    writeCrashRaw("===== signal ")
    writeCrashSignalName(sig)
    writeCrashRaw(" pid=")
    writeCrashNumber(UInt64(getpid()))
    writeCrashRaw(" time=")
    writeCrashNumber(UInt64(time(nil)))
    writeCrashRaw(" =====\n")
    if let slots = CrashLogSlots.pointer {
        let count = backtrace(slots, CrashLogSlots.count)
        backtrace_symbols_fd(slots, count, CrashLogSlots.fd)
        writeCrashRaw("\n")
    }
    _ = fsync(CrashLogSlots.fd)
    signal(sig, SIG_DFL)
    raise(sig)
}

/// 给信号处理器用的纯整数入口，避免从处理器里碰 `CrashLog` 的 Swift 状态。
private enum CrashLogSlots {
    static var pointer: UnsafeMutablePointer<UnsafeMutableRawPointer?>? { crashStackSlots }
    static var count: Int32 { crashStackCount }
    static var fd: Int32 { crashFileDescriptor }
}

// 信号处理器不能安全地读 enum 的存储。用文件级变量，安装时赋值。
private var crashFileDescriptor: Int32 = -1
private var crashStackSlots: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
private var crashStackCount: Int32 = 128

private func writeCrashText(_ text: String) {
    text.withCString { writeCrashRaw($0) }
    _ = fsync(crashFileDescriptor)
}

private func writeCrashRaw(_ text: UnsafePointer<CChar>) {
    guard crashFileDescriptor >= 0 else { return }
    _ = Darwin.write(crashFileDescriptor, text, strlen(text))
}

private func writeCrashNumber(_ value: UInt64) {
    var digits = [CChar](repeating: 0, count: 24)
    var n = value
    var index = 22
    repeat {
        digits[index] = CChar(48 + (n % 10))
        n /= 10
        index -= 1
    } while n > 0 && index >= 0
    _ = Darwin.write(crashFileDescriptor, &digits[index + 1], 22 - index)
}

private func writeCrashSignalName(_ sig: Int32) {
    switch sig {
    case SIGABRT: writeCrashStatic("SIGABRT")
    case SIGSEGV: writeCrashStatic("SIGSEGV")
    case SIGBUS: writeCrashStatic("SIGBUS")
    case SIGILL: writeCrashStatic("SIGILL")
    case SIGTRAP: writeCrashStatic("SIGTRAP")
    case SIGFPE: writeCrashStatic("SIGFPE")
    default: writeCrashStatic("SIGNAL")
    }
}

private func writeCrashStatic(_ text: StaticString) {
    guard crashFileDescriptor >= 0 else { return }
    text.withUTF8Buffer { buffer in
        _ = buffer.baseAddress.map { Darwin.write(crashFileDescriptor, $0, buffer.count) }
    }
}

// CrashLog.install 里分配的缓冲要交给文件级变量，处理器才能看见。
private func publishCrashState(fd: Int32, slots: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, count: Int32) {
    crashFileDescriptor = fd
    crashStackSlots = slots
    crashStackCount = count
}
