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

    // MARK: - 注册表

    /// Cursor 只注册观测型事件：权限类事件会强制 allow/deny，绝不碰。
    func testCursorRegistersObserveOnlyEvents() {
        XCTAssertEqual(CursorHookInstaller.events, ["stop", "sessionEnd"])
    }

    /// WorkBuddy 的提问必须挂在 PreToolUse + AskUserQuestion 上，
    /// 否则 hook 收不到 tool_input，卡片弹不出来。
    func testWorkBuddyRegistersQuestionAndLifecycle() {
        let events = WorkBuddyHookInstaller.specs.map(\.event)
        XCTAssertEqual(events, ["PreToolUse", "Notification", "PermissionRequest", "Stop", "SessionEnd"])
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
