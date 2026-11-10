// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 测试 Cursor / WorkBuddy 共用 hook 模板的生成契约。
///
/// 两个宿主的差异只在「事件方言」与「安装目标」，一旦安装器把占位符替换漏了，
/// 或者方言串了，hook 会在宿主侧静默失败（Cursor 那边甚至会阻塞工具调用），
/// 所以这里把关键不变量钉住。
final class HostHookTemplateTests: XCTestCase {

    // MARK: - 占位符替换

    /// 安装态正文不得残留任何占位符。
    func testNoPlaceholderLeftInInstalledHelper() {
        for content in [CursorHookInstaller.helperContent,
                        WorkBuddyHookInstaller.helperContent] {
            XCTAssertFalse(content.contains("__SOCKET_PATH__"))
            XCTAssertFalse(content.contains("__ANSWER_DIR__"))
            XCTAssertFalse(content.contains("__EVENT_STYLE__"))
            XCTAssertFalse(content.contains("__PROVIDER__"))
            XCTAssertFalse(content.contains("__HOST_BUNDLE__"))
            XCTAssertFalse(content.contains("__QUESTION_TIMEOUT__"))
        }
    }

    /// 方言与 provider 必须各就各位，不能互换。
    func testDialectAndProviderAreCorrect() {
        let cursor = CursorHookInstaller.helperContent
        XCTAssertTrue(cursor.contains("or \"cursor\""), "Cursor 侧方言未落到 cursor")
        XCTAssertTrue(cursor.contains("com.todesktop.230313mzl4w4u92"))
        XCTAssertFalse(cursor.contains("or \"claude\""), "Cursor 正文混入了 claude 方言")

        let workbuddy = WorkBuddyHookInstaller.helperContent
        XCTAssertTrue(workbuddy.contains("or \"claude\""), "WorkBuddy 侧方言未落到 claude")
        XCTAssertTrue(workbuddy.contains("com.tencent.workbuddy.mac"))
        XCTAssertFalse(workbuddy.contains("or \"cursor\""), "WorkBuddy 正文混入了 cursor 方言")
    }

    // MARK: - 提醒开关键名

    /// 提醒开关必须读设置里的驼峰键（`Settings` 的 @Published 名）。
    ///
    /// settings.json 的 `values` 里是 `turnNotifyEnabled`，旧模板只读
    /// `turn_notify_enabled` → 键永远找不到 → 恒"默认开启"，关掉也不生效。
    func testAlertToggleReadsCamelCaseKeys() {
        for content in [CursorHookInstaller.helperContent,
                        WorkBuddyHookInstaller.helperContent] {
            XCTAssertTrue(content.contains("turnNotifyEnabled"))
            XCTAssertTrue(content.contains("questionEnabled"))
            XCTAssertTrue(content.contains("permissionEnabled"))
            // 下划线键作为兼容回退保留
            XCTAssertTrue(content.contains("turn_notify_enabled"))
        }
    }

