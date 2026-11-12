// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 把 Qoder IDE 卡片上的「始终允许」交给语言服务。
///
/// 设置页改终端模式时调用 `config/updateGlobalTerminalRunMode`。正在生效的值是
/// `terminalRunMode`，对应设置记录里的 `configChatTerminalRunMode`。
/// 「始终允许」把终端设为 `fullAccess`（完全访问权限），把 Web 工具设为自动执行，
/// 把计划智能体设为自动运行。设置页重新打开时读的是 `User/app.json`，不是
/// `settings.json`。页面会把 app.json 里的旧值同步回语言服务。所以语言服务收下后，
/// 还要改 app.json 和 settings.json 里的对应字段。语言服务没连上时返回
/// `.downgraded`，调用方把这一次当成「允许」。
enum QoderCommandAllowList {
    /// 写入结果。`remembered` 的字符串是落盘的命令名。
    enum Outcome: Equatable {
        case remembered(String)
        case downgraded
    }

    /// 测试注入路径。非 nil 时不再碰用户目录，也不连接真正的语言服务。
    static var locationsForTesting: ((AgentProvider) -> (ui: URL, runtime: URL)?)?

    /// 测试注入的语言服务。参数是方法名和请求体，返回 `result` 对象。
    static var rpcForTesting: ((String, [String: Any]) -> [String: Any]?)?

    private static let defaultDenyList = "rm,mv,sudo,wget,curl,chown,remove-item"
    /// 设置页「完全访问权限」。语言服务和设置记录都用这个大小写。
    private static let fullAccessMode = "fullAccess"
    /// 设置页 Web 工具「自动执行」。文件里是英文文案，语言服务是另一套枚举。
    private static let webAutoPage = "Auto-execute"
    private static let webAutoLive = "enabledAutoExecute"
    /// 设置页计划智能体「自动运行」。文件里是英文文案，语言服务是另一套枚举。
    private static let planAutoPage = "Auto-run"
    private static let planAutoLive = "autoRunInFuture"

    /// 桌面版「本会话允许」用的命令名。不写任何配置文件。
    static func sessionToken(from command: String) -> String? {
        token(from: command, denyList: defaultDenyList)
    }

    /// 取命令的第一个词。含逗号或引号、或命中禁用列表时返回 nil。
    static func token(from command: String, denyList: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let token = String(first)
        guard !token.isEmpty else { return nil }
        if token.contains(",") || token.contains("\"") || token.contains("'") { return nil }
        let denied = denyList.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if denied.contains(token.lowercased()) { return nil }
        return token
    }

