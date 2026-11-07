// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 新接入宿主（Claude Code / Codex / Trae / Trae CN / Kimi / Qoder CN）的安装契约。
///
/// 这几家的验证成本很高：写坏一份 `settings.json` 或 `config.toml`，宿主会**整份**
/// 配置加载失败（不是「hook 不生效」而是「IDE 打不开」）。所以这里把三类不变量钉死：
///
/// 1. **只动自己的条目**，其余分组、其余字段原样保留；
/// 2. **幂等**，重复安装不追加第二个分组/区块；
/// 3. **方言与事件名对齐宿主**——尤其 Trae 的 `Notification` matcher 匹配的是
///    `notification_type`、Kimi 的 `[[hooks]]` 只认 4 个字段，这两处错了会静默失效。
final class HostAdapterTests: XCTestCase {

    // MARK: - JSON matcher 分组（Claude Code / Trae）

    /// 合并只增我们的分组，别人的 hook 与顶层字段一个都不能少。
    func testMergeKeepsForeignHooksAndFields() {
        let foreign: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "echo mine"]]],
                ],
                "UserPromptSubmit": [
                    ["hooks": [["type": "command", "command": "echo other"]]],
                ],
            ],
        ]
        let merged = HookGroupInstaller.mergedHooks(
            foreign["hooks"] as! [String: Any],
            specs: ClaudeCodeHookInstaller.specs,
            scriptPath: "/tmp/betterfocus-notify.sh")

        // 别人的两条都还在。
        let preToolUse = merged["PreToolUse"] as! [[String: Any]]
        XCTAssertTrue(preToolUse.contains { ($0["matcher"] as? String) == "Bash" })
        XCTAssertEqual((merged["UserPromptSubmit"] as! [[String: Any]]).count, 1)
        // 我们的分组也进来了。
        XCTAssertTrue(preToolUse.contains {
            HookGroupInstaller.isOurGroup($0, scriptPath: "/tmp/betterfocus-notify.sh")
        })
    }

    /// 重复安装幂等：同一事件下我们的分组永远只有一个。
    func testMergeIsIdempotent() {
        var hooks: [String: Any] = [:]
        for _ in 0..<3 {
            hooks = HookGroupInstaller.mergedHooks(
                hooks, specs: ClaudeCodeHookInstaller.specs,
                scriptPath: "/tmp/betterfocus-notify.sh")
        }
        for spec in ClaudeCodeHookInstaller.specs {
            let groups = hooks[spec.event] as? [[String: Any]] ?? []
            let ours = groups.filter {
                HookGroupInstaller.isOurGroup($0, scriptPath: "/tmp/betterfocus-notify.sh")
            }
            XCTAssertEqual(ours.count, 1, "\(spec.event) 出现了 \(ours.count) 个我们的分组")
        }
    }

    /// 卸载只剔除我们的分组，剔空的事件键要一并消失（别留 `"Stop": []`）。
    func testRemovalDropsOnlyOurGroups() {
        let withOurs = HookGroupInstaller.mergedHooks(
            ["Stop": [["hooks": [["type": "command", "command": "echo mine"]]]]],
            specs: ClaudeCodeHookInstaller.specs,
            scriptPath: "/tmp/betterfocus-notify.sh")
        let cleaned = HookGroupInstaller.hooksAfterRemoval(
            withOurs, scriptPath: "/tmp/betterfocus-notify.sh")
        XCTAssertEqual((cleaned["Stop"] as? [[String: Any]])?.count, 1, "别人的 Stop hook 被误删")
        XCTAssertNil(cleaned["SessionEnd"], "我们独占的事件应整键移除")
    }

    /// 无 marker、但有 `hooks` 数组且 command 指向我们的脚本 —— 这种历史分组
    /// （早期版本写的，或 Qoder CN 装进了英文版配置）必须被认出来并清掉。
    ///
    /// 认不出来的后果不是「多一个分组」：每个 Stop 会调用两个 hook，各发一条
    /// turn_finished，人在一次任务结束时收到两条「回复完成」。
    func testQoderMergeDedupesMarkerlessLegacyGroup() {
        let legacy: [String: Any] = [
            "matcher": "*",
            "hooks": [[
                "type": "command",
                "command": "/Users/someone/.qoder-cn/hooks/betterfocus-notify.sh",
                "timeout": 5,
            ]],
        ]
        let foreign: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": "echo someone-else"]],
        ]
        let hooks: [String: Any] = ["Stop": [legacy, foreign]]

        let merged = QoderHookInstaller.mergedHooks(hooks)
        let groups = merged["Stop"] as? [[String: Any]] ?? []

        let ours = groups.filter { group in
            guard let entries = group["hooks"] as? [[String: Any]] else { return false }
            return entries.contains {
                ($0["command"] as? String)?.contains("betterfocus-notify.sh") == true
            }
        }
        XCTAssertEqual(ours.count, 1, "遗留的无 marker 分组没被清掉，Stop 会触发两次通知")
        XCTAssertTrue(ours.first?["_betterfocus_marker"] as? String == QoderHookInstaller.marker,
                      "存活的那份应带 marker，即本次写入的新分组")
        XCTAssertTrue(groups.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains {
                ($0["command"] as? String) == "echo someone-else"
            } == true
        }, "别人的 hook 被误删")
    }

    /// 重复安装后每个事件下我们的分组恒为一个（幂等 + 去重）。
    func testQoderMergeIsIdempotent() {
        var hooks: [String: Any] = [:]
        for _ in 0..<3 {
            hooks = QoderHookInstaller.mergedHooks(hooks)
        }
        for event in ["PreToolUse", "PermissionRequest", "SessionEnd", "Stop"] {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let ours = groups.filter { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return false }
                return entries.contains {
                    ($0["command"] as? String)?.contains("betterfocus-notify.sh") == true
                }
            }
            XCTAssertEqual(ours.count, 1, "\(event) 出现了 \(ours.count) 个我们的分组")
        }
    }

    /// `~/.qoder-cn` 链到 `~/.qoder` 时算同一个安装，不该被当成「装了 CN 版」。
    ///
    /// 判错的后果：CN 安装器把英文版的注册改写成带 `BETTERFOCUS_VARIANT=cn`
    /// 的脚本，此后英文版的每条通知都被记成「Qoder CN」。
    func testSymlinkedHostDirectoryIsNotADistinctInstall() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bf-symlink-\(UUID().uuidString)")
        let real = root.appendingPathComponent("qoder")
        let link = root.appendingPathComponent("qoder-cn")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: real.path)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(InstallerPaths.hostDirectoryIsDistinct(real.path, from: "/somewhere/else"),
                      "普通目录应算独立安装")
        XCTAssertFalse(InstallerPaths.hostDirectoryIsDistinct(link.path, from: real.path),
                       "软链指向同一目录时不该被当成独立安装")
    }

    /// Trae 的 `Notification` matcher 匹配的是 notification_type，不是工具名。
    /// 写成工具名会让权限提醒永远不触发。任务完成是 `idle_prompt`，漏了就没有完成通知。
    func testTraeNotificationMatcherTargetsNotificationType() {
        let notification = TraeHookInstaller.specs.first { $0.event == "Notification" }
        XCTAssertEqual(notification?.matcher,
                       "permission_prompt|ask_user_question|document_review|browser_interaction|idle_prompt")
        let body = TraeHookInstaller.helperContent(.international)
        XCTAssertTrue(body.contains("kind == \"idle_prompt\""))
        XCTAssertTrue(body.contains("emit_turn_finished(session_id, payload)"))
        XCTAssertTrue(TraeHookInstaller.specs.contains { $0.event == "UserPromptSubmit" })
    }

    /// Trae 只有六类事件，没有 SessionEnd——注册了也不会被调用，别假装有。
    func testTraeHasNoSessionEnd() {
        XCTAssertFalse(TraeHookInstaller.specs.contains { $0.event == "SessionEnd" })
        XCTAssertTrue(TraeHookInstaller.specs.contains { $0.event == "Stop" })
    }

    /// 进度卡靠 PostToolUse 转发 TodoWrite。Trae 的工具枚举没有这项，
    /// 2026-11-07 实测也不会发事件。挂上只会空转。
    func testTraeDoesNotRegisterTodoProgress() {
        XCTAssertFalse(TraeHookInstaller.specs.contains { $0.event == "PostToolUse" })
    }

    // MARK: - TOML 受管区块（Kimi / Codex）

    /// 区块插入 → 替换 → 移除的完整回路，且界标之外一个字符都不变。
    func testManagedTOMLRoundTrip() {
        let original = """
        model = "kimi-k2"

        [tui]
        theme = "dark"
        """
        let first = ManagedTOML.applying(ManagedTOML.block(["notify = [\"/bin/bash\", \"/tmp/a.sh\"]"]),
                                         to: original)
        XCTAssertTrue(first.contains(original.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(ManagedTOML.hasBlock(in: first))

        // 二次应用：替换而不是追加。
        let second = ManagedTOML.applying(ManagedTOML.block(["notify = [\"/bin/bash\", \"/tmp/b.sh\"]"]),
                                          to: first)
        XCTAssertEqual(second.components(separatedBy: ManagedTOML.beginMarker).count, 2,
                       "受管区块被追加了第二份")
        XCTAssertTrue(second.contains("/tmp/b.sh"))
        XCTAssertFalse(second.contains("/tmp/a.sh"))

        // 移除后回到原样（允许空行归一化）。
        let stripped = ManagedTOML.removing(from: second)
        XCTAssertFalse(stripped.contains(ManagedTOML.beginMarker))
        XCTAssertTrue(stripped.contains("model = \"kimi-k2\""))
        XCTAssertTrue(stripped.contains("theme = \"dark\""))
    }

    /// 界标外的同名键必须被识别成冲突：TOML 不允许重复键，追加会让整份配置失效。
    func testManagedTOMLDetectsForeignKey() {
        let text = """
        # my own notifier
        notify = ["/usr/local/bin/mine.sh"]
        """
        XCTAssertTrue(ManagedTOML.hasKeyOutsideBlock("notify", in: text))
        let oursOnly = ManagedTOML.applying(ManagedTOML.block(["notify = [\"/bin/bash\", \"/tmp/x.sh\"]"]),
                                            to: "")
        XCTAssertFalse(ManagedTOML.hasKeyOutsideBlock("notify", in: oursOnly),
                       "自己的区块不该被当成外来键")
    }

    /// Kimi 的 `[[hooks]]` 只允许 event/matcher/command/timeout 四个字段，
    /// 多写任何一个整份 config.toml 都加载失败。
    func testKimiBlockUsesOnlyAllowedFields() {
        let allowed: Set<String> = ["event", "matcher", "command", "timeout"]
        for line in KimiHookInstaller.tomlBlock.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "[[hooks]]" { continue }
            let key = trimmed.split(separator: "=").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            XCTAssertTrue(allowed.contains(key), "Kimi 不认识的字段：\(key)")
        }
        // 每条事件都要有对应的表。
        let tables = KimiHookInstaller.tomlBlock.components(separatedBy: "[[hooks]]").count - 1
        XCTAssertEqual(tables, KimiHookInstaller.specs.count)
        // 超时上限 600s，超了会让配置加载失败。
        for line in KimiHookInstaller.tomlBlock.split(separator: "\n") where line.contains("timeout") {
            let value = Int(line.split(separator: "=").last?
                .trimmingCharacters(in: .whitespaces) ?? "") ?? -1
            XCTAssertTrue(value > 0 && value <= 600, "timeout 越界：\(value)")
        }
    }

    /// Codex 的 notify 必须是「程序 + 参数」的字符串数组。
    func testCodexNotifyIsWellFormed() {
        let block = CodexHookInstaller.tomlBlock
        XCTAssertTrue(block.hasPrefix(ManagedTOML.beginMarker) == false || block.contains("notify = ["))
        XCTAssertTrue(block.contains("notify = [\"/bin/bash\""))
        XCTAssertTrue(block.contains(CodexHookInstaller.scriptPath))
        XCTAssertEqual(block.components(separatedBy: "notify =").count, 2)
    }

    // MARK: - Python 正文

    /// 六个新宿主的正文都必须能被 Python 解析。语法错误 = 全部事件静默丢失。
    func testAllHelperBodiesCompileAsPython() throws {
        let cases: [(String, String)] = [
            ("claude", ClaudeCodeHookInstaller.helperContent),
            ("codex", CodexHookInstaller.helperContent),
            ("trae-cn", TraeHookInstaller.helperContent(.cn)),
            ("trae", TraeHookInstaller.helperContent(.international)),
            ("kimi", KimiHookInstaller.helperContent),
            ("qoder-cn", QoderCnHookInstaller.installer.helperContent),
            ("copilot", CopilotHookInstaller.helperContent),
        ]
        let dir = NSTemporaryDirectory() + "bf-hook-syntax-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        for (name, content) in cases {
            // 只查真正的占位符；正文里有 `__main__` 这类合法双下划线。
            for placeholder in ["__SOCKET_PATH__", "__ANSWER_DIR__", "__SETTINGS_PATH__",
                                "__EVENT_STYLE__", "__PROVIDER__", "__HOST_BUNDLE__",
                                "__QUESTION_TIMEOUT__", "__PERMISSION_TIMEOUT__"] {
                XCTAssertFalse(content.contains(placeholder), "\(name) 残留了 \(placeholder)")
            }
            let path = dir + "/" + name + ".py"
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c",
                                 "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)",
                                 path]
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(name) 语法检查失败")
        }
    }

    /// 启动器必须把命令行参数转交给 Python：Codex 的 payload 只从 argv 来，
    /// 少了 `"$@"` 这条链路会「装上但永远收不到事件」。
    func testLauncherForwardsArguments() {
        XCTAssertTrue(HookInstallerSupport.scriptContent().contains("betterfocus-hook.py\" \"$@\""))
        XCTAssertTrue(QoderCnHookInstaller.scriptContent.contains("\"$@\""))
    }

    /// Codex 的 notify 走 argv，hooks.json 走 stdin。有 argv 时必须先返回，
    /// 不能落到后面的 stdin 读取——notify 不关 stdin，读下去会把终端卡死。
    func testCodexNotifyReadsArgvBeforeStdin() {
        let body = CodexHookInstaller.helperContent
        XCTAssertTrue(body.contains("EVENT_STYLE == \"codex\" and len(sys.argv) > 1"))
        XCTAssertTrue(body.contains("json.loads(sys.argv[1])"))
        let readPayload = body.components(separatedBy: "def read_payload").last ?? ""
        let codexIndex = readPayload.range(of: "EVENT_STYLE == \"codex\"")?.lowerBound
        let stdinIndex = readPayload.range(of: "json.load(sys.stdin)")?.lowerBound
        XCTAssertNotNil(codexIndex)
        XCTAssertNotNil(stdinIndex)
        if let codexIndex, let stdinIndex {
            XCTAssertTrue(codexIndex < stdinIndex, "argv 分支必须早于 stdin 读取")
        }
        // notify 命中后直接返回；hooks.json 的载荷继续走 Claude 方言。
        XCTAssertTrue(body.contains("payload.get(\"type\") == \"agent-turn-complete\""))
        XCTAssertFalse(body.contains("Codex 只发 agent-turn-complete"))
    }

    /// hooks.json 的事件面以官方文档为准：SessionEnd 超时不得超过 3 秒，
    /// 没有 Notification，待办工具 update_plan 也先不挂。
    func testCodexHooksStayInsideDocumentedLimits() {
        let events = CodexHookInstaller.specs.map(\.event)
        XCTAssertEqual(events, ["PermissionRequest", "UserPromptSubmit",
                                "Stop", "SessionEnd", "SubagentStop", "PostCompact"])
        let sessionEnd = CodexHookInstaller.specs.first { $0.event == "SessionEnd" }
        XCTAssertEqual(sessionEnd?.timeout, 3)
        for spec in CodexHookInstaller.specs where spec.event != "SessionEnd" {
            XCTAssertLessThanOrEqual(spec.timeout, 600)
        }
    }

    // MARK: - 终端标注与跳转

    /// CLI 产品标成「产品（终端）」；GUI 宿主保持原样。
    func testCLILabelsNameTheirTerminal() {
        XCTAssertEqual(AgentProvider.label(provider: .qoder_cli, hostName: "Warp",
                                           bundleID: "dev.warp.Warp-Stable"),
                       "Qoder CLI（Warp）")
        XCTAssertEqual(AgentProvider.label(provider: .qoder_cn_cli, hostName: "iTerm2",
                                           bundleID: "com.googlecode.iterm2"),
                       "Qoder CN CLI（iTerm）")
        XCTAssertEqual(AgentProvider.label(provider: .claude_code, hostName: "Ghostty",
                                           bundleID: "com.mitchellh.ghostty"),
                       "Claude Code（Ghostty）")
        // 认不出终端：退回产品名，不能拼出「Claude Code（）」这种残句。
        XCTAssertEqual(AgentProvider.label(provider: .claude_code, hostName: "", bundleID: ""),
                       "Claude Code")
        // 祖先进程是别的宿主（IDE / 另一个 agent）时，不能把对方的名称当成来源。
        XCTAssertEqual(AgentProvider.label(provider: .qoder_cn_cli, hostName: "WorkBuddy",
                                           bundleID: "com.tencent.workbuddy.mac"),
                       "Qoder CN CLI")
        // GUI 宿主不受影响。
        XCTAssertEqual(AgentProvider.label(provider: .trae_cn, hostName: "Trae CN",
                                           bundleID: "cn.trae.app"), "Trae CN")
    }

    /// GUI 宿主也要防「祖先链报的是别人」：实测在 WorkBuddy 的 shell 里触发
    /// Trae CN 的 hook，卡片曾写成 "WorkBuddy 回复完成"。bundle 明确属于另一个
    /// 应用家族时只写产品名；bundle 认不出（第三方终端 / 未知应用）时仍信 host.name。
    func testForeignHostBundleDoesNotHijackProductName() {
        XCTAssertEqual(AgentProvider.label(provider: .trae_cn,
                                           hostName: "WorkBuddy",
                                           bundleID: "com.tencent.workbuddy.mac"),
                       "Trae CN")
        XCTAssertEqual(AgentProvider.label(provider: .cursor,
                                           hostName: "Trae CN",
                                           bundleID: "cn.trae.app"),
                       "Cursor")
        // JetBrains 插件必须保留 host.name，否则 "IntelliJ IDEA" 会退化成 "Qoder"。
        XCTAssertEqual(AgentProvider.label(provider: .jetbrains_plugin,
                                           hostName: "IntelliJ IDEA",
                                           bundleID: "com.jetbrains.intellij"),
                       "IntelliJ IDEA")
        // 亲缘 bundle 照常使用 host.name（大小写/别名不影响归属判定）。
        XCTAssertEqual(AgentProvider.label(provider: .trae,
                                           hostName: "Trae",
                                           bundleID: "com.trae.app"), "Trae")
    }

    /// 图标身份必须跟着名字走：不能「文字写 Trae CN、图标画 WorkBuddy」。
    func testIconIdentityMatchesLabel() {
        // GUI 宿主被别的应用「冒名」时，图标回到产品自己的 bundle。
        let hijacked = AgentProvider.iconIdentity(provider: .trae_cn,
                                                 hostName: "WorkBuddy",
                                                 bundleID: "com.tencent.workbuddy.mac")
        XCTAssertEqual(hijacked.name, "Trae CN")
        XCTAssertEqual(hijacked.bundle, "cn.trae.app")
        // 正常情况原样透传 host，图标仍是 host（GUI 宿主 host == 产品）。
        let normal = AgentProvider.iconIdentity(provider: .cursor,
                                               hostName: "Cursor",
                                               bundleID: "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(normal.bundle, "com.todesktop.230313mzl4w4u92")
        // CLI 宿主永远用终端身份，不走产品那套。
        let cli = AgentProvider.iconIdentity(provider: .claude_code,
                                            hostName: "Warp",
                                            bundleID: "dev.warp.Warp-Stable")
        XCTAssertEqual(cli.name, "Warp")
        XCTAssertEqual(cli.bundle, "dev.warp.Warp-Stable")
    }

    /// CLI 宿主的跳转目标是它所在的终端，不是「无处可跳」。
    func testCLIJumpsBackToItsTerminal() {
        let host = HostInfo(from: ["bundle": .string("dev.warp.Warp-Stable"),
                                   "name": .string("Warp")],
                            cwd: "/tmp/proj")
        let target = IDELauncher.target(for: "qoder_cli", host: host)
        XCTAssertEqual(target?.bundles, ["dev.warp.Warp-Stable"])
        XCTAssertEqual(target?.names, ["Warp"])
    }

    /// ChatGPT.app 沿用 Codex 的 bundle id。点桌面版通知应唤起 ChatGPT，
    /// 终端里的会话仍唤起那个终端。
    func testChatGPTAppJumpLeavesTerminalSessionsAlone() {
        XCTAssertEqual(AgentProvider.codex.displayName, "ChatGPT")
        let app = HostInfo(from: ["bundle": .string("com.openai.codex"),
                                  "name": .string("ChatGPT")],
                           cwd: "/tmp/proj")
        let appTarget = IDELauncher.target(for: "codex", host: app)
        XCTAssertEqual(appTarget?.bundles, ["com.openai.codex"])
        XCTAssertEqual(appTarget?.names, ["ChatGPT"])

        let terminal = HostInfo(from: ["bundle": .string("com.apple.Terminal"),
                                       "name": .string("Terminal")],
                                cwd: "/tmp/proj")
        let terminalTarget = IDELauncher.target(for: "codex", host: terminal)
        XCTAssertEqual(terminalTarget?.bundles, ["com.apple.Terminal"])
        XCTAssertEqual(terminalTarget?.names, ["Terminal"])
    }

    /// GitHub Copilot.app 的完成通知必须唤起这个桌面应用。
    /// 终端里的 CLI 会话仍唤起那个终端，不能被桌面版 bundle 盖掉。
    func testCopilotAppJumpLeavesTerminalSessionsAlone() {
        let app = HostInfo(from: ["bundle": .string("com.github.githubapp"),
                                  "name": .string("GitHub Copilot"),
                                  "path": .string("/Users/bit_tiger/Applications/GitHub Copilot.app")],
                           cwd: "/tmp/proj")
        let appTarget = IDELauncher.target(for: "copilot", host: app)
        XCTAssertEqual(appTarget?.bundles, ["com.github.githubapp"])
        XCTAssertEqual(appTarget?.names, ["GitHub Copilot"])

        let terminal = HostInfo(from: ["bundle": .string("dev.warp.Warp-Stable"),
                                       "name": .string("Warp")],
                                cwd: "/tmp/proj")
        let terminalTarget = IDELauncher.target(for: "copilot", host: terminal)
        XCTAssertEqual(terminalTarget?.bundles, ["dev.warp.Warp-Stable"])
        XCTAssertEqual(terminalTarget?.names, ["Warp"])
    }

    /// Copilot 的 hook 文件是扁平 command 条目，并且只有 ask_user 会进 preToolUse。
    /// 全量 preToolUse 在 Copilot 上是 fail-closed，脚本一出错就拒绝所有工具。
    func testCopilotHookFileIsFlatAndQuestionScoped() {
        let doc = CopilotHookInstaller.hookDocument(
            scriptPath: "/tmp/betterfocus-notify.sh", questionTimeout: 120)
        XCTAssertEqual(doc["version"] as? Int, 1)
        let hooks = doc["hooks"] as? [String: [[String: Any]]]
        let pre = hooks?["PreToolUse"]?.first
        XCTAssertEqual(pre?["type"] as? String, "command")
        XCTAssertEqual(pre?["command"] as? String, "/tmp/betterfocus-notify.sh")
        XCTAssertEqual(pre?["matcher"] as? String, "AskUserQuestion")
        XCTAssertEqual(pre?["timeoutSec"] as? Int, 120)
        XCTAssertNil(pre?["hooks"], "不能写成 Claude 的嵌套 hooks 分组")
        XCTAssertEqual(hooks?["PreToolUse"]?.count, 1)
        let permission = hooks?["PermissionRequest"]?.first
        XCTAssertNil(permission?["matcher"], "权限提醒要覆盖全部工具，但不能带空 matcher")
        XCTAssertEqual(permission?["timeoutSec"] as? Int, 5)
        XCTAssertEqual(hooks?["Stop"]?.first?["timeoutSec"] as? Int, 5)
        XCTAssertEqual(hooks?["UserPromptSubmit"]?.first?["command"] as? String,
                       "/tmp/betterfocus-notify.sh")
        let post = hooks?["PostToolUse"]?.first?["matcher"] as? String ?? ""
        XCTAssertTrue(post.contains("|sql"), "TodoWrite 在 Copilot CLI 里是 sql，进度卡必须挂上")
        XCTAssertFalse((pre?["matcher"] as? String ?? "").contains("sql"),
                       "sql 不能进 PreToolUse，那条失败即拒绝")
    }

    /// Copilot CLI 的待办不叫 TodoWrite。技能里的 TodoWrite 落到会话库的
    /// `sql` 工具，表是内置的 `todos`。INSERT 建任务，UPDATE 改状态；
    /// 其它表和 todo_deps 不能误当成进度。
    func testCopilotSessionSqlBecomesTodoRows() throws {
        let dir = NSTemporaryDirectory() + "bf-copilot-sql-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let hook = dir + "/hook.py"
        try CopilotHookInstaller.helperContent.write(toFile: hook, atomically: true, encoding: .utf8)
        let probe = dir + "/probe.py"
        let script = """
        import importlib.util, json, sys
        spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        insert = (
            "INSERT INTO todos (id, title, description) VALUES "
            "('tool-test-01', 'Creating test task 1', 'd1'), "
            "('tool-test-02', 'Creating test task 2', 'd2')"
        )
        rows = mod.copilot_todo_changes(insert)
        assert rows == [
            {"id": "tool-test-01", "content": "Creating test task 1", "status": "pending"},
            {"id": "tool-test-02", "content": "Creating test task 2", "status": "pending"},
        ], rows
        updated = mod.copilot_todo_changes(
            "UPDATE todos SET status = 'done' WHERE id = 'tool-test-01'")
        assert updated == [
            {"id": "tool-test-01", "content": "", "status": "done"},
        ], updated
        assert mod.copilot_todo_changes(
            "INSERT INTO todo_deps (todo_id, depends_on) VALUES ('a', 'b')") == []
        assert mod.copilot_todo_changes(
            "INSERT INTO session_state (key, value) VALUES ('a', 'b')") == []
        box = {"tasks": {}}
        sent = []
        mod._load_todo_state = lambda sid: {"tasks": dict(box["tasks"])}
        def save(sid, state):
            box["tasks"] = dict(state.get("tasks") or {})
        mod._save_todo_state = save
        mod.send = lambda msg: sent.append(msg)
        mod.emit_copilot_sql_todos("sess", {"tool_name": "sql", "tool_input": {"query": insert}})
        mod.emit_copilot_sql_todos("sess", {
            "tool_name": "sql",
            "tool_input": {"query": "UPDATE todos SET status = 'in_progress' WHERE id = 'tool-test-02'"},
        })
        mod.emit_copilot_sql_todos("sess", {
            "tool_name": "sql",
            "tool_input": {"database": "project", "query": insert},
        })
        titles = [(m["payload"]["todo"]["id"], m["payload"]["todo"]["content"], m["payload"]["todo"]["status"]) for m in sent]
        assert titles == [
            ("tool-test-01", "Creating test task 1", "pending"),
            ("tool-test-02", "Creating test task 2", "pending"),
            ("tool-test-02", "Creating test task 2", "in_progress"),
        ], titles
        print("ok")
        """
        try script.write(toFile: probe, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [probe, hook]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, err)
    }

    /// 只在显式打开环境变量时写 ~/.codex/hooks.json，避免普通测试碰用户目录。
    /// notify 已被占用时安装必须成功，并且不能改 config.toml。
    func testInstallCodexHooksWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BETTERFOCUS_INSTALL_CODEX"] == "1")
        let config = InstallerPaths.codexConfigPath
        let before = try? String(contentsOfFile: config, encoding: .utf8)
        try CodexHookInstaller.install()
        XCTAssertTrue(CodexHookInstaller.isInstalled)
        XCTAssertTrue(CodexHookInstaller.isRegistered)
        let after = try? String(contentsOfFile: config, encoding: .utf8)
        XCTAssertEqual(before, after, "已有 notify 时不能改 config.toml")
    }

    /// 本机安装入口。只在显式打开环境变量时写 ~/.copilot/hooks，避免普通测试碰用户目录。
    func testInstallCopilotHooksWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BETTERFOCUS_INSTALL_COPILOT"] == "1")
        try CopilotHookInstaller.install()
        XCTAssertTrue(CopilotHookInstaller.isInstalled)
        XCTAssertTrue(CopilotHookInstaller.isRegistered)
    }

    /// Copilot 的放行必须是「什么都不写」。顶层 allow 会跳过用户确认。
    func testCopilotDecisionStaysSilentOnAllow() {
        let body = CopilotHookInstaller.helperContent
        XCTAssertTrue(body.contains("EVENT_STYLE == \"copilot\""))
        XCTAssertTrue(body.contains("\"permissionDecision\": \"deny\""))
        XCTAssertTrue(body.contains("\"behavior\": \"deny\""))
        XCTAssertTrue(body.contains("decision in (\"ask\", \"allow\")"))
        XCTAssertTrue(body.contains("if EVENT_STYLE != \"copilot\":"))
        XCTAssertEqual(AgentProvider.label(provider: .copilot, hostName: "Warp",
                                           bundleID: "dev.warp.Warp-Stable"),
                       "Copilot（Warp）")
    }

    /// 每个 CLI provider 都必须被判为 isCLI，否则命名与跳转会走错分支。
    func testCLIClassification() {
        let cli: [AgentProvider] = [.claude_code, .codex, .kimi, .copilot,
                                    .qoder_cli, .qoder_cn_cli]
        for provider in cli {
            XCTAssertTrue(provider.isCLI, "\(provider.rawValue) 应为 CLI")
        }
        for provider in [AgentProvider.trae, .trae_cn, .cursor, .workbuddy, .qoder_ide] {
            XCTAssertFalse(provider.isCLI, "\(provider.rawValue) 不应为 CLI")
        }
    }

    /// Qoder CN 与 Qoder 共用主题色：同一产品的两个发行版不该让用户调两次。
    func testQoderCNSharesTintWithQoder() {
        XCTAssertEqual(AgentProvider.qoder_cn_cli.tintRGB.red,
                       AgentProvider.qoder_cli.tintRGB.red, accuracy: 0.0001)
        XCTAssertEqual(AgentProvider.qoder_cn_ide.providerGroup, "qoder")
    }
}
