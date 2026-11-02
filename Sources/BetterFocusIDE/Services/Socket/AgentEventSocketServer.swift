// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Unix Domain Socket server listening for JSON events from Qoder Hook / OpenCode Plugin.
/// Each message is newline-delimited JSON; parsed events are routed to NotchService.
final class AgentEventSocketServer {
    static let shared = AgentEventSocketServer()

    /// Outcome of `start()`. `.alreadyRunning` means another instance holds the
    /// socket path, so the caller should not raise a second island.
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
    /// Descriptor for the `<socket>.lock` `flock`; kept open for the whole
    /// process lifetime so the kernel releases it on exit (including `kill -9`).
    private var lockFD: Int32 = -1

    /// Callback invoked on main queue for each parsed socket message.
    var onMessage: ((AgentSocketMessage) -> Void)?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        socketURL = appSupport.appendingPathComponent("BetterFocusIDE/agent-events.sock")
    }

    // MARK: - Lifecycle

    /// Bind and listen, guarded by a single-instance lock. A second instance
    /// finds the lock held (or a live listener) and returns `.alreadyRunning`
    /// instead of unlinking the first instance's socket and turning it into a
    /// ghost that receives nothing.
    @discardableResult
    func start() -> StartOutcome {
        queue.sync {
            guard !running else { return .started }
            do {
                try FileManager.default.createDirectory(
                    at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try acquireLock()
                if probeAlive() {
                    // An old build that predates the lock file may still be
                    // listening; never steal its socket path.
                    releaseLock()
                    return .alreadyRunning
                }
                try bindAndListen()
                startAccepting()
                running = true
                Log.info("Socket server listening at \(socketURL.path)", topic: "socket")
                return .started
            } catch is SocketInUse {
                return .alreadyRunning
            } catch {
                releaseLock()
                return .failed(error.localizedDescription)
            }
        }
    }

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
            // Release the lock but leave the lock file on disk: unlinking it and
            // recreating would let two processes lock different inodes, voiding
            // the protection (see `acquireLock`).
            releaseLock()
        }
    }

    // MARK: - Single-instance lock

    /// Take an exclusive, non-blocking `flock` on `<socket>.lock`. Fails if
    /// another instance already holds it. The lock file is never deleted.
    private func acquireLock() throws {
        guard lockFD < 0 else { return }
        let path = socketURL.path + ".lock"
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .ENOENT) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw SocketInUse()
        }
        // Record the pid so `cat agent-events.sock.lock` reveals the holder.
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

    /// Try to connect to the socket. A Unix-domain connect returns
    /// immediately: success means a live listener, failure means a dead file.
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


    // MARK: - Bind

    private func bindAndListen() throws {
        // Remove stale socket
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
        // Non-blocking for accept loop
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        serverFD = fd
    }

    // MARK: - Accept

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

    private func acceptClients() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            startReading(clientFD: clientFD)
        }
    }

    // MARK: - Read

    private func startReading(clientFD: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        var buffer = Data()

        source.setEventHandler { [weak self] in
            let available = source.data
            var chunk = [UInt8](repeating: 0, count: max(1, Int(available)))
            let n = read(clientFD, &chunk, chunk.count)
            guard n > 0 else { source.cancel(); return }
            buffer.append(contentsOf: chunk.prefix(Int(n)))

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

    // MARK: - Parse

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
            // Never log the raw bytes — a malformed line may carry user content;
            // only the failure reason and size are safe.
            Log.warning("decode failed: \(error.localizedDescription) (\(data.count) bytes)", topic: "socket")
        }
    }
}