    /// 把命令名追加进逗号分隔列表。已有同名项（忽略大小写）则不重复。
    static func merging(_ existing: String, token: String) -> String {
        var parts = existing.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if parts.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) {
            return parts.joined(separator: ",")
        }
        parts.append(token)
        return parts.joined(separator: ",")
    }

    /// 按产品选择两份配置。Qoder CN 用自己的 Application Support 目录。
    static func locations(for provider: AgentProvider) -> (ui: URL, runtime: URL)? {
        if let locationsForTesting { return locationsForTesting(provider) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        switch provider {
        case .qoder, .qoder_ide, .qoder_cli:
            return (support.appendingPathComponent("Qoder/User/settings.json"),
                    support.appendingPathComponent("Qoder/SharedClientCache/cache/app-config.json"))
        case .qoder_cn, .qoder_cn_ide, .qoder_cn_cli:
            return (support.appendingPathComponent("QoderCN/User/settings.json"),
                    support.appendingPathComponent("QoderCN/SharedClientCache/cache/app-config.json"))
        default:
            return nil
        }
    }

    /// 把终端、Web 工具、计划智能体改成自动执行。语言服务没收下就放弃。
    static func remember(command: String, provider: AgentProvider) -> Outcome {
        guard locations(for: provider) != nil else { return .downgraded }
        guard var current = call(method: "config/getGlobal", params: [:], provider: provider) else {
            Log.info("没有读到 Qoder 的自动执行配置，这次按允许处理", topic: "permission")
            return .downgraded
        }
        current["terminalRunMode"] = fullAccessMode
        current["webToolsExecutionMode"] = webAutoLive
        current["planModeRunConfig"] = planAutoLive
        guard let updated = call(method: "config/updateGlobal", params: current, provider: provider),
              (updated["success"] as? Bool) == true,
              let terminal = call(method: "config/updateGlobalTerminalRunMode",
                                  params: ["terminalRunMode": fullAccessMode],
                                  provider: provider),
              (terminal["success"] as? Bool) == true else {
            Log.info("没有把自动执行改成放行，这次按允许处理", topic: "permission")
            return .downgraded
        }
        if let settings = locations(for: provider)?.ui {
            mirrorSettings(fullAccessMode, key: "configChatTerminalRunMode", at: settings)
            mirrorSettings(webAutoPage, key: "configChatWebToolsMode", at: settings)
            mirrorSettings(planAutoPage, key: "configIntegrationsPlanModeRunConfig", at: settings)
            let page = settings.deletingLastPathComponent().appendingPathComponent("app.json")
            mirrorJSONKey(fullAccessMode, key: "terminalRunMode", at: page)
            mirrorJSONKey(webAutoPage, key: "webToolsMode", at: page)
            mirrorJSONKey(planAutoPage, key: "planModeRunConfig", at: page)
        }
        return .remembered(token(from: command, denyList: defaultDenyList) ?? "")
    }

    /// 语言服务调用。测试注入优先；测试路径下绝不连接用户正在用的套接字。
    private static func call(method: String, params: [String: Any], provider: AgentProvider) -> [String: Any]? {
        if let rpcForTesting { return rpcForTesting(method, params) }
        if locationsForTesting != nil { return nil }
        guard let path = socketPath(for: provider) else { return nil }
        return rpc(socketPath: path, method: method, params: params)
    }

    private static func socketPath(for provider: AgentProvider) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support")
        switch provider {
        case .qoder_ide, .qoder_cli:
            return support.appendingPathComponent("Qoder/SharedClientCache/qoder.sock").path
        case .qoder_cn_ide, .qoder_cn_cli:
            return support.appendingPathComponent("QoderCN/SharedClientCache/qoder.sock").path
        default:
            return nil
        }
    }

    /// 改设置页真正读取的 `app.json`。只换 `terminalRunMode` 的字符串，不动其他键。
    private static func mirrorJSONKey(_ value: String, key: String, at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let patched = replacingJSONString(data, key: key, value: value) else { return }
        do {
            try patched.write(to: url, options: .atomic)
        } catch {
            Log.error("Qoder 设置页配置写入失败：\(error.localizedDescription)", topic: "permission")
        }
    }

    /// 把语言服务已经收下的终端模式抄进设置页写出的那份记录。抄不进去不影响这次决定。
    private static func mirrorSettings(_ value: String, key: String, at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let ui = jsonObject(data),
              ui["app"] is [String: Any] else { return }
        guard let patched = replacingJSONString(data, key: key, value: value)
                ?? rewritten(ui, key: key, value: value) else { return }
        do {
            try patched.write(to: url, options: .atomic)
        } catch {
            Log.error("Qoder 设置记录写入失败：\(error.localizedDescription)", topic: "permission")
        }
    }

    /// 只替换指定键的字符串值，保留文件其余字节。
    private static func replacingJSONString(_ data: Data, key: String, value: String) -> Data? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        let pattern = "(\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\")((?:\\\\.|[^\"\\\\])*)(\")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 2), in: text) else { return nil }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        text.replaceSubrange(valueRange, with: escaped)
        return text.data(using: .utf8)
    }

    private static func rewritten(_ ui: [String: Any], key: String, value: String) -> Data? {
        var copy = ui
        guard var app = copy["app"] as? [String: Any] else { return nil }
        app[key] = value
        copy["app"] = app
        return try? JSONSerialization.data(withJSONObject: copy, options: [.prettyPrinted])
    }

    /// `Content-Length` 分帧的 JSON-RPC。和 Qoder IDE 连接 `qoder.sock` 的方式一致。
    private static func rpc(socketPath: String, method: String, params: [String: Any]) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        let timeoutLen = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutLen)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutLen)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: bytes.count) { dst in
                dst.update(from: bytes, count: bytes.count)
            }
        }
        addr.sun_len = UInt8(MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + bytes.count)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        guard let body = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        let outgoing = Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
        var sent = 0
        let total = outgoing.count
        let writeOK: Bool = outgoing.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            while sent < total {
                let n = Darwin.write(fd, base + sent, total - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        guard writeOK else { return nil }

        var incoming = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while framedBody(incoming) == nil {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { return nil }
            incoming.append(buffer, count: n)
        }
        guard let payload = framedBody(incoming),
              let object = jsonObject(payload) else { return nil }
        return object["result"] as? [String: Any]
    }

    private static func framedBody(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              let marker = text.range(of: "\r\n\r\n") else { return nil }
        let header = text[..<marker.lowerBound]
        guard let line = header.split(separator: "\r\n").first(where: {
            $0.lowercased().hasPrefix("content-length:")
        }) else { return nil }
        let lengthText = line.split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespaces)
        guard let length = lengthText.flatMap(Int.init), length >= 0 else { return nil }
        let headerBytes = Data(text[..<marker.upperBound].utf8).count
        guard data.count >= headerBytes + length else { return nil }
        return data.subdata(in: headerBytes..<(headerBytes + length))
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
