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

    /// 补齐 OpenCode 会话的宿主信息。
    ///
    /// 插件跑在 serve 进程里，事件流不带客户端类型，桌面端 / 终端 / 浏览器三种
    /// 会话上报的 host 一模一样（都为空）。判定顺序：
    /// 1. 插件上报的 `pid` 若正是 `opencode serve` 且在本机监听端口 → 浏览器会话；
    /// 2. 否则沿进程表祖先链找终端；
    /// 3. 都不命中就原样返回，由调用方回退到产品桌面端。
    static func resolveHost(provider: AgentProvider,
                            host: HostInfo,
                            directory: String,
                            pid: Int?,
                            terminalHost: (String) -> HostInfo? = {
                                currentTerminalHost(directory: $0)
                            },
                            webHost: (String, Int?) -> HostInfo? = {
                                currentWebHost(pid: $1, directory: $0)
                            }) -> HostInfo {
        // 已经是明确的产品宿主（如 JetBrains 插件上报的 IDE）就别动。
        guard provider == .opencode,
              host.bundle.isEmpty || host.bundle == "ai.opencode.desktop" else { return host }
        if let web = webHost(directory, pid) { return web }
        guard let terminal = terminalHost(directory) else { return host }
        var updated = terminal
        updated.cwd = directory.isEmpty ? host.cwd : directory
        return updated
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

    // MARK: - 浏览器会话（`opencode serve` + Web UI）

    /// 浏览器会话的宿主标记。
    ///
    /// 这类会话真的没有任何窗口：用户在浏览器里操作，服务只是本机一个端口。
    /// 用独立 marker 占住 `bundle` 让 `host` 非空（历史能记住落地方式），
    /// 同时留空 `name`——徽章与来源名仍应是产品名 OpenCode，而不是「浏览器」。
    static let webBundleMarker = "betterfocus.web"

    /// 是否是 `opencode serve` 开出来的本地服务（浏览器 / Web UI 的后端）。
    ///
    /// 必须排除另外两类同名进程：桌面端常驻服务 `serve --service`、IDE 内嵌
    /// 的 ACP `serve --stdio`——它们也监听端口，但用户在各自的应用里。
    static func isServeServer(_ proc: Proc) -> Bool {
        let cmd = proc.command.lowercased()
        guard cmd.contains("opencode") else { return false }
        if cmd.contains(".app/contents/") { return false }
        if cmd.contains("betterfocuside") { return false }
        if cmd.contains("--service") || cmd.contains("--stdio") { return false }
        return cmd.contains(" serve")
    }

    /// 读一次进程表并推断浏览器宿主。
    static func currentWebHost(pid: Int?, directory: String = "") -> HostInfo? {
        webHost(in: snapshot(), pid: pid, directory: directory)
    }

    /// 从进程表里找出承载该会话的本地服务，返回指向其 Web UI 的宿主。
    ///
    /// - Parameter pid: 插件自报的进程号（`process.pid`）。有三种可能：serve 自身、
    ///   serve 派生的 cli 子进程（同一份插件会再加载一次）、或者终端 TUI。
    ///   只有祖先链上真的挂着 `opencode serve` 才算浏览器会话——一个 serve 能服务
    ///   多个项目目录，pid 比 cwd 更能认人。
    ///   pid 缺失（旧插件）时退回按 cwd 与项目目录比对。
    static func webHost(in table: [Proc],
                        pid: Int?,
                        directory: String = "",
                        port: (Proc) -> Int? = {
                            portFromCommand($0.command) ?? listeningPort(of: $0.pid)
                        },
                        cwd: (Int) -> String? = { workingDirectory(of: $0) }) -> HostInfo? {
        guard !table.isEmpty else { return nil }
        var byPid: [Int: Proc] = [:]
        for proc in table { byPid[proc.pid] = proc }

        let server: Proc?
        if let pid, byPid[pid] != nil {
            switch role(of: pid, byPid: byPid) {
            case .webServe(let proc): server = proc
            case .desktopService, .otherClient: return nil
            case .unknown: return nil
            }
        } else if !directory.isEmpty {
            server = table.first { proc in
                guard isServeServer(proc), let dir = cwd(proc.pid) else { return false }
                return pathsOverlap(dir, directory)
            }
        } else {
            return nil
        }

        guard let server, let number = port(server), number > 0 else { return nil }
        var host = HostInfo()
        host.bundle = webBundleMarker
        host.cwd = cwd(server.pid) ?? directory
        host.url = "http://127.0.0.1:\(number)/"
        return host
    }

    /// 某个 opencode 进程在本次会话里扮演的角色。
    enum ProcessRole: Equatable {
        /// 浏览器后端（`opencode serve`）：祖先链上命中。
        case webServe(Proc)
        /// 桌面端常驻服务（`serve --service`）。
        case desktopService
        /// 终端 TUI 或 `opencode run`。
        case otherClient
        /// 进程已退出或读不到进程表。
        case unknown
    }

    /// 沿 pid 的祖先链（含自身）判定角色。
    static func role(of pid: Int, byPid: [Int: Proc]) -> ProcessRole {
        var current = pid
        var depth = 0
        var sawClient = false
        while depth < maxDepth, let proc = byPid[current] {
            if isServeServer(proc) { return .webServe(proc) }
            if proc.command.lowercased().contains("--service") { return .desktopService }
            if isClient(proc) { sawClient = true }
            if proc.ppid == current || proc.ppid <= 1 { break }
            current = proc.ppid
            depth += 1
        }
        return sawClient ? .otherClient : .unknown
    }

    /// 从命令行解析 `--port 4096` / `--port=4096`；未指定时返回 nil。
    static func portFromCommand(_ command: String) -> Int? {
        let parts = command.split(separator: " ")
        for (index, part) in parts.enumerated() {
            if part == "--port", index + 1 < parts.count, let port = Int(parts[index + 1]) {
                return port
            }
            if part.hasPrefix("--port="), let port = Int(part.dropFirst("--port=".count)) {
                return port
            }
        }
        return nil
    }

    /// 读进程的监听端口（`lsof -a -p <pid> -iTCP -sTCP:LISTEN -P -Fn`）。
    ///
    /// `-P` 不能省：不加时 lsof 会把 4096 写成服务名 `bre`，解析出不了数字。
    static func listeningPort(of pid: Int) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-P", "-Fn"]
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
        return parseListeningPort(text)
    }

    /// 解析 lsof 输出里的监听端口，形如 `n127.0.0.1:4096`（IPv6 为 `n[::1]:4096`）。
    static func parseListeningPort(_ text: String) -> Int? {
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            guard let colon = line.lastIndex(of: ":") else { continue }
            if let port = Int(line[line.index(after: colon)...]), port > 0 { return port }
        }
        return nil
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
