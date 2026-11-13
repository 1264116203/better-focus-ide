// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// ACP 桥只改本机平台的 `cmd`，并把 JSON-RPC 译成岛上已经认识的事件。
final class AcpBridgeTests: XCTestCase {

    /// 发行包里的脚本在资源包的 Contents/Resources，不在包根目录。
    /// 本机源码树的 `#filePath` 兜底在别的电脑上不存在。
    func testReadsScriptFromBundleContentsResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-bundle-\(UUID().uuidString).bundle", isDirectory: true)
        let resources = root
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = "# bridge\nsession/update\n"
        try body.write(to: resources.appendingPathComponent("acp-bridge.py"),
                       atomically: true, encoding: .utf8)

        let text = try XCTUnwrap(AcpBridgeInstaller.scriptText(in: [root]))
        XCTAssertTrue(text.contains("session/update"))
    }

    func testWrapKeepsForeignFieldsAndRestoresOriginalCommand() {
        var registry = sampleRegistry()
        var sidecar: [String: Any] = [:]
        let script = "/tmp/betterfocus-acp-bridge.py"
        XCTAssertEqual(AcpBridgeInstaller.wrap(&registry, sidecar: &sidecar,
                                               scriptPath: script, platform: "darwin-aarch64"), 1)
        XCTAssertEqual(AcpBridgeInstaller.wrap(&registry, sidecar: &sidecar,
                                               scriptPath: script, platform: "darwin-aarch64"), 1)

        let mac = slot(registry, platform: "darwin-aarch64")
        XCTAssertEqual(mac["cmd"] as? String, script)
        XCTAssertEqual(mac["args"] as? [String], ["acp.registry.cursor"])
        XCTAssertEqual(mac["archive"] as? String, "https://example.invalid/agent.tar.gz")
        let linux = slot(registry, platform: "linux-x86_64")
        XCTAssertEqual(linux["cmd"] as? String, "./dist-package/cursor-agent")
        XCTAssertEqual(linux["args"] as? [String], ["acp"])

        let saved = (sidecar["agents"] as? [String: Any])?["acp.registry.cursor"] as? [String: Any]
        XCTAssertEqual(saved?["cmd"] as? String, "./dist-package/cursor-agent")
        XCTAssertEqual(saved?["args"] as? [String], ["acp"])

        XCTAssertTrue(AcpBridgeInstaller.restore(&registry, sidecar: sidecar,
                                                 scriptPath: script, platform: "darwin-aarch64"))
        let restored = slot(registry, platform: "darwin-aarch64")
        XCTAssertEqual(restored["cmd"] as? String, "./dist-package/cursor-agent")
        XCTAssertEqual(restored["args"] as? [String], ["acp"])
        XCTAssertEqual(restored["archive"] as? String, "https://example.invalid/agent.tar.gz")
    }

    func testCheckTranslatesTurnPermissionPlanAndTodo() throws {
        let source = try AcpBridgeInstaller.loadSource()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-bridge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("acp-bridge.py")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let input = """
        {"direction":"client","message":{"jsonrpc":"2.0","id":1,"method":"session/new","params":{"cwd":"/tmp/demo","mcpServers":[]}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","id":1,"result":{"sessionId":"s1"}}}
        {"direction":"client","message":{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":{"sessionId":"s1","prompt":[{"type":"text","text":"hello island"}]}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"plan_update","plan":{"type":"items","planId":"p1","entries":[{"content":"read the file","priority":"high","status":"in_progress"}]}}}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","id":9,"method":"session/request_permission","params":{"sessionId":"s1","toolCall":{"toolCallId":"t1","title":"Shell","rawInput":{"command":"ls"}},"options":[]}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"state_update","state":"idle","stopReason":"end_turn"}}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","id":2,"result":{"stopReason":"end_turn"}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call","toolCallId":"todo1","title":"TaskCreate","rawInput":{"subject":"write the bridge"}}}}}
        {"direction":"agent","message":{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"tool_call_update","toolCallId":"todo2","title":"TaskUpdate","rawInput":{"taskId":"21","status":"completed"}}}}}
        {"direction":"exit"}
        """
        let output = try runCheck(script: script, input: input)
        let events = try events(from: output)
        let names = events.compactMap { $0["event"] as? String }
        XCTAssertEqual(names.filter { $0 == "turn_finished" }.count, 1)
        XCTAssertEqual(names.filter { $0 == "session_ended" }.count, 1)
        XCTAssertTrue(names.contains("todo_updated"))
        XCTAssertTrue(names.contains("permission_notice"))
        XCTAssertGreaterThanOrEqual(names.filter { $0 == "todo_item_updated" }.count, 2)

        let turn = try XCTUnwrap(events.first { $0["event"] as? String == "turn_finished" })
        XCTAssertEqual(turn["product"] as? String, "jetbrains_plugin")
        XCTAssertEqual(turn["cwd"] as? String, "/tmp/demo")
        let payload = try XCTUnwrap(turn["payload"] as? [String: Any])
        XCTAssertEqual(payload["prompt"] as? String, "hello island")
        let host = try XCTUnwrap(turn["host"] as? [String: Any])
        XCTAssertEqual(host["bundle"] as? String, "com.jetbrains.intellij")

        let plan = try XCTUnwrap(events.first { $0["event"] as? String == "todo_updated" })
        let todos = ((plan["payload"] as? [String: Any])?["todos"] as? [[String: Any]]) ?? []
        XCTAssertEqual(todos.first?["content"] as? String, "read the file")
        XCTAssertEqual(todos.first?["status"] as? String, "in_progress")

        let update = events.last { event in
            guard event["event"] as? String == "todo_item_updated" else { return false }
            let todo = (event["payload"] as? [String: Any])?["todo"] as? [String: Any]
            return todo?["id"] as? String == "21"
        }
        let todo = (update?["payload"] as? [String: Any])?["todo"] as? [String: Any]
        XCTAssertEqual(todo?["content"] as? String, "write the bridge")
        XCTAssertEqual(todo?["status"] as? String, "completed")
    }

    func testRelativeCommandResolvesFromJetBrainsCache() throws {
        let source = try AcpBridgeInstaller.loadSource()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-bridge-rel-\(UUID().uuidString)", isDirectory: true)
        let agentDir = dir
            .appendingPathComponent("IntelliJIdea/acp-agents/cursor/2026.11.05/dist-package",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let agent = agentDir.appendingPathComponent("cursor-agent")
        let agentSource = """
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            msg = json.loads(line)
            if msg.get("method") == "session/new":
                out = {"jsonrpc": "2.0", "id": msg["id"], "result": {"sessionId": "s1"}}
                sys.stdout.write(json.dumps(out) + "\\n")
                sys.stdout.flush()
        """
        try agentSource.write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agent.path)

        let sidecar = dir.appendingPathComponent("sidecar.json")
        let sidecarObject: [String: Any] = [
            "agents": ["acp.registry.cursor": ["cmd": "./dist-package/cursor-agent", "args": ["acp"]]],
        ]
        try JSONSerialization.data(withJSONObject: sidecarObject).write(to: sidecar)

        let script = dir.appendingPathComponent("acp-bridge.py")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let text = try runBridge(script: script, sidecar: sidecar, cache: dir, agentID: "acp.registry.cursor",
                                 extraEnv: [:])
        XCTAssertTrue(text.contains("\"sessionId\": \"s1\"") || text.contains("\"sessionId\":\"s1\""), text)
    }

    func testForwardsAgentLines() throws {
        let source = try AcpBridgeInstaller.loadSource()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-bridge-fwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let agent = dir.appendingPathComponent("fake-agent.py")
        let agentSource = """
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            msg = json.loads(line)
            if msg.get("method") == "session/new":
                out = {"jsonrpc": "2.0", "id": msg["id"], "result": {"sessionId": "s1"}}
                sys.stdout.write(json.dumps(out) + "\\n")
                sys.stdout.flush()
        """
        try agentSource.write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agent.path)

        let sidecar = dir.appendingPathComponent("sidecar.json")
        let sidecarObject: [String: Any] = [
            "agents": ["demo": ["cmd": agent.path, "args": []]],
        ]
        let sidecarData = try JSONSerialization.data(withJSONObject: sidecarObject)
        try sidecarData.write(to: sidecar)

        let script = dir.appendingPathComponent("acp-bridge.py")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let text = try runBridge(script: script, sidecar: sidecar, cache: dir,
                                 agentID: "demo", extraEnv: [:])
        XCTAssertTrue(text.contains("\"sessionId\": \"s1\"") || text.contains("\"sessionId\":\"s1\""), text)
    }

    private func runBridge(script: URL, sidecar: URL, cache: URL, agentID: String,
                           extraEnv: [String: String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script.path, agentID]
        var env = ProcessInfo.processInfo.environment
        env["BETTERFOCUS_ACP_SIDECAR"] = sidecar.path
        env["BETTERFOCUS_ACP_CACHE"] = cache.path
        env["BETTERFOCUS_SOCKET"] = cache.appendingPathComponent("missing.sock").path
        env["BETTERFOCUS_SETTINGS"] = cache.appendingPathComponent("missing-settings.json").path
        env["BETTERFOCUS_ACP_HOST"] = #"{"bundle":"com.jetbrains.intellij","name":"IntelliJ IDEA","path":""}"#
        for (key, value) in extraEnv { env[key] = value }
        proc.environment = env
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = error
        try proc.run()
        let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/new\",\"params\":{\"cwd\":\"/tmp/demo\"}}\n"
        input.fileHandleForWriting.write(Data(request.utf8))
        input.fileHandleForWriting.closeFile()
        let deadline = Date().addingTimeInterval(5)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning { proc.terminate() }
        proc.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0, stderr + stdout)
        return stdout
    }

    private func runCheck(script: URL, input: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script.path, "--check"]
        proc.environment = [
            "BETTERFOCUS_ACP_HOST": #"{"bundle":"com.jetbrains.intellij","name":"IntelliJ IDEA","path":"/Applications/IntelliJ IDEA.app"}"#,
            "BETTERFOCUS_SETTINGS": "/tmp/betterfocus-acp-missing-settings.json",
        ]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe
        try proc.run()
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        proc.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0, stderr + stdout)
        return stdout
    }

    private func events(from output: String) throws -> [[String: Any]] {
        try output.split(separator: "\n").map { line in
            let data = Data(line.utf8)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    private func sampleRegistry() -> [String: Any] {
        [
            "agents": [
                "acp.registry.cursor": [
                    "installedAt": 1,
                    "agent": [
                        "name": "Cursor",
                        "distribution": [
                            "binary": [
                                "darwin-aarch64": [
                                    "cmd": "./dist-package/cursor-agent",
                                    "args": ["acp"],
                                    "archive": "https://example.invalid/agent.tar.gz",
                                ],
                                "linux-x86_64": [
                                    "cmd": "./dist-package/cursor-agent",
                                    "args": ["acp"],
                                ],
                            ] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private func slot(_ registry: [String: Any], platform: String) -> [String: Any] {
        let agents = registry["agents"] as? [String: Any]
        let entry = agents?["acp.registry.cursor"] as? [String: Any]
        let agent = entry?["agent"] as? [String: Any]
        let distribution = agent?["distribution"] as? [String: Any]
        let binary = distribution?["binary"] as? [String: Any]
        return binary?[platform] as? [String: Any] ?? [:]
    }
}
