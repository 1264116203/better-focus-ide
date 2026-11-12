// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// Qoder 权限卡「始终允许」：命令名怎么切、两份配置怎么追加、应答怎么降级。
final class QoderCommandAllowListTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bf-allow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        QoderCommandAllowList.locationsForTesting = { _ in
            (ui: self.directory.appendingPathComponent("settings.json"),
             runtime: self.directory.appendingPathComponent("app-config.json"))
        }
    }

    override func tearDownWithError() throws {
        QoderCommandAllowList.locationsForTesting = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testCommandTokenUsesFirstWordAndSkipsDenyList() {
        XCTAssertEqual(QoderCommandAllowList.token(from: "git status", denyList: "rm,sudo"), "git")
        XCTAssertEqual(QoderCommandAllowList.token(from: "git", denyList: ""), "git")
        XCTAssertNil(QoderCommandAllowList.token(from: "   ", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "a,b", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "\"quoted\"", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "rm -rf /tmp", denyList: "rm,sudo"))
        XCTAssertNil(QoderCommandAllowList.token(from: "Sudo ls", denyList: "rm,sudo"))
    }

    func testMergeKeepsOtherEntriesAndDoesNotDuplicate() {
        XCTAssertEqual(QoderCommandAllowList.merging("git, npm", token: "git"), "git,npm")
        XCTAssertEqual(QoderCommandAllowList.merging("", token: "git"), "git")
        XCTAssertEqual(QoderCommandAllowList.merging("npm", token: "git"), "npm,git")
    }

    func testRememberWritesBothFilesAndPreservesOtherKeys() throws {
        try seed(uiAllow: "", runtimeAllow: "", deny: "rm,sudo")
        let outcome = QoderCommandAllowList.remember(command: "git status", provider: .qoder_ide)
        guard case .remembered(let token) = outcome else {
            return XCTFail("expected remembered, got \(outcome)")
        }
        XCTAssertEqual(token, "git")

        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatCommandAllowlist"] as? String, "git")
        XCTAssertEqual(app?["configChatTerminalRunMode"] as? String, "askEveryTime")

        let runtime = try json(at: directory.appendingPathComponent("app-config.json"))
        XCTAssertEqual(runtime["commandAllowList"] as? String, "git")
        XCTAssertEqual(runtime["terminalRunMode"] as? String, "askEveryTime")
    }

    func testRememberDoesNotCreateMissingFiles() {
        let outcome = QoderCommandAllowList.remember(command: "git status", provider: .qoder_ide)
        guard case .downgraded = outcome else {
            return XCTFail("expected downgraded, got \(outcome)")
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("settings.json").path))
    }

    func testAllowAlwaysRecordsTokenAndAllowOnceDoesNotTouchLists() throws {
        try seed(uiAllow: "", runtimeAllow: "", deny: "rm")
        let controller = PermissionController()
        let session = "sess-\(UUID().uuidString)"
        controller.present(makeRequest(session: session, command: "git status"))
        controller.decide(.allowAlways)

        let answer = try answerJSON(session: session, request: "req-1")
        XCTAssertEqual(answer["decision"] as? String, "always")
        XCTAssertEqual(answer["command_token"] as? String, "git")
        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatCommandAllowlist"] as? String, "git")

        let onceController = PermissionController()
        onceController.present(makeRequest(session: session, command: "npm test", requestID: "req-2"))
        onceController.decide(.allowOnce)
        let once = try answerJSON(session: session, request: "req-2")
        XCTAssertEqual(once["decision"] as? String, "once")
        XCTAssertNil(once["command_token"])
        let runtime = try json(at: directory.appendingPathComponent("app-config.json"))
        XCTAssertEqual(runtime["commandAllowList"] as? String, "git")
    }

    func testDesktopAlwaysStaysInSessionAndDoesNotWriteLists() throws {
        try seed(uiAllow: "ls", runtimeAllow: "ls", deny: "rm")
        let controller = PermissionController()
        let session = "sess-\(UUID().uuidString)"
        controller.present(PermissionRequest(
            requestID: "req-desk",
            provider: .qoder,
            sessionID: session,
            action: "shell",
            resources: ["git status"],
            agent: "",
            toolName: "Bash",
            toolInput: ["command": .string("git status")],
            arrivedAt: Date()
        ))
        controller.decide(.allowAlways)

        let answer = try answerJSON(session: session, request: "req-desk")
        XCTAssertEqual(answer["decision"] as? String, "always")
        XCTAssertEqual(answer["command_token"] as? String, "git")
        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatCommandAllowlist"] as? String, "ls")
        let runtime = try json(at: directory.appendingPathComponent("app-config.json"))
        XCTAssertEqual(runtime["commandAllowList"] as? String, "ls")
    }

    func testAllowAlwaysDowngradesWhenConfigIsMissing() throws {
        let controller = PermissionController()
        let session = "sess-\(UUID().uuidString)"
        controller.present(makeRequest(session: session, command: "git status"))
        controller.decide(.allowAlways)
        let answer = try answerJSON(session: session, request: "req-1")
        XCTAssertEqual(answer["decision"] as? String, "once")
        XCTAssertNil(answer["command_token"])
    }

    func testQoderHookWaitsForTerminalPermissionCard() {
        let body = HelperTemplate.body
        XCTAssertTrue(body.contains("\"permission_requested\""))
        XCTAssertTrue(body.contains("perm-"))
        XCTAssertTrue(body.contains("decision") && body.contains("\"always\""))
        XCTAssertTrue(body.contains("permission_notice"))
        XCTAssertFalse(body.contains("AUTO_MODES"))
        XCTAssertTrue(body.contains("\"behavior\": decision"))
        XCTAssertTrue(body.contains("updatedPermissions"))
        XCTAssertTrue(body.contains(":*"))
        XCTAssertTrue(body.contains("run_permission(payload, session_id, \"PreToolUse\")"))
        XCTAssertTrue(body.contains("remember_permission_hold"))
        XCTAssertTrue(body.contains("remember_session_allow"))
        XCTAssertTrue(body.contains("qoder_handles_approval"))
        XCTAssertTrue(body.contains("bypass_permissions"))
        XCTAssertTrue(body.contains("\"destination\": \"session\""))
        XCTAssertFalse(body.contains("persist_prefix_rule"))
    }

    // MARK: - 夹具

    private func seed(uiAllow: String, runtimeAllow: String, deny: String) throws {
        let ui: [String: Any] = [
            "app": [
                "configChatCommandAllowlist": uiAllow,
                "configChatCommandDenyList": deny,
                "configChatTerminalRunMode": "askEveryTime",
            ],
        ]
        let runtime: [String: Any] = [
            "commandAllowList": runtimeAllow,
            "commandDenyList": deny,
            "terminalRunMode": "askEveryTime",
        ]
        try write(ui, to: directory.appendingPathComponent("settings.json"))
        try write(runtime, to: directory.appendingPathComponent("app-config.json"))
    }

    private func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }

    private func json(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeRequest(session: String, command: String, requestID: String = "req-1") -> PermissionRequest {
        PermissionRequest(
            requestID: requestID,
            provider: .qoder_ide,
            sessionID: session,
            action: "shell",
            resources: [command],
            agent: "",
            toolName: "Bash",
            toolInput: ["command": .string(command)],
            arrivedAt: Date()
        )
    }

    private func answerJSON(session: String, request: String) throws -> [String: Any] {
        let url = AnswerDispatcher.permissionPath(sessionID: session, requestID: request)
        let data = try Data(contentsOf: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
