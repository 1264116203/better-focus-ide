// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Unix Domain Socket 服务端，监听来自 Qoder Hook / OpenCode Plugin 的 JSON 事件。
///
/// 每条消息以换行分隔（newline-delimited JSON），解析后路由到 NotchService。
final class AgentEventSocketServer {
    static let shared = AgentEventSocketServer()

    /// `start()` 的结果。`.alreadyRunning` 表示另一实例已持有 socket 路径，
    /// 调用方不应再拉起第二个灵动岛。
    enum StartOutcome {
        case started
        case alreadyRunning
        case failed(String)
    }

    private struct SocketInUse: Error {}

    private let socketURL: URL
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clientSources: [DispatchSourceRead] = []
    private let queue = DispatchQueue(label: "com.betterfocus.agent-socket", qos: .utility)
    private var running = false
    /// `<socket>.lock` 的 `flock` 描述符；整个进程生命周期保持打开，
    /// 由内核在退出时（包括 `kill -9`）自动释放。
    private var lockFD: Int32 = -1

    /// 每条解析后的 socket 消息在主队列上回调。
    var onMessage: ((AgentSocketMessage) -> Void)?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        socketURL = appSupport.appendingPathComponent("BetterFocusIDE/agent-events.sock")
    }

    // MARK: - 生命周期

    /// 绑定并监听，受单实例锁保护。第二个实例会发现锁被持有（或有活跃监听者），
    /// 返回 `.alreadyRunning`，而不是 unlink 掉第一实例的 socket、把自己变成
    /// 什么都收不到的幽灵进程。
    @discardableResult
    func start() -> StartOutcome {
        queue.sync {
            guard !running else { return .started }
            do {
                try FileManager.default.createDirectory(
                    at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try acquireLock()
                if probeAlive() {
                    // 某个早于锁文件机制的旧构建可能仍在监听；绝不抢它的 socket 路径。
                    releaseLock()
                    return .alreadyRunning
                }
                try bindAndListen()
                startAccepting()
                running = true
                Log.info("Socket 服务端监听于 \(socketURL.path)", topic: "socket")
                return .started
            } catch is SocketInUse {
                return .alreadyRunning
            } catch {
                releaseLock()
                return .failed(error.localizedDescription)
            }
        }
    }

    /// 停止监听：取消所有 source、关闭服务端 fd、移除 socket 文件。
    /// 锁文件保留在磁盘上（见 `acquireLock` 的说明）。
    func stop() {
        queue.sync {
            guard running else { releaseLock(); return }
            running = false
            acceptSource?.cancel()
            acceptSource = nil
            let sources = clientSources
            clientSources.removeAll()
            for s in sources { s.cancel() }
            if serverFD >= 0 { close(serverFD); serverFD = -1 }
            try? FileManager.default.removeItem(at: socketURL)
            // 释放锁但把锁文件留在磁盘上：unlink 再重建会让两个进程锁到不同 inode，
            // 从而使保护失效（见 `acquireLock`）。
            releaseLock()
        }
    }

    // MARK: - 单实例锁

    /// 对 `<socket>.lock` 取排他、非阻塞的 `flock`。若另一实例已持有则失败。
    /// 锁文件永不删除。
    private func acquireLock() throws {
        guard lockFD < 0 else { return }
        let path = socketURL.path + ".lock"
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .ENOENT) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw SocketInUse()
        }
        // 记录 pid，便于 `cat agent-events.sock.lock` 看出持有者。
        if ftruncate(fd, 0) == 0 {
            let pid = Data("\(getpid())\n".utf8)
            pid.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        }
        lockFD = fd
    }

    private func releaseLock() {
        guard lockFD >= 0 else { return }
        flock(lockFD, LOCK_UN)
        close(lockFD)
        lockFD = -1
    }

    /// 尝试连接 socket。Unix domain 的 connect 立即返回：成功表示有活跃监听者，
    /// 失败表示这是个死文件。
    private func probeAlive() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = socketURL.path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= maxLen else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() where i < maxLen { raw[i] = byte }
        }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }


    // MARK: - 绑定

    /// 绑定并监听 socket。会先移除陈旧 socket 文件；关键不变量：不能无条件删除
    /// 一个仍被运行中实例持有的 socket 路径（那会把 socket 从活实例手里偷走）。
    private func bindAndListen() throws {
        // 移除陈旧 socket
        try? FileManager.default.removeItem(at: socketURL)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .ENOENT) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let pathBytes = socketURL.path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= maxLen else {
            close(fd)
            throw NSError(domain: "AgentSocket", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() where i < maxLen { raw[i] = byte }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let err = POSIXError(.init(rawValue: errno) ?? .ENOENT)
            close(fd); throw err
        }
        guard listen(fd, 5) == 0 else {
            let err = POSIXError(.init(rawValue: errno) ?? .ENOENT)
            close(fd); throw err
        }
        // 设为非阻塞，供 accept 循环使用。
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        serverFD = fd
    }

    // MARK: - 接受连接

    /// 在服务端 fd 上建立读 source，有新连接时接受客户端。
    private func startAccepting() {
        guard serverFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFD, fd >= 0 { close(fd); self?.serverFD = -1 }
        }
        source.resume()
        acceptSource = source
    }

    /// 一次性排空所有待接受连接（非阻塞 accept 直到无更多）。
    private func acceptClients() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            startReading(clientFD: clientFD)
        }
    }

    // MARK: - 读取

    /// 为某个客户端 fd 建立读 source，按换行边界切分并逐条处理消息。
    private func startReading(clientFD: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        var buffer = Data()

        source.setEventHandler { [weak self] in
            let available = source.data
            var chunk = [UInt8](repeating: 0, count: max(1, Int(available)))
            let n = read(clientFD, &chunk, chunk.count)
            guard n > 0 else { source.cancel(); return }
            buffer.append(contentsOf: chunk.prefix(Int(n)))

            // 按换行拆出完整行，剩余不完整数据留在 buffer 等下次到达。
            while let nlIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nlIndex)
                buffer.removeSubrange(buffer.startIndex...nlIndex)
                if !lineData.isEmpty {
                    self?.processMessage(data: lineData)
                }
            }
        }
        source.setCancelHandler { [weak self] in
            close(clientFD)
            self?.clientSources.removeAll { $0 === source }
        }
        source.resume()
        clientSources.append(source)
    }

    // MARK: - 解析

    /// 解码一行 JSON 为 socket 消息，成功后在主队列回调 `onMessage`。
    private func processMessage(data: Data) {
        do {
            let message = try AgentSocketMessage.decoder().decode(AgentSocketMessage.self, from: data)
            Log.info(Log.describe(event: message.event, provider: message.provider,
                                  session: message.sessionID,
                                  request: message.payload?["request_id"]?.stringValue),
                     topic: "socket")
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(message)
            }
        } catch {
            // 绝不记录原始字节——畸形行可能携带用户内容；只记录失败原因和字节数才安全。
            Log.warning("decode failed: \(error.localizedDescription) (\(data.count) bytes)", topic: "socket")
        }
    }
}
