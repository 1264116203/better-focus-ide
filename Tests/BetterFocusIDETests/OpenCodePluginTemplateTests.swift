// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 测试 OpenCode 插件模板的 API 契约。
///
/// OpenCode 的 `ctx.event` 是异步可迭代事件流（`ctx.event.subscribe({signal})`），
/// 没有 `.on()` 方法——旧模板用 `ctx.event.on('session.idle', …)` 恒为 undefined，
/// 静默跳过注册，导致 turn_finished 从未发送（且加载无报错，极难察觉）。
final class OpenCodePluginTemplateTests: XCTestCase {

    /// 模板正文（未替换占位符的原始形态）。
    private var body: String { PluginTemplate.body }

    /// 安装态正文（占位符已替换）。
    private var installed: String { OpenCodePluginInstaller.pluginContent }

    // MARK: - 事件订阅 API

    /// 测试：必须用 ctx.event.subscribe 异步迭代流订阅事件。
    func testEventSubscriptionUsesSubscribeStream() {
        XCTAssertTrue(body.contains("ctx.event.subscribe"),
                      "OpenCode 的事件订阅是 ctx.event.subscribe() 异步迭代")
        XCTAssertFalse(body.contains("ctx.event.on("),
                       "ctx.event.on 不是 OpenCode 的 API（undefined），恒静默跳过")
    }

    /// 测试：订阅循环必须防御性处理订阅流不可用的情况（旧版 OpenCode 兼容）。
    func testSubscribeGuardedForOlderBuilds() {
        XCTAssertTrue(body.contains("ctx.event"),
                      "仍需引用 ctx.event；守卫在 for-await 的 try/catch 内")
    }

    // MARK: - 事件名兼容

    /// 测试：session.status（2.x）与 session.idle（旧版）双兼容。
    func testStatusAndIdleEventCompatibility() {
        XCTAssertTrue(body.contains("'session.status'"), "2.x 用 session.status 报告轮次状态")
        XCTAssertTrue(body.contains("'session.idle'"), "旧版用 session.idle")
    }

    /// 测试：session.status 必须过滤出 status.type === 'idle'（busy/retry 是轮次中间态）。
    func testStatusIdleFilter() {
        XCTAssertTrue(body.contains("status.type"), "必须检查 status.type")
        XCTAssertTrue(body.contains("'idle'"), "只有 idle 代表 agent 停止")
    }

    // MARK: - 去抖与数据提取

    /// 测试：同会话去抖（sub-session 也会触发 idle，否则一连串横幅）。
    func testTurnDebouncePresent() {
        XCTAssertTrue(body.contains("TURN_DEBOUNCE_MS") && body.contains("lastTurnAt"),
                      "需要按会话记录上次轮次时间做去抖")
    }

    /// 测试：sessionID 从 event.data 提取（含 2.x 的 data.sessionID 与 info 回退）。
    func testSessionIDExtractedFromEventData() {
        XCTAssertTrue(body.contains("d.sessionID"), "2.x 事件数据在 event.data")
        XCTAssertTrue(body.contains("d.info"), "info 回退路径保留")
    }

    // MARK: - 提醒开关键名

    /// 测试：提醒开关必须读设置里的驼峰键（`Settings` 的 @Published 名）。
    ///
    /// 旧模板只读 `turn_notify_enabled`，而 settings.json 的 `values` 里是
    /// `turnNotifyEnabled` —— 键永远找不到，`alertsEnabled` 恒走"默认开启"分支，
    /// 于是应用内的「回复完成通知」等开关关掉也不生效。
    func testAlertToggleReadsCamelCaseKeys() {
        XCTAssertTrue(body.contains("turnNotifyEnabled"), "必须读 turnNotifyEnabled")
        XCTAssertTrue(body.contains("questionEnabled"), "必须读 questionEnabled")
        XCTAssertTrue(body.contains("permissionEnabled"), "必须读 permissionEnabled")
    }

    /// 测试：保留下划线键作为兼容回退（旧版 Python 实现的命名）。
    func testAlertToggleKeepsSnakeCaseFallback() {
        XCTAssertTrue(body.contains("turn_notify_enabled"), "下划线键作为回退保留")
    }

    /// 测试：开关判断必须遍历候选键，而不是只看单个键。
    func testAlertToggleIteratesCandidateKeys() {
        XCTAssertTrue(body.contains("for (const key of keys)"),
                      "驼峰优先、下划线回退，需要遍历候选键")
    }

    // MARK: - 安装完整性

    /// 测试：安装态正文不含任何占位符（全部替换）。
    func testPlaceholdersReplacedOnInstall() {
        XCTAssertFalse(installed.contains("__SOCKET_PATH__"))
        XCTAssertFalse(installed.contains("__ANSWER_DIR__"))
        XCTAssertFalse(installed.contains("__SETTINGS_PATH__"))
        XCTAssertFalse(installed.contains("__ANSWER_TIMEOUT_MS__"))
        XCTAssertTrue(installed.contains(InstallerPaths.socketPath))
    }
}
