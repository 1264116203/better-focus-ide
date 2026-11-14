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

    private var updates: [[String: Any]] = []
    private var globalUpdates: [[String: Any]] = []

    override func tearDownWithError() throws {
        QoderCommandAllowList.locationsForTesting = nil
        QoderCommandAllowList.rpcForTesting = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// 语言服务替身：读出当前配置，收下整份更新和终端模式更新。
    private func installRPC() {
        updates = []
        globalUpdates = []
        QoderCommandAllowList.rpcForTesting = { method, params in
            switch method {
            case "config/getGlobal":
                return [
                    "terminalRunMode": "askEveryTime",
                    "webToolsExecutionMode": "enabledAskEveryTime",
                    "planModeRunConfig": "askEveryTime",
                    "commandAllowList": "keep-me",
                ]
            case "config/updateGlobal":
                self.globalUpdates.append(params)
                return ["success": true]
            case "config/updateGlobalTerminalRunMode":
                self.updates.append(params)
                return ["success": true]
            default:
                return nil
            }
        }
    }

    func testCommandTokenUsesFirstWordAndSkipsDenyList() {
        XCTAssertEqual(QoderCommandAllowList.token(from: "git status", denyList: "rm,sudo"), "git")
        XCTAssertEqual(QoderCommandAllowList.token(from: "git", denyList: ""), "git")
        XCTAssertNil(QoderCommandAllowList.token(from: "   ", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "a,b", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "\"quoted\"", denyList: ""))
        XCTAssertNil(QoderCommandAllowList.token(from: "rm -rf /tmp", denyList: "rm,sudo"))
        XCTAssertNil(QoderCommandAllowList.token(from: "Sudo ls", denyList: "rm,sudo"))
        XCTAssertEqual(QoderCommandAllowList.target(for: "SwitchMode"), .plan)
        XCTAssertEqual(QoderCommandAllowList.target(for: "CreatePlan"), .plan)
        XCTAssertEqual(QoderCommandAllowList.target(for: "WebFetch"), .web)
        XCTAssertEqual(QoderCommandAllowList.target(for: "Bash"), .terminal)
    }

    func testMergeKeepsOtherEntriesAndDoesNotDuplicate() {
        XCTAssertEqual(QoderCommandAllowList.merging("git, npm", token: "git"), "git,npm")
        XCTAssertEqual(QoderCommandAllowList.merging("", token: "git"), "git")
        XCTAssertEqual(QoderCommandAllowList.merging("npm", token: "git"), "npm,git")
    }

    func testRememberUpdatesLanguageServiceAndMirrorsSettings() throws {
        try seed(uiAllow: "ls", runtimeAllow: "keep-me", deny: "rm,sudo")
        try write([
            "config": [
                "chat": [
                    "terminalRunMode": "askEveryTime",
                    "webToolsMode": "Ask every time",
                    "commandAllowlist": "ls",
                ],
                "integrations": [
                    "planModeRunConfig": "Ask every time",
                    "questPlanModeRunConfig": "Auto-run",
                ],
            ],
        ], to: directory.appendingPathComponent("app.json"))
        installRPC()
        let outcome = QoderCommandAllowList.remember(command: "git status", provider: .qoder_ide)
        guard case .remembered(let token) = outcome else {
            return XCTFail("expected remembered, got \(outcome)")
        }
        XCTAssertEqual(token, "git")
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0]["terminalRunMode"] as? String, "fullAccess")
        XCTAssertEqual(globalUpdates.count, 1)
        XCTAssertEqual(globalUpdates[0]["terminalRunMode"] as? String, "fullAccess")
        XCTAssertEqual(globalUpdates[0]["webToolsExecutionMode"] as? String, "enabledAskEveryTime")
        XCTAssertEqual(globalUpdates[0]["planModeRunConfig"] as? String, "askEveryTime")
        XCTAssertEqual(globalUpdates[0]["commandAllowList"] as? String, "keep-me")

        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatCommandAllowlist"] as? String, "ls")
        XCTAssertEqual(app?["configChatTerminalRunMode"] as? String, "fullAccess")
        XCTAssertEqual(app?["configChatWebToolsMode"] as? String, "Ask every time")
        XCTAssertEqual(app?["configIntegrationsPlanModeRunConfig"] as? String, "Ask every time")
        let page = try json(at: directory.appendingPathComponent("app.json"))
        let chat = (page["config"] as? [String: Any])?["chat"] as? [String: Any]
        let integrations = (page["config"] as? [String: Any])?["integrations"] as? [String: Any]
        XCTAssertEqual(chat?["terminalRunMode"] as? String, "fullAccess")
        XCTAssertEqual(chat?["webToolsMode"] as? String, "Ask every time")
        XCTAssertEqual(chat?["commandAllowlist"] as? String, "ls")
        XCTAssertEqual(integrations?["planModeRunConfig"] as? String, "Ask every time")
        XCTAssertEqual(integrations?["questPlanModeRunConfig"] as? String, "Auto-run")

        let runtime = try json(at: directory.appendingPathComponent("app-config.json"))
        XCTAssertEqual(runtime["commandAllowList"] as? String, "keep-me")
    }

    func testRememberWebDoesNotChangePlanOrTerminal() throws {
        try seed(uiAllow: "ls", runtimeAllow: "keep-me", deny: "rm,sudo")
        try write([
            "config": [
                "chat": [
                    "terminalRunMode": "askEveryTime",
                    "webToolsMode": "Ask every time",
                ],
                "integrations": ["planModeRunConfig": "Ask every time"],
            ],
        ], to: directory.appendingPathComponent("app.json"))
        installRPC()
        let outcome = QoderCommandAllowList.remember(command: "", toolName: "WebSearch",
                                                     provider: .qoder_ide)
        guard case .remembered = outcome else {
            return XCTFail("expected remembered, got \(outcome)")
        }
        XCTAssertTrue(updates.isEmpty)
        XCTAssertEqual(globalUpdates[0]["webToolsExecutionMode"] as? String, "enabledAutoExecute")
        XCTAssertEqual(globalUpdates[0]["terminalRunMode"] as? String, "askEveryTime")
        XCTAssertEqual(globalUpdates[0]["planModeRunConfig"] as? String, "askEveryTime")

        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatWebToolsMode"] as? String, "Auto-execute")
        XCTAssertEqual(app?["configChatTerminalRunMode"] as? String, "askEveryTime")
        XCTAssertEqual(app?["configIntegrationsPlanModeRunConfig"] as? String, "Ask every time")
        let page = try json(at: directory.appendingPathComponent("app.json"))
        let chat = (page["config"] as? [String: Any])?["chat"] as? [String: Any]
        let integrations = (page["config"] as? [String: Any])?["integrations"] as? [String: Any]
        XCTAssertEqual(chat?["webToolsMode"] as? String, "Auto-execute")
        XCTAssertEqual(chat?["terminalRunMode"] as? String, "askEveryTime")
        XCTAssertEqual(integrations?["planModeRunConfig"] as? String, "Ask every time")
    }

    func testRememberWritesSettingsFileWhenRuntimeCacheIsMissing() throws {
        try seed(uiAllow: "", runtimeAllow: "", deny: "rm,sudo")
        installRPC()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("app-config.json"))
        let outcome = QoderCommandAllowList.remember(command: "git status", provider: .qoder_ide)
        guard case .remembered(let token) = outcome else {
            return XCTFail("expected remembered, got \(outcome)")
        }
        XCTAssertEqual(token, "git")
        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatTerminalRunMode"] as? String, "fullAccess")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("app-config.json").path))
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
        installRPC()
        let controller = PermissionController()
        let session = "sess-\(UUID().uuidString)"
        controller.present(makeRequest(session: session, command: "git status"))
        controller.decide(.allowAlways)

        let answer = try answerJSON(session: session, request: "req-1")
        XCTAssertEqual(answer["decision"] as? String, "always")
        XCTAssertEqual(answer["command_token"] as? String, "git")
        let ui = try json(at: directory.appendingPathComponent("settings.json"))
        let app = ui["app"] as? [String: Any]
        XCTAssertEqual(app?["configChatTerminalRunMode"] as? String, "fullAccess")

        let onceController = PermissionController()
        onceController.present(makeRequest(session: session, command: "npm test", requestID: "req-2"))
        onceController.decide(.allowOnce)
        let once = try answerJSON(session: session, request: "req-2")
        XCTAssertEqual(once["decision"] as? String, "once")
        XCTAssertNil(once["command_token"])
        let runtime = try json(at: directory.appendingPathComponent("app-config.json"))
        XCTAssertEqual(runtime["commandAllowList"] as? String, "")
        XCTAssertEqual(updates[0]["terminalRunMode"] as? String, "fullAccess")
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
        XCTAssertTrue(body.contains("def _card_permission"))
        XCTAssertTrue(body.contains("\"websearch\""))
        XCTAssertTrue(body.contains("\"webfetch\""))
        XCTAssertTrue(body.contains("\"switchmode\""))
        XCTAssertFalse(body.contains("\"createplan\""))
        XCTAssertTrue(body.contains("_permission_card_recent"))
        XCTAssertTrue(body.contains("_permission_notice_recent"))
        XCTAssertFalse(body.contains("AUTO_MODES"))
        XCTAssertTrue(body.contains("and _desktop_qoder()"))
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
        XCTAssertTrue(body.contains("\"jetbrains_plugin\": \"jetbrains_cn_plugin\""))
    }

    /// JetBrains 插件的「始终允许」写插件自己的语言服务，不写 Qoder IDE 的设置文件。
    func testJetBrainsAlwaysAllowUsesPluginServerAndSkipsIdeFiles() {
        QoderCommandAllowList.locationsForTesting = nil
        XCTAssertNil(QoderCommandAllowList.locations(for: .jetbrains_plugin))
        XCTAssertNil(QoderCommandAllowList.locations(for: .jetbrains_cn_plugin))
        XCTAssertTrue(QoderCommandAllowList.socketPath(for: .jetbrains_plugin)?
            .hasSuffix("/.qoder/shared_client/qoder.sock") == true)
        XCTAssertTrue(QoderCommandAllowList.socketPath(for: .jetbrains_cn_plugin)?
            .hasSuffix("/.qoder-cn/shared_client/qodercn.sock") == true)
        XCTAssertEqual(PermissionDecisionValue.allowAlways.buttonLabel(for: .jetbrains_plugin),
                       "始终允许")
        XCTAssertEqual(PermissionDecisionValue.allowAlways.buttonLabel(for: .jetbrains_cn_plugin),
                       "始终允许")

        QoderCommandAllowList.locationsForTesting = { provider in
            if provider == .jetbrains_plugin || provider == .jetbrains_cn_plugin { return nil }
            return (ui: self.directory.appendingPathComponent("settings.json"),
                    runtime: self.directory.appendingPathComponent("app-config.json"))
        }
        installRPC()
        let outcome = QoderCommandAllowList.remember(command: "git status",
                                                     toolName: "Bash",
                                                     provider: .jetbrains_plugin)
        guard case .remembered = outcome else {
            return XCTFail("expected remembered, got \(outcome)")
        }
        XCTAssertEqual(globalUpdates[0]["terminalRunMode"] as? String, "fullAccess")
        XCTAssertEqual(globalUpdates[0]["webToolsExecutionMode"] as? String, "enabledAskEveryTime")
        XCTAssertEqual(globalUpdates[0]["planModeRunConfig"] as? String, "askEveryTime")
        XCTAssertEqual(updates[0]["terminalRunMode"] as? String, "fullAccess")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("settings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("app.json").path))
    }

    // MARK: - 夹具

    private func seed(uiAllow: String, runtimeAllow: String, deny: String) throws {
        let ui: [String: Any] = [
            "app": [
                "configChatCommandAllowlist": uiAllow,
                "configChatCommandDenyList": deny,
                "configChatTerminalRunMode": "askEveryTime",
                "configChatWebToolsMode": "Ask every time",
                "configIntegrationsPlanModeRunConfig": "Ask every time",
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
