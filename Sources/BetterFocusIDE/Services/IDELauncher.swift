// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Foundation

/// hook 在事件顶层上报的宿主应用身份信息。
struct HostInfo: Codable, Equatable {
    var bundle: String = ""
    var name: String = ""
    var path: String = ""
    var cwd: String = ""
    /// 浏览器会话的落地地址（如 `http://127.0.0.1:4096/`）。
    ///
    /// 只有 `opencode serve` + Web UI 这类「没有窗口、只有本机端口」的会话会填。
    /// 非空时跳转直接打开浏览器，不再去激活产品自己的桌面端。
    var url: String = ""

    /// 已知 bundle ID → 展示名称映射（internal 以便 HistoryEntry 解码时复用）。
    ///
    /// 当 hook 上报的 `host.name` 为空（某些 IDE 的 Info.plist 中 `CFBundleName` 缺失）
    /// 时，用此表回退填充，确保图标匹配与历史来源展示正确。
    static let bundleIdDisplayName: [String: String] = [
        // JetBrains
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.webstorm": "WebStorm",
        "com.jetbrains.goland": "GoLand",
        "com.jetbrains.rider": "Rider",
        "com.jetbrains.CLion": "CLion",
        "com.jetbrains.PhpStorm": "PhpStorm",
        "com.jetbrains.rubymine": "RubyMine",
        "com.jetbrains.datagrip": "DataGrip",
        "com.jetbrains.fleet": "Fleet",
        // VS Code 系
        "com.microsoft.VSCode": "Visual Studio Code",
        "com.visualstudio.code": "Visual Studio Code",
        "com.qoder.ide": "Qoder IDE",
        "com.aliyun.lingma.ide": "Qoder CN IDE",
        "com.qoder.app": "Qoder",
        "com.cursor": "Cursor",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "ai.opencode.desktop": "OpenCode",
        "com.byte-dance.trae": "Trae",
        "com.bytedance.trae": "Trae",
        "cn.trae.app": "Trae CN",
        "com.trae.app": "Trae",
        // 终端
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "dev.warp.Warp-Stable": "Warp",
        "com.mitchellh.ghostty": "Ghostty",
        "net.kovidgoyal.kitty": "Kitty",
        "org.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        // 其他
        "com.tencent.workbuddy.mac": "WorkBuddy",
        "ai.workbuddy": "WorkBuddy",
        "ai.moonshot.kimi": "Kimi",
        "com.moonshot.kimichat": "Kimi",
    ]

    init() {}

    /// 解码时容忍缺字段：历史记录里存下的 host 没有 `url`（以及早期版本的
    /// 其它新增键），用默认值兜底，避免整条历史读不出来。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundle = try c.decodeIfPresent(String.self, forKey: .bundle) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    /// 从 socket 消息的 host 字典 + 可选 cwd 构造；缺失字段留空。
    ///
    /// 当 `name` 为空但 `bundle` 非空时，用已知 bundle ID 映射表回退填充名称，
    /// 确保图标匹配与历史来源展示不受 `CFBundleName` 缺失影响。
    init(from dict: [String: AnyCodableValue]?, cwd: String? = nil) {
        guard let dict else { return }
        bundle = dict["bundle"]?.stringValue ?? ""
        name = dict["name"]?.stringValue ?? ""
        path = dict["path"]?.stringValue ?? ""
        self.cwd = cwd ?? dict["cwd"]?.stringValue ?? ""
        // name 缺失时，用 bundle ID 映射表回退
        if name.isEmpty && !bundle.isEmpty {
            name = Self.bundleIdDisplayName[bundle] ?? ""
        }
    }

    /// bundle/name/path 全空视为无有效宿主信息。
    var isEmpty: Bool { bundle.isEmpty && name.isEmpty && path.isEmpty }
}