    /// 正文必须能被 Python 解析（语法错误会让所有事件静默丢失）。
    func testHelperCompilesAsPython() throws {
        let dir = NSTemporaryDirectory() + "bf-hook-syntax-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for (name, content) in [("cursor.py", CursorHookInstaller.helperContent),
                                ("workbuddy.py", WorkBuddyHookInstaller.helperContent)] {
            let path = dir + "/" + name
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)", path]
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(name) 语法检查失败")
        }
    }

    // MARK: - 出卡延迟

    /// 「岛先出现」不是靠猜，是靠这条链上的毫秒数：宿主自己的提问面板在模型
    /// 吐出 `tool_use` 的瞬间就画好了，岛要抢在用户动手之前被看见，只能把
    /// hook 启动那段压到极限。三个不变量：
    ///
    /// - 启动器带 `-S`：跳过 site 初始化（实测 273ms → 33ms）；
    /// - 正文顶部不 import subprocess：它会拖进 threading/enum/functools（~100ms），
    ///   只有真要爬进程祖先链时才付这个钱；
    /// - 烘焙了宿主身份的 GUI 宿主直接用它，不爬链（爬链 ~55ms/次，含多次 `ps`）。
    func testCardPathKeepsHookStartupCheap() {
        XCTAssertTrue(HookInstallerSupport.scriptContent().contains(#"exec "$PYTHON" -S"#))
        XCTAssertTrue(QoderHookInstaller.scriptContent.contains(#"exec "$PYTHON" -S"#))
        XCTAssertTrue(QoderCnHookInstaller.scriptContent.contains(#"exec "$PYTHON" -S"#))

        let body = HostHookTemplate.body
        XCTAssertFalse(body.contains("import subprocess\n"), "subprocess 又回到顶部导入了")
        XCTAssertTrue(body.contains("import subprocess  #"), "host_app 里没有现用现导入")
        XCTAssertTrue(body.contains("if HOST_BUNDLE or HOST_NAME:"), "GUI 宿主又开始爬进程祖先链了")
    }

    // MARK: - 提问通道

    /// 提问必须**先于**权限门分发，而且不看事件族。
    ///
    /// 这是「岛先出现」的全部技术含量：`PermissionRequest` 上平台正等我们的答复，
    /// 此时宿主还没画出自己那份问卷；而 `PreToolUse` 是 fire-and-forget，平台不等。
    /// 一旦把提问塞回权限分支里（旧做法），它就会被「权限提醒开关」和 auto 档的
    /// `return` 连坐——岛连事件都收不到，宿主顺手弹自己的面板。
    func testQuestionDispatchPrecedesPermissionGate() throws {
        let body = HostHookTemplate.body
        let question = try XCTUnwrap(body.range(of: "if looks_like_question(payload, tool_name):"))
        let gate = try XCTUnwrap(body.range(of: #"if event in ("Notification", "PermissionRequest"):"#))
        XCTAssertLessThan(question.lowerBound, gate.lowerBound, "提问分发又被放回权限门之后了")

        // 通道不同，退场的语义也不同：PermissionRequest 交给宿主去问，PreToolUse 不干预。
        XCTAssertTrue(body.contains("def host_decides(hook_event):"))
        XCTAssertTrue(body.contains(#"return "ask" if hook_event == "PermissionRequest" else "allow""#))
        // 同一个提问会从两条通道各来一次，去重必须按问题内容，而不是载荷里不一定存在的 id。
        XCTAssertTrue(body.contains(#""q-" + "_".join"#))
        // 事件里带上通道标记，日志才看得出是谁先到。
        XCTAssertTrue(body.contains(#""channel": hook_event"#))
    }

    /// 宿主弹面板的瞬间只发一条 Notification（载荷里**没有题面**），
    /// 而 PreToolUse 要等用户答完才来——实测 18:10:09 收到通知、18:11:02
    /// 才收到 PreToolUse，中间那 52 秒就是用户在 IDE 里作答的时间。
    ///
    /// 所以「岛先出现」唯一能站住的地方是那条 Notification：从转录里捞出
    /// 题面先出卡；等 PreToolUse 真到了，把岛上已有的答案直接回灌。
    func testNotificationPreemptsHostPanel() throws {
        let body = HostHookTemplate.body

        // 1) 预取分支必须在提问分发之前，否则 Notification 会先掉进权限门。
        let preview = try XCTUnwrap(body.range(of: "if event == \"Notification\" and not looks_like_question"))
        let question = try XCTUnwrap(body.range(of: "if looks_like_question(payload, tool_name):"))
        XCTAssertLessThan(preview.lowerBound, question.lowerBound, "预取分支被放到提问分发之后了")

        // 2) 题面来自转录尾部，而不是载荷。
        XCTAssertTrue(body.contains("def pending_question(payload):"))
        XCTAssertTrue(body.contains(#"payload.get("transcript_path")"#))
        XCTAssertTrue(body.contains("def _collect_tool_blocks(node, uses, results):"))

        // 3) 预取只出卡、不作答：通道标成 Notification，发完就退出。
        XCTAssertTrue(body.contains("def preview_question(session_id, payload, questions, tool_use_id):"))
        XCTAssertTrue(body.contains(#""channel": "Notification""#))

        // 4) 两条通道必须算出同一个 request id（tool_use_id），答案文件才对得上。
        XCTAssertTrue(body.contains(#"or payload.get("call_id")"#))

        // 5) PreToolUse 先看岛上是否已经答过；答过就直接回灌，不再问第二遍。
        XCTAssertTrue(body.contains("questions[0][\"id\"], 0)"))
    }

    // MARK: - 注册表

    /// Cursor 的权限接 Shell、MCP，以及只匹配 Delete 的 preToolUse。
    func testCursorRegistersObserveOnlyEvents() {
        XCTAssertEqual(CursorHookInstaller.events, [
            "beforeSubmitPrompt", "stop", "sessionEnd",
            "subagentStop", "preCompact",
            "beforeShellExecution", "beforeMCPExecution",
            "preToolUse",
        ])
        let merged = CursorHookInstaller.mergedHooks([:])
        let pre = (merged["preToolUse"] as? [[String: Any]])?.first
        XCTAssertEqual(pre?["matcher"] as? String, "Delete")
        let shell = (merged["beforeShellExecution"] as? [[String: Any]])?.first
        XCTAssertNil(shell?["matcher"])
        let cursor = CursorHookInstaller.helperContent
        XCTAssertTrue(cursor.contains(#"{"permission": "ask"}"#))
        XCTAssertFalse(cursor.contains("beforeReadFile"))
    }

    /// WorkBuddy 的提问必须挂在 PreToolUse + AskUserQuestion 上，
    /// 否则 hook 收不到 tool_input，卡片弹不出来。
    func testWorkBuddyRegistersQuestionAndLifecycle() {
        let events = WorkBuddyHookInstaller.specs.map(\.event)
        XCTAssertEqual(events, ["PreToolUse", "Notification", "PermissionRequest",
                               "PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd",
                               "StopFailure", "PermissionDenied",
                               "SubagentStop", "PostCompact", "Elicitation"])
        let question = WorkBuddyHookInstaller.specs.first { $0.event == "PreToolUse" }
        XCTAssertEqual(question?.matcher, "AskUserQuestion")
        // Stop / SessionEnd 不带 matcher。
        XCTAssertNil(WorkBuddyHookInstaller.specs.first { $0.event == "Stop" }?.matcher)
    }

    // MARK: - 权限标题推断

    /// Notification 类权限提醒没有 tool_name，需从文案里抠出工具名。
    func testToolNameHintFromNotificationMessage() {
        let hint = PermissionRequest.toolNameHint(from: "Claude needs your permission to use Bash")
        XCTAssertEqual(hint, "Bash")
        XCTAssertEqual(PermissionRequest.actionFromToolName(hint), "shell")
        XCTAssertEqual(PermissionRequest.actionLabel("shell"), "终端命令")
    }

    /// 认不出来的文案保持空串，标题回落到「操作」而不是瞎猜。
    func testToolNameHintFallsBackToEmpty() {
        XCTAssertEqual(PermissionRequest.toolNameHint(from: ""), "")
        XCTAssertEqual(PermissionRequest.toolNameHint(from: "Waiting for your input"), "")
        XCTAssertEqual(PermissionRequest.actionLabel(""), "操作")
    }
}
