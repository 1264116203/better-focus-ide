// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 终端宿主推断的契约测试。
///
/// OpenCode 2.2.x 把会话执行统一收进桌面端常驻服务，插件拿不到客户端类型，
/// 只能靠进程祖先链判断——这里锁住那套判据。
final class OpenCodeHostProbeTests: XCTestCase {

    // MARK: - ps 解析

    func testParseSkipsBlankAndMalformedLines() {
        let text = """
        11988     1 /Applications/iTerm.app/Contents/MacOS/iTerm2

        22334     1 /Applications/OpenCode.app/Contents/MacOS/OpenCode
        garbage line without numbers
        """
        let table = OpenCodeHostProbe.parse(text)
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table[0], .init(pid: 11988, ppid: 1,
                                       command: "/Applications/iTerm.app/Contents/MacOS/iTerm2"))
        XCTAssertEqual(table[1].pid, 22334)
    }

    /// 命令行含空格时必须完整保留（`maxSplits: 2`）。
    func testParseKeepsCommandWithSpaces() {
        let table = OpenCodeHostProbe.parse("42  1 bun /$bunfs/root/opencode run --title a b")
        XCTAssertEqual(table.first?.command, "bun /$bunfs/root/opencode run --title a b")
    }

    // MARK: - 终端识别

    /// iTerm 里跑 `opencode`：opencode → zsh → login → iTerm2。
    func testDetectsItermAncestor() {
        let table = OpenCodeHostProbe.parse("""
        11988     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
        12000 11988 /bin/zsh --login
        12001 12000 bun /$bunfs/root/opencode
        """)
        let host = OpenCodeHostProbe.terminalHost(in: table)
        XCTAssertEqual(host?.bundle, "com.googlecode.iterm2")
        XCTAssertEqual(host?.name, "iTerm")
        XCTAssertEqual(host?.path, "/Applications/iTerm.app")
    }

    /// Terminal.app 同样命中。
    func testDetectsAppleTerminal() {
        let table = OpenCodeHostProbe.parse("""
        900     1 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
        901   900 -zsh
        902   901 bun /$bunfs/root/opencode run hi
        """)
        XCTAssertEqual(OpenCodeHostProbe.terminalHost(in: table)?.bundle, "com.apple.Terminal")
    }

    /// 桌面端后台服务（serve --service）不算客户端：祖先链只有 launchd。
    func testServiceProcessIsNotAClient() {
        let table = OpenCodeHostProbe.parse("""
        85872     1 bun /$bunfs/root/opencode serve --service
        """)
        XCTAssertNil(OpenCodeHostProbe.terminalHost(in: table))
    }

    /// GUI 打包进程（OpenCode.app / Helper）不算客户端，否则桌面端会话会误判。
    func testGuiBundledProcessIsNotAClient() {
        let table = OpenCodeHostProbe.parse("""
        22334     1 /Applications/OpenCode.app/Contents/MacOS/OpenCode
        22348 22334 /Applications/OpenCode.app/Contents/Frameworks/OpenCode Helper.app/Contents/MacOS/OpenCode Helper --type=gpu-process
        """)
        XCTAssertNil(OpenCodeHostProbe.terminalHost(in: table))
    }

    /// 完全无关的进程表不该误报。
    func testUnrelatedProcessesProduceNoHost() {
        let table = OpenCodeHostProbe.parse("""
        1 0 /sbin/launchd
        500 1 /Applications/Safari.app/Contents/MacOS/Safari
        """)
        XCTAssertNil(OpenCodeHostProbe.terminalHost(in: table))
    }

    /// 客户端存在但祖先链里没有终端（如 IDE 内嵌 ACP 会话）→ 保持 nil。
    func testClientWithoutTerminalAncestorYieldsNil() {
        let table = OpenCodeHostProbe.parse("""
        25554     1 /Applications/IntelliJ IDEA.app/Contents/MacOS/idea
        25769 25554 /Users/dev/Library/Caches/opencode acp
        """)
        XCTAssertNil(OpenCodeHostProbe.terminalHost(in: table))
    }

    /// 祖先链断裂（pid 不存在）时不能崩，直接返回 nil。
    func testBrokenAncestryReturnsNil() {
        let table = OpenCodeHostProbe.parse("500 999 bun /$bunfs/root/opencode")
        XCTAssertNil(OpenCodeHostProbe.terminalHost(in: table))
    }

    // MARK: - 路径与命名

    func testAppPathExtractsBundlePath() {
        XCTAssertEqual(
            OpenCodeHostProbe.appPath(in: "/Applications/iTerm.app/Contents/MacOS/iTerm2 -q"),
            "/Applications/iTerm.app")
        XCTAssertEqual(OpenCodeHostProbe.appPath(in: "/bin/zsh --login"), "")
    }

    /// iTerm 的进程名是 `iTerm2`，展示名要统一成 `iTerm`（与图标/命名同源）。
    func testTerminalDisplayNameIsNormalised() {
        let host = OpenCodeHostProbe.hostInfo(
            forTerminalCommand: "/Applications/iTerm.app/Contents/MacOS/iTerm2")
        XCTAssertEqual(host?.name, "iTerm")
        XCTAssertTrue(TerminalHost.isTerminal(bundle: host?.bundle, name: host?.name))
    }

    // MARK: - 会话目录比对

    /// lsof 输出解析：取 `n` 开头的行。
    func testParseWorkingDirectory() {
        let text = "p87403\nfcwd\nn/Users/dev/project\n"
        XCTAssertEqual(OpenCodeHostProbe.parseWorkingDirectory(text), "/Users/dev/project")
        XCTAssertNil(OpenCodeHostProbe.parseWorkingDirectory("p1\nfcwd\n"))
    }

    /// 双向包含：子目录启动、项目根上报，两种方向都算同一个会话。
    func testPathsOverlap() {
        XCTAssertTrue(OpenCodeHostProbe.pathsOverlap("/a/b", "/a/b"))
        XCTAssertTrue(OpenCodeHostProbe.pathsOverlap("/a/b", "/a/b/c"))
        XCTAssertTrue(OpenCodeHostProbe.pathsOverlap("/a/b/c", "/a/b/"))
        XCTAssertFalse(OpenCodeHostProbe.pathsOverlap("/a/b", "/a/bc"))
        XCTAssertFalse(OpenCodeHostProbe.pathsOverlap("", "/a/b"))
    }

    /// 会话目录与进程 cwd 一致 → 认定是终端里这一轮的会话。
    func testDirectoryMatchSelectsTerminal() {
        let table = OpenCodeHostProbe.parse("""
        11988     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
        87403 11988 opencode
        """)
        let host = OpenCodeHostProbe.terminalHost(
            in: table, directory: "/Users/dev/project",
            cwd: { _ in "/Users/dev/project" })
        XCTAssertEqual(host?.bundle, "com.googlecode.iterm2")
    }

    /// 目录不匹配：终端里那个 opencode 是另一个项目，本轮属于桌面端 → 不劫持。
    func testDirectoryMismatchYieldsNil() {
        let table = OpenCodeHostProbe.parse("""
        11988     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
        87403 11988 opencode
        """)
        let host = OpenCodeHostProbe.terminalHost(
            in: table, directory: "/Users/dev/other-project",
            cwd: { _ in "/Users/dev/project" })
        XCTAssertNil(host)
    }

    /// 读不到 cwd（权限受限）时不敢断言不属于本轮，降级为兜底候选。
    func testUnknownCwdFallsBack() {
        let table = OpenCodeHostProbe.parse("""
        11988     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
        87403 11988 opencode
        """)
        let host = OpenCodeHostProbe.terminalHost(
            in: table, directory: "/Users/dev/project",
            cwd: { _ in nil })
        XCTAssertEqual(host?.bundle, "com.googlecode.iterm2")
    }
}