/// 唤起产生某条通知的 IDE 窗口。
///
/// 用 AppleScript `tell application ... activate` 而非 `NSRunningApplication.activate`：
/// 从裸可执行文件启动的辅助应用缺乏 macOS 焦点保护所需的 bundle 身份，而 Apple Events
/// 是针对*目标*应用的身份来授权的。
enum IDELauncher {
    // 提供方 → bundle id / 应用名，按尝试顺序排列。
    static let ideBundles: [String: [String]] = [
        // Qoder 家族：独立应用 + VS Code 系 IDE（英文/中文）
        "qoder": ["com.qoder.app", "com.qoder.ide", "com.aliyun.lingma.ide"],
        "opencode": ["ai.opencode.desktop"],
        // Cursor：ToDesktop 打包的实际 bundle id 在前，官方 id 兜底
        "cursor": ["com.todesktop.230313mzl4w4u92", "com.cursor"],
        // WorkBuddy：桌面应用（Electron），无 VS Code 系 CLI
        "workbuddy": ["com.tencent.workbuddy.mac", "ai.workbuddy"],
        // Trae：国内版 cn.trae.app 在前，国际版与旧 id 兜底
        "trae": ["cn.trae.app", "com.trae.app", "com.byte-dance.trae", "com.bytedance.trae"],
        // Kimi 桌面应用（Kimi CLI 跑在终端里，不会用到这一项）
        "kimi": ["com.moonshot.kimichat", "ai.moonshot.kimi"],
        // Claude Code / Codex 只有 CLI，没有可跳回的应用窗口——空列表意味着
        // 交给下面的「终端宿主」分支去激活终端。
        "claude_code": [],
        "codex": [],
    ]
    static let ideNames: [String: [String]] = [
        "qoder": ["Qoder"],
        "opencode": ["OpenCode"],
        "cursor": ["Cursor"],
        "workbuddy": ["WorkBuddy"],
        "trae": ["Trae CN", "Trae"],
        "kimi": ["Kimi"],
        "claude_code": [],
        "codex": [],
    ]
    static let jetbrainsPrefix = "com.jetbrains."
    /// VS Code 系变体：支持 `code -r <cwd>` 精确复用项目窗口。
    static let vscodeFamilyBundles: Set<String> = [
        "com.qoder.ide", "com.aliyun.lingma.ide",
        "com.todesktop.230313mzl4w4u92", "com.cursor",
    ]
    /// 终端宿主的判定统一收在 `TerminalHost`：跳转、命名、图标三处必须用同一份
    /// 名单，否则会出现「卡片写着 Qoder CLI（Warp）但点不开」这类不一致。
    /// 需要终端名单时请用 `TerminalHost.bundles`。

    /// 决定该为这条通知唤起哪个应用；返回 nil 表示没有可跳转的目标。
    static func target(for provider: String, host: HostInfo?) -> (bundles: [String], names: [String])? {
        // provider 可能是产品值（jetbrains_plugin / qoder_cli 等）或组值
        // （qoder / opencode / cursor / workbuddy），用 AgentProvider 统一解析后
        // 取 providerGroup 作为索引键。
        let resolved = AgentProvider(rawValue: provider)
        var key = resolved?.providerGroup ?? (ideBundles[provider] != nil ? provider : "qoder")
        let bundle = host?.bundle ?? ""
        // provider 缺失或 unknown 时用宿主 bundle 反查分组：老 hook 或第三方脚本
        // 只上报 host 时，Cursor / WorkBuddy 的通知也必须跳回自己的窗口。
        if (resolved == nil || resolved == .unknown), let inferred = group(for: bundle) {
            key = inferred
        }
        let bundles = ideBundles[key] ?? []
        let names = ideNames[key] ?? []
        if bundle.isEmpty { return (bundles, names) }
        // JetBrains 系：直接用上报的具体 bundle/名字（每个 IDE bundle 各不同）。
        if bundle.hasPrefix(jetbrainsPrefix) {
            let name = host?.name ?? ""
            return ([bundle], name.isEmpty ? [] : [name])
        }
        if bundles.contains(bundle) { return (bundles, names) }
        // 终端宿主（Warp / iTerm / Terminal / Ghostty / VS Code 内置终端…）：
        // 产品自己没有窗口，但用户是在这个终端里等结果的——点通知就把终端
        // 激活到前台，而不是什么都不做。
        if TerminalHost.isTerminal(bundle: bundle, name: host?.name) {
            let terminalName = TerminalHost.displayName(bundle: bundle, name: host?.name) ?? ""
            return ([bundle], terminalName.isEmpty ? [] : [terminalName])
        }
        return (bundles, names)
    }

