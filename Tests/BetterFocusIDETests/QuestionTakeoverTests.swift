// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 「这道题要不要接到岛上」的判定，以及**让位信号在每条通道里都能被读懂**。
///
/// 背景：WorkBuddy IDE 在模型发起 `AskUserQuestion` 的瞬间就把自己的提问面板画出来了，
/// 不等 `PreToolUse` hook 返回。宿主那份面板 hook 拦不住，所以策略是**岛优先**：
/// 岛一定接管，宿主面板成为「看得见但不算数」的残影。`-4` 让位信号因此保留为
/// 可选策略（`Policy.deferToHostWhenFrontmost`），一旦启用，三条通道（hook / helper /
/// 插件）都必须读懂它——漏一条就是「卡片不出现、工具却一直卡着」。
/// 所以这里同时钉住两种策略与三条通道的契约。
final class QuestionTakeoverTests: XCTestCase {

    private func host(_ bundle: String, name: String = "", url: String = "") -> HostInfo {
        var info = HostInfo()
        info.bundle = bundle
        info.name = name
        info.url = url
        return info
    }

    // MARK: - 判定

    /// 默认策略：一律接管。
    ///
    /// 宿主那份面板是它在 hook 返回前自绘的，拦不住；让位只会让岛静默、而用户
    /// 在 IDE 里那次作答照样被 deny 丢掉。所以岛的卡必须是唯一有效入口。
    func testDefaultPolicyAlwaysTakesOver() {
        let cases: [(HostInfo?, String?)] = [
            (host("com.tencent.workbuddy.mac", name: "WorkBuddy"), "com.tencent.workbuddy.mac"),
            (host("com.tencent.workbuddy.mac", name: "WorkBuddy"), "com.google.Chrome"),
            (host("com.googlecode.iterm2", name: "iTerm"), "com.googlecode.iterm2"),
            (host("betterfocus.web", url: "http://127.0.0.1:4096/"), "com.apple.Safari"),
            (nil, "com.apple.Safari"),
            (host(""), "com.apple.Safari"),
        ]
        for (hostInfo, frontmost) in cases {
            XCTAssertTrue(QuestionTakeover.shouldTakeOver(host: hostInfo,
                                                          frontmostBundle: frontmost),
                          "默认策略下应一律接管：\(hostInfo?.bundle ?? "nil") / \(frontmost ?? "nil")")
        }
    }

    /// 可选策略（仅在实测确认某宿主的原生面板能自行作答后才启用）。
    func testDeferPolicyDefersOnlyForForegroundGUIHost() {
        let policy = QuestionTakeover.Policy.deferToHostWhenFrontmost
        // GUI 宿主正在前台：让位给它自己的提问面板。
        XCTAssertFalse(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: "com.tencent.workbuddy.mac", policy: policy))
        // 同一个宿主，但用户跑去别的 App 了：岛上接管。
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: "com.google.Chrome", policy: policy))
        // 终端宿主恒接管：hook 的 deny 先于工具执行生效，终端不会出现第二份。
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.googlecode.iterm2", name: "iTerm"),
            frontmostBundle: "com.googlecode.iterm2", policy: policy))
        // 浏览器会话（serve + Web UI）没有可对照的应用窗口，恒接管。
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("betterfocus.web", url: "http://127.0.0.1:4096/"),
            frontmostBundle: "betterfocus.web", policy: policy))
        // 宿主身份未知、取不到前台 App 时不敢让位。
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(host: nil,
                                                      frontmostBundle: "com.apple.Safari",
                                                      policy: policy))
        XCTAssertTrue(QuestionTakeover.shouldTakeOver(
            host: host("com.tencent.workbuddy.mac", name: "WorkBuddy"),
            frontmostBundle: nil, policy: policy))
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

    /// 作答一律走 `deny + reason`：`allow + updatedInput.answers` 那条代答
    /// 捷径试过、也撤了——宿主自己的面板关不掉不是我们要解决的问题，
    /// 岛只需要**尽快出现**（见启动器的 `-S`）。这里钉住「不再有按宿主
    /// 分叉的代答路径」，免得有人又把它请回来。
    func testAnswersAlwaysGoBackThroughDenyReason() {
        let body = HostHookTemplate.body
        XCTAssertFalse(body.contains("emit_native_answer"))
        XCTAssertFalse(body.contains("updatedInput"))
        XCTAssertTrue(body.contains(#"reason = ("The person answered on the BetterFocusIDE island. ""#))
        XCTAssertTrue(body.contains(#"emit("deny", reason, hook_event)"#))
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
