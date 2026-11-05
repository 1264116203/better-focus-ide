// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// 推断 OpenCode 会话真正跑在哪个终端里。
///
/// OpenCode 2.2.x 的后台服务（`opencode-cli serve --service`）统一执行所有会话，
/// 插件从事件流拿到的字段里**没有**客户端类型——桌面端和终端会话的事件完全一样，
/// 所以插件无法自己上报宿主。改为从进程表反推：终端里跑的 `opencode`（TUI 或
/// `opencode run`）的祖先链里一定有终端 App，而桌面端服务的祖先是 launchd。
///
/// 结论要么是本机某个终端（iTerm / Terminal / Warp…），要么是 nil——nil 时调用方
/// 保持原有回退（唤起 OpenCode 桌面端）。
enum OpenCodeHostProbe {
    /// 进程表的一项，`ps -axo pid=,ppid=,command=` 的解析结果。
    struct Proc: Equatable {
        let pid: Int
        let ppid: Int
        let command: String
    }

    /// 上溯祖先的最大深度，防止异常进程表导致死循环。
    static let maxDepth = 12

    /// 终端识别关键词 → 展示名。
    ///
    /// 顺序有意义：`terminal` 最泛（会命中 Terminal.app 之外的一些路径），放最后，
    /// 让 iTerm / Warp 等更具体的关键词先命中。
    static let terminalMarkers: [(key: String, display: String)] = [
        ("iterm", "iTerm"),
        ("warp", "Warp"),
        ("ghostty", "Ghostty"),
        ("kitty", "Kitty"),
        ("alacritty", "Alacritty"),
        ("wezterm", "WezTerm"),
        ("hyper", "Hyper"),
        ("terminal", "Terminal"),
    ]

    // MARK: - 对外入口

    /// 读一次进程表并推断终端宿主；系统调用失败或没有终端会话时返回 nil。
    ///
    /// - Parameter directory: 会话的项目目录。给定时只认 cwd 落在该目录内的客户端——
    ///   终端里的 opencode TUI 常常一开就是一整天，不比对目录的话，桌面端会话
    ///   也会被这盏常驻进程带偏到终端。
    static func currentTerminalHost(directory: String = "") -> HostInfo? {
        terminalHost(in: snapshot(), directory: directory)
    }

    /// 读一次进程表。
    static func snapshot() -> [Proc] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.info("进程表读取失败：\(error.localizedDescription)", topic: "launcher")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// 解析 `ps` 输出。抽成纯函数以便测试。
    ///
    /// 每行形如 `12345     1 /Applications/iTerm.app/Contents/MacOS/iTerm2 -q`：
    /// 前两列是 pid / ppid，其余整体是命令行（可能含空格）。
    static func parse(_ text: String) -> [Proc] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 2,
                                      omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { return nil }
            return Proc(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    /// 从进程表里找出终端宿主：任一 opencode 客户端进程的祖先里出现终端 App 即命中。
    ///
    /// 传入 `directory` 时优先返回 cwd 落在该目录内的客户端；cwd 读不到（权限或
    /// lsof 缺失）时降级为兜底候选，读到了但不匹配则明确排除。
    /// `cwd` 参数可注入，便于测试替换掉真实的 lsof 调用。
    static func terminalHost(in table: [Proc], directory: String = "",
                             cwd: (Int) -> String? = { workingDirectory(of: $0) }) -> HostInfo? {
        guard !table.isEmpty else { return nil }
        var byPid: [Int: Proc] = [:]
        for proc in table { byPid[proc.pid] = proc }
        var fallback: HostInfo?
        for proc in table where isClient(proc) {
            guard let host = ancestorTerminal(from: proc.ppid, byPid: byPid) else { continue }
            if directory.isEmpty { return host }
            guard let processCwd = cwd(proc.pid) else {
                if fallback == nil { fallback = host }
                continue
            }
            if pathsOverlap(processCwd, directory) { return host }
        }
        return fallback
    }

    /// 读进程的工作目录（`lsof -a -p <pid> -d cwd -Fn`）；失败返回 nil。
    static func workingDirectory(of pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parseWorkingDirectory(text)
    }

    /// 解析 lsof 输出（`p1234` / `fcwd` / `n/Users/...`），取 `n` 开头的行。
    /// 抽成纯函数便于测试。
    static func parseWorkingDirectory(_ text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if !path.isEmpty { return path }
        }
        return nil
    }

    /// 两个绝对路径是否有包含关系（同路径，或一方是另一方的祖先目录）。
    ///
    /// 双向包含是必要的：用户在项目子目录里启动 opencode 时，进程 cwd 是子目录，
    /// 而事件的 `location.directory` 是项目根。
    static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalized(lhs)
        let b = normalized(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    private static func normalized(_ path: String) -> String {
        var s = path
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 是否是 OpenCode 的终端客户端进程。
    ///
    /// 三类进程的命令行里都含 "opencode"，必须逐一排除，否则会把桌面端会话
    /// 或 IDE 内嵌会话误判成终端会话：
    /// - GUI 打包进程（`OpenCode.app/Contents/...`，含 Helper / Renderer）
    /// - 后台服务（`serve --service`，由桌面端拉起，祖先链里没有终端）
    /// - 本应用自己
    static func isClient(_ proc: Proc) -> Bool {
        let cmd = proc.command.lowercased()
        guard cmd.contains("opencode") else { return false }
        if cmd.contains(".app/contents/") { return false }
        if cmd.contains("--service") || cmd.contains(" serve") { return false }
        if cmd.contains("betterfocuside") { return false }
        return true
    }

    /// 沿 ppid 上溯，命中终端 App 即返回其宿主信息。
    static func ancestorTerminal(from pid: Int, byPid: [Int: Proc]) -> HostInfo? {
        var current = pid
        var depth = 0
        while current > 1 && depth < maxDepth {
            guard let proc = byPid[current] else { return nil }
            if let host = hostInfo(forTerminalCommand: proc.command) { return host }
            if proc.ppid == current { return nil }
            current = proc.ppid
            depth += 1
        }
        return nil
    }

    /// 命令行若指向某个终端 App，构造对应 HostInfo。
    static func hostInfo(forTerminalCommand command: String) -> HostInfo? {
        let lowered = command.lowercased()
        guard let marker = terminalMarkers.first(where: { lowered.contains($0.key) }) else {
            return nil
        }
        var host = HostInfo()
        host.name = marker.display
        host.bundle = TerminalHost.bundles
            .first(where: { $0.value == marker.display })?.key ?? ""
        host.path = appPath(in: command)
        return host
    }

    /// 从命令行里截出 `.app` 路径；取不到返回空串。
    static func appPath(in command: String) -> String {
        guard let range = command.range(of: ".app/Contents/MacOS") else { return "" }
        let head = String(command[command.startIndex..<range.lowerBound])
        // 命令可能带启动参数（如 `open -a /Applications/X`），取最后一个空格后的部分。
        if let space = head.lastIndex(of: " ") {
            return String(head[head.index(after: space)...]) + ".app"
        }
        return head + ".app"
    }
}