    /// 由宿主 bundle id 反查它属于哪个提供方组。
    static func group(for bundle: String) -> String? {
        guard !bundle.isEmpty else { return nil }
        for (key, bundles) in ideBundles where bundles.contains(bundle) { return key }
        return nil
    }

    /// 为该通知唤起 IDE。返回是否成功。
    ///
    /// 二级定位策略（知道 `cwd` 时先尝试精确聚焦到具体项目窗口）：
    /// - JetBrains：CLI 直达 → AXRaise 同 Space → Window 菜单跨 Space/合并 tab
    /// - Qoder IDE：`code -r <cwd>` 复用窗口
    /// - 其他/失败：回退 App 级激活
    @discardableResult
    static func activate(provider: String, host: HostInfo?) -> Bool {
        // 浏览器会话（`opencode serve` + Web UI）：没有窗口可激活，也不该把
        // 产品桌面端叫到前台——用户在浏览器里等着，落地就该是那个页面。
        if let raw = host?.url, !raw.isEmpty, let target = URL(string: raw) {
            if NSWorkspace.shared.open(target) {
                Log.info("已在浏览器打开 \(raw)", topic: "launcher")
                return true
            }
            Log.warning("浏览器打开失败：\(raw)", topic: "launcher")
        }
        guard let targets = target(for: provider, host: host) else {
            Log.info("\(provider) 跑在终端里，没有可跳转的窗口", topic: "launcher")
            return false
        }
        let bundles = targets.bundles
        let names = targets.names
        let hostBundle = host?.bundle ?? ""
        let cwd = host?.cwd ?? ""

        // ── 窗口级二级定位：知道项目目录时先尝试精确聚焦 ──
        if !cwd.isEmpty {
            // JetBrains 系：三层回退
            if hostBundle.hasPrefix(jetbrainsPrefix) {
                // ① CLI 直达：让运行中的 IDE 自己聚焦目标工程窗/tab（跨 Space、无闪烁）
                if focusJetBrainsViaCLI(bundle: hostBundle, cwd: cwd) {
                    Log.info("已用 JetBrains CLI 定位窗口 \(provider)（\(cwd)）", topic: "launcher")
                    return true
                }
                // ② AXRaise：同 Space 时直达（无闪烁）
                if isRunning(bundle: hostBundle), activateByAppleScript(bundle: hostBundle) {
                    if raiseJetBrainsWindow(bundle: hostBundle, cwd: cwd) {
                        Log.info("AXRaise 定位 JetBrains 窗口 \(provider)（\(cwd)）", topic: "launcher")
                        return true
                    }
                    // ③ Window 菜单点击：跨 Space/合并 tab（有闪烁但可靠）
                    let focusOk = focusJetBrainsWindowViaMenu(bundle: hostBundle, cwd: cwd)
                    Log.info("已定位 JetBrains 窗口 \(provider)（\(cwd)）菜单定位: \(focusOk)", topic: "launcher")
                    return true
                }
            }
            // VS Code 系（Qoder IDE / Cursor）：code -r + IPC socket 复用窗口
            if vscodeFamilyBundles.contains(hostBundle),
               let hostPath = host?.path, !hostPath.isEmpty {
                if focusCodeWindow(hostPath: hostPath, hostBundle: hostBundle, cwd: cwd) {
                    Log.info("已用 code -r 定位 \(hostBundle) 窗口 \(cwd)", topic: "launcher")
                    return true
                }
            }
            // VS Code 系二级定位失败时，回退到 App 级激活
            if vscodeFamilyBundles.contains(hostBundle) {
                if activateByAppleScript(bundle: hostBundle) {
                    Log.info("已激活 VS Code 系 \(hostBundle)（App 级回退）", topic: "launcher")
                    return true
                }
            }
        }

        // ── App 级回退 ──
        // 1. 优先按运行中应用的 bundle id 激活。
        for bundle in bundles {
            if isRunning(bundle: bundle), activateByAppleScript(bundle: bundle) {
                Log.info("已激活 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        // 2. 回退到应用名（中文区 bundle id 常常对不上）。
        for name in runningNames(matching: names) {
            if activateByAppName(name: name) {
                Log.info("已按应用名激活 \(name)", topic: "launcher")
                return true
            }
        }
        // 3. 没在运行：直接启动它。
        for bundle in bundles {
            if launch(bundle: bundle) {
                Log.info("已启动 \(provider)（\(bundle)）", topic: "launcher")
                return true
            }
        }
        Log.warning("未能唤起 \(provider)", topic: "launcher")
        return false
    }

    /// 在主线程之外执行唤起——AppleScript 首次编译约需 1 秒，会卡主线程。
    static func activateAsync(provider: String, host: HostInfo?) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = activate(provider: provider, host: host)
        }
    }

    // MARK: - 辅助方法

    /// 指定 bundle id 的应用是否正在运行。
    private static func isRunning(bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// 在运行中应用里挑出展示名匹配目标名的（去重、保序）。
    private static func runningNames(matching names: [String]) -> [String] {
        var found: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            let localizedName = app.localizedName ?? ""
            if !localizedName.isEmpty,
               names.contains(where: { localizedName.contains($0) }),
               !found.contains(localizedName) {
                found.append(localizedName)
            }
        }
        return found
    }

    /// 按 bundle id 用 AppleScript 激活。
    private static func activateByAppleScript(bundle: String) -> Bool {
        runAppleScript("tell application id \"\(bundle)\" to activate")
    }

    /// 按应用名用 AppleScript 激活（对名字里的反斜杠/引号做转义）。
    private static func activateByAppName(name: String) -> Bool {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return runAppleScript("tell application \"\(escaped)\" to activate")
    }

    /// 执行一段 AppleScript；出错时记录并返回 false。
    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.warning("AppleScript 失败：\(errorInfo)", topic: "launcher")
            return false
        }
        return true
    }

    /// 用 `/usr/bin/open -b` 启动指定 bundle 的应用，退出码 0 视为成功。
    private static func launch(bundle: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundle]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            Log.warning("启动 \(bundle) 失败：\(error)", topic: "launcher")
            return false
        }
    }

    // MARK: - 二级定位：JetBrains

    /// 取项目目录的末段名（JetBrains 窗口标题里的项目名就是它）。
    private static func projectLeaf(from cwd: String) -> String {
        let url = URL(fileURLWithPath: cwd)
        return url.lastPathComponent
    }

    /// 用 JetBrains App 自带可执行文件聚焦工程窗（无菜单闪烁，首选）。
    ///
    /// `<binary> <项目路径>`：运行中的实例会把请求转发给对应工程窗/合并 tab 并聚焦
    /// （含跨全屏 Space，由 IDE 自己切桌面）。二进制路径从 `NSRunningApplication.executableURL`
    /// 现取，不依赖 hook 上报的 path 字段；仅在实例已运行时尝试。
    private static func focusJetBrainsViaCLI(bundle: String, cwd: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        guard let app = apps.first else { return false }
        guard let exe = app.executableURL?.path, FileManager.default.isExecutableFile(atPath: exe) else {
            Log.debug("未找到 \(bundle) 的可执行文件，不用 CLI 定位", topic: "launcher")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = [cwd]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                Log.debug("JetBrains CLI 返回非零 (\(task.terminationStatus))", topic: "launcher")
                return false
            }
            return true
        } catch {
            Log.debug("JetBrains CLI 定位失败：\(error)", topic: "launcher")
            return false
        }
    }

    /// 同 Space 独立窗的无闪烁定位：用 AXRaise 直接提目标窗口。
    ///
    /// 按窗口标题前缀匹配工程名（IDEA 窗口标题形如 `<project> – <file>`）。
    /// 局限：跨全屏 Space 时 System Events 看不到其他 Space 的窗口，会 miss。
    private static func raiseJetBrainsWindow(bundle: String, cwd: String) -> Bool {
        let leaf = projectLeaf(from: cwd)
        guard !leaf.isEmpty else { return false }
        let safeLeaf = leaf.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "System Events" to tell (first process whose bundle identifier is "\(bundle)")
          set frontmost to true
          try
            tell (first window whose name starts with "\(safeLeaf)") to perform action "AXRaise"
          on error
            return "miss"
          end try
        end tell
        """
        guard let (ok, result) = runAppleScriptWithResult(source), ok else { return false }
        // 成功时 result 可能是 "miss" 或 nil
        if let str = result as? String, str.trimmingCharacters(in: .whitespaces) == "miss" {
            return false
        }
        return true
    }

    /// 靠 IDEA 自己的 Window 菜单切到目标工程窗（实测可跨 Space / 合并 tab）。
    ///
    /// 一个工程一个窗，Window 菜单里那一项的名字就是工程目录名。作为 AXRaise miss 时的兜底。
    /// 已知 trade-off：菜单点击会短暂展开 Window 菜单（约 100-200ms 视觉闪烁）。
    private static func focusJetBrainsWindowViaMenu(bundle: String, cwd: String) -> Bool {
        let leaf = projectLeaf(from: cwd)
        guard !leaf.isEmpty else { return false }
        let safeLeaf = leaf.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "System Events" to tell (first process whose bundle identifier is "\(bundle)")
          set frontmost to true
          click menu bar item "Window" of menu bar 1
          click menu item "\(safeLeaf)" of menu 1 of menu bar item "Window" of menu bar 1
        end tell
        """
        let ok = runAppleScript(source)
        if !ok {
            Log.debug("点 Window 菜单未命中工程窗 bundle=\(bundle) leaf=\(leaf)", topic: "launcher")
        } else {
            Log.debug("Window 菜单点击成功 leaf=\(leaf)", topic: "launcher")
        }
        return ok
    }

    // MARK: - 二级定位：Qoder / VS Code 系

    /// 从运行中 VS Code 系进程的数据目录查找 IPC socket 路径。
    ///
    /// VS Code 系应用启动时会在用户数据目录下创建 `<version>-main.sock` 文件用于进程间通信。
    /// 外部调用 `code` CLI 时需要设置 `VSCODE_IPC_HOOK_CLI` 环境变量指向该 socket，
    /// 否则 CLI 无法找到运行中的实例而会打开新窗口。
    ///
    /// 注意：应用名与数据目录名不一定相同（如 "Qoder IDE.app" → "Qoder"，
    /// "Qoder CN IDE.app" → "QoderCN"），因此通过 bundle ID 映射到已知的数据目录名，
    /// 同时兜底扫描所有可能的目录名。
    private static func findCodeIPCSocket(hostBundle: String, hostPath: String = "") -> String? {
        // bundle ID → 数据目录名（VS Code 系应用的用户数据目录不一定与应用名相同）
        let bundleToDataDir: [String: [String]] = [
            "com.qoder.ide": ["Qoder", "Qoder IDE"],
            "com.aliyun.lingma.ide": ["QoderCN", "Qoder CN"],
            "com.todesktop.230313mzl4w4u92": ["Cursor"],
            "com.cursor": ["Cursor"],
            "com.microsoft.VSCode": ["Code"],
            "com.visualstudio.code.oss": ["Code - OSS"],
        ]

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        // 收集候选目录名：bundle ID 映射优先，再从应用路径推导兜底
        var candidateDirs: [String] = []
        if let dirNames = bundleToDataDir[hostBundle] {
            candidateDirs.append(contentsOf: dirNames)
        }
        // 兜底：从 .app 路径推导可能的数据目录名
        // （某些 VS Code fork 的数据目录名与应用名一致）
        if !hostPath.isEmpty {
            let appName = (hostPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            if !appName.isEmpty && !candidateDirs.contains(appName) {
                candidateDirs.append(appName)
            }
        }

        for dirName in candidateDirs {
            let dataDir = appSupport.appendingPathComponent(dirName)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dataDir.path) else {
                continue
            }
            let sockFiles = contents.filter { $0.hasSuffix("-main.sock") }
            if let latest = sockFiles.sorted().last {
                let sockPath = dataDir.appendingPathComponent(latest).path
                if FileManager.default.fileExists(atPath: sockPath) {
                    Log.debug("找到 VS Code 系 IPC socket: \(sockPath)", topic: "launcher")
                    return sockPath
                }
            }
        }
        return nil
    }

    /// 用 IDE 自带的 `code` 启动器 `-r`（reuse-window）聚焦该 workspace 窗口。
    ///
    /// Qoder 是 VS Code 系 fork，窗口标题不含项目路径；但 IDE 自己知道哪个窗口开着着哪个
    /// folder，`code -r <folder>` 会把它复用/聚焦到那个窗口——不需要辅助功能授权，最准。
    ///
    /// **关键**：必须设置 `VSCODE_IPC_HOOK_CLI` 环境变量指向运行中实例的 IPC socket，
    /// 否则 CLI 进程无法通过 socket 连接到已有实例，会退化为打开新窗口。
    /// 找不到 socket 时返回 false，由调用者回退到 AppleScript 激活（不会产生新实例闪烁）。
    /// socket 路径从 `hostPath` 推导出的应用数据目录中查找（`*-main.sock`）。
    private static func focusCodeWindow(hostPath: String, hostBundle: String, cwd: String) -> Bool {
        guard !hostPath.isEmpty else { return false }
        let codeBin = (hostPath as NSString).appendingPathComponent("Contents/Resources/app/bin/code")
        guard FileManager.default.isExecutableFile(atPath: codeBin) else {
            Log.debug("未找到 \(hostPath) 的 code 启动器，回退 App 级唤起", topic: "launcher")
            return false
        }

        // 必须找到 IPC socket 才能安全复用窗口；否则 code -r 会打开新实例导致闪烁
        guard let sockPath = findCodeIPCSocket(hostBundle: hostBundle, hostPath: hostPath) else {
            Log.debug("未找到 \(hostBundle) 的 IPC socket，跳过 code -r 回退 AppleScript", topic: "launcher")
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: codeBin)
        task.arguments = ["-r", cwd]

        // 设置 IPC socket 环境变量，让 CLI 能连接到运行中的实例而非开新窗口
        var env = ProcessInfo.processInfo.environment
        env["VSCODE_IPC_HOOK_CLI"] = sockPath
        task.environment = env

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                Log.debug("code -r 返回非零 (\(task.terminationStatus))", topic: "launcher")
                return false
            }
            return true
        } catch {
            Log.debug("code -r 唤起失败：\(error)", topic: "launcher")
            return false
        }
    }

    // MARK: - AppleScript 辅助

    /// 执行 AppleScript 并返回 (成功, 结果值)。
    private static func runAppleScriptWithResult(_ source: String) -> (Bool, Any?)? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            Log.warning("AppleScript 失败：\(errorInfo)", topic: "launcher")
            return (false, nil)
        }
        return (true, result)
    }
}
