// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 「这道题要不要接到岛上」的判定，以及**让位信号在每条通道里都能被读懂**。
///
/// 背景：WorkBuddy IDE 在模型发起 `AskUserQuestion` 的瞬间就把自己的提问面板画出来了，
/// 不等 `PreToolUse` hook 返回。岛上再弹一张卡，同一道题要答两遍，而且 IDE 里那次选择
/// 会被 hook 的 deny 覆盖。修法是「GUI 宿主在前台就让位」，但让位是**跨进程协议**：
/// 只要有一个通道（hook / helper / 插件）不认识这个信号，用户就会看到「卡片不出现、
/// 工具却一直卡着」——比原来更糟。所以这里同时钉住判定与三条通道的契约。
final class QuestionTakeoverTests: XCTestCase {

    private func host(_ bundle: String, name: String = "", url: String = "") -> HostInfo {
        var info = HostInfo()
        info.bundle = bundle
        info.name = name
        info.url = url
        return info
    }

    // MARK: - 判定

    /// GUI 宿主正在前台：让位给它自己的提问面板。
    func testGUIHostInForegroundDefers() {
        XCTAssertFalse(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: "com.tencent.workbuddy.mac"))
    }

    /// 同一个宿主，但用户跑去别的 App 了：岛上接管，这才是灵动岛的价值。
    func testGUIHostInBackgroundTakesOver() {
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: "com.google.Chrome"))
    }

    /// 终端宿主恒接管：hook 的 deny 先于工具执行生效，终端那边不会出现第二份。
    func testTerminalHostAlwaysTakesOver() {
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.googlecode.iterm2", name: "iTerm"),
            frontmostBundle: "com.googlecode.iterm2"))
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.apple.Terminal", name: "Terminal"),
            frontmostBundle: "com.apple.Terminal"))
    }

    /// 浏览器会话（serve + Web UI）没有可对照的应用窗口，恒接管。
    func testBrowserHostAlwaysTakesOver() {
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("betterfocus.web", url: "http://127.0.0.1:4096/"),
            frontmostBundle: "betterfocus.web"))
    }

    /// 宿主身份未知（老插件、父进程链断了）：保持旧行为，照常接管。
    func testUnknownHostTakesOver() {
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(host: nil,
                                                      frontmostBundle: "com.apple.Safari"))
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(host: host(""),
                                                      frontmostBundle: "com.apple.Safari"))
    }

    /// 取不到前台应用时不敢让位：宁多多一张卡，也不能让问题悬空没人问。
    func testMissingFrontmostTakesOver() {
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: nil))
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: ""))
    }

    // MARK: - 让位信号

    /// 让位下标不能和已有语义撞车：-1 超时、-2 自定义、-3 多选。
    func testDeferIndexDoesNotCollide() {
        XCTAssertEqual(AnswerDispatcher.deferIndex, -4)
    }

    /// 三条能收到 `question_requested` 的通道都必须认得 `defer`。
    ///
    /// 漏一条的后果不是「多一张卡」，而是「卡片不出现、工具卡到超时」。
    func testEveryQuestionChannelUnderstandsDefer() {
        let channels: [(name: String, body: String)] = [
            ("HostHookTemplate", HostHookTemplate.body),
            ("HelperTemplate", HelperTemplate.body),
            ("OpenCodePlugin", PluginTemplate.body),
        ]
        for channel in channels {
            XCTAssertTrue(channel.body.contains("defer"),
                          "\(channel.name) 不认识让位信号")
            XCTAssertTrue(channel.body.contains("-4"),
                          "\(channel.name) 缺少让位下标兜底")
        }
    }

    /// hook 侧的让位必须**静默退出**：Claude 方言里「不打印任何决策」才是
    /// 交给宿主原生对话框，而不是伪造一个 allow。
    func testHookDefersSilently() {
        let body = HostHookTemplate.body
        XCTAssertTrue(body.contains(#"if found and index == -4:"#))
        XCTAssertTrue(body.contains(#"if data.get("defer") is True or index == -4:"#))
        // 让位分支紧跟 return，后面不能再走到 emit。
        let deferBranch = body.components(separatedBy: "if found and index == -4:").dropFirst()
        for branch in deferBranch {
            let head = branch.split(separator: "\n").prefix(4).joined(separator: "\n")
            XCTAssertTrue(head.contains("return"), "让位分支没有立即返回：\n\(head)")
        }
    }

    /// 插件侧的让位要交回原生 question 工具，而不是返回空答案。
    func testPluginHandsBackToNativeTool() {
        let body = PluginTemplate.body
        XCTAssertTrue(body.contains("return { deferred: true }"))
        XCTAssertTrue(body.contains("if (deferred) return original(input, context);"))
    }

    // MARK: - 权限通道上的提问

    /// 提问工具也会从权限通道冒一遍，但不能当权限横幅弹出来。
    func testQuestionToolIsNotAPermission() {
        XCTAssertTrue(PermissionRequest.isQuestionTool("AskUserQuestion"))
        XCTAssertTrue(PermissionRequest.isQuestionTool("ask_user_question"))
        XCTAssertTrue(PermissionRequest.isQuestionTool("question"))
        XCTAssertFalse(PermissionRequest.isQuestionTool("Bash"))
        XCTAssertFalse(PermissionRequest.isQuestionTool(""))
        // 从文案里抠工具名的那条路也要能命中。
        XCTAssertTrue(PermissionRequest.isQuestionTool(
            PermissionRequest.toolNameHint(from: "Claude needs your permission to use AskUserQuestion")))
    }
}
