// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 测试调试面板的场景目录与目标身份：这两处一旦漂移，页面上就会出现
/// 点了没反应的空行，或者一张图标 / 来源名对不上的卡片。
final class DebugScenariosTests: XCTestCase {

    /// 场景 id 必须唯一（SwiftUI 的 ForEach 依赖它）。
    func testSceneIDsAreUnique() {
        let ids = DebugCatalog.scenes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "存在重复的场景 id：\(ids)")
    }

    /// 每个场景的 group 都必须在 groups 里登记，否则它不会出现在页面上。
    func testEverySceneGroupIsListed() {
        let groups = Set(DebugCatalog.groups)
        for scene in DebugCatalog.scenes {
            XCTAssertTrue(groups.contains(scene.group),
                          "场景 \(scene.id) 的分组「\(scene.group)」未在 groups 中登记")
        }
    }

    /// 每个分组下至少有一个场景。
    func testEveryGroupHasScenes() {
        for group in DebugCatalog.groups {
            XCTAssertFalse(DebugCatalog.scenes(in: group).isEmpty, "分组「\(group)」没有场景")
        }
    }

    /// 目标 IDE 的 id 唯一，且伪造的宿主身份能被 HostInfo 正确解析回来
    /// （图标与来源名都靠它）。
    func testTargetsCarryParsableHost() {
        let ids = DebugTarget.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "存在重复的目标 id：\(ids)")

        for target in DebugTarget.all {
            let host = HostInfo(from: target.host(project: "demo"))
            XCTAssertEqual(host.bundle, target.bundle)
            XCTAssertEqual(host.name, target.hostName)
            XCTAssertFalse(host.isEmpty)
        }
    }

    /// 工作目录作为消息顶层字段上报（真实 hook 里 cwd 不在 host 里），
    /// 且空项目名回退到占位目录名，避免卡片上的项目标签变成空串。
    func testCwdProjectFallback() {
        // cwd 是顶层字段：host 字典里不该有 cwd，否则历史条目工作目录会丢空。
        for target in DebugTarget.all {
            let host = target.host(project: "demo")
            XCTAssertNil(host["cwd"], "\(target.title) 的 host 里不应带 cwd")
        }
        XCTAssertTrue(DebugTarget.cwd(project: "   ").hasSuffix("/Documents/demo-project"))
    }

    /// 覆盖范围自查：四个宿主的提问 / 权限 / 完成通知三种事件形态都在目录里。
    func testCatalogCoversAllPayloadKinds() {
        let payloads = DebugCatalog.scenes.map(\.payload)
        func has(_ predicate: (DebugPayload) -> Bool) -> Bool { payloads.contains(where: predicate) }

        XCTAssertTrue(has { if case .question = $0 { return true }; return false })
        XCTAssertTrue(has { if case .permission = $0 { return true }; return false })
        XCTAssertTrue(has { if case .permissionNotice = $0 { return true }; return false })
        XCTAssertTrue(has { if case .turnFinished = $0 { return true }; return false })
        XCTAssertTrue(has { if case .sessionEnded = $0 { return true }; return false })
        XCTAssertTrue(has { if case .history = $0 { return true }; return false })
        XCTAssertTrue(has { if case .clearCards = $0 { return true }; return false })
        XCTAssertTrue(has { if case .clearHistory = $0 { return true }; return false })
    }

    /// 新适配的宿主都必须出现在目标清单里，CLI 宿主要用终端身份上报。
    func testTargetsCoverNewHosts() {
        let providers = Set(DebugTarget.all.map(\.provider))

        // 新接的 GUI 宿主。
        for p in [AgentProvider.trae, .trae_cn, .kimi,
                  .qoder_cn, .qoder_cn_ide] {
            XCTAssertTrue(providers.contains(p), "目标清单缺少 \(p.rawValue)")
        }
        // CLI 宿主。
        for p in [AgentProvider.qoder_cli, .qoder_cn_cli, .claude_code, .codex] {
            XCTAssertTrue(providers.contains(p), "目标清单缺少 \(p.rawValue)")
        }

        // CLI 目标上报的是终端身份（bundle 是终端、名字是终端名），
        // 这样图标 / 跳转 / 命名三处才同源。
        let cliTargets = DebugTarget.all.filter { $0.provider.isCLI }
        XCTAssertFalse(cliTargets.isEmpty)
        for target in cliTargets {
            XCTAssertTrue(TerminalHost.isTerminal(bundle: target.bundle, name: target.hostName),
                          "CLI 目标 \(target.title) 应使用终端身份上报")
        }
    }
}
