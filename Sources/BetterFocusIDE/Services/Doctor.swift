// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 自检报告中的一行检查结果。
struct DoctorCheck {
    /// 是否通过。
    let ok: Bool
    /// 检查项标签。
    let label: String
    /// 详情描述。
    let detail: String
    /// 失败时的修复提示（通过则为 nil）。
    let hint: String?
}

/// 自检："能不能跑 → 跑得对不对"。
///
/// 每项检查失败时都带一条修复提示，让"卡片没弹出"这类现象有可解释的原因。
enum Doctor {
    /// 依次执行所有检查，返回结果列表。
    static func run() -> [DoctorCheck] {
        var checks: [DoctorCheck] = [socketAlive()]
        // 四个宿主各自独立检查；宿主配置目录不存在时视为「没装这个宿主」，不算失败。
        checks.append(contentsOf: hostIntegration(
            label: "Qoder", hostDir: InstallerPaths.qoderDir,
            script: InstallerPaths.qoderScriptPath, helper: InstallerPaths.qoderHelperPath,
            registered: hookRegistered))
        checks.append(contentsOf: hostIntegration(
            label: "OpenCode", hostDir: InstallerPaths.opencodePluginsDir,
            script: InstallerPaths.opencodePluginPath, helper: nil,
            registered: { true }))
        checks.append(contentsOf: hostIntegration(
            label: "Cursor", hostDir: InstallerPaths.cursorDir,
            script: InstallerPaths.cursorScriptPath, helper: InstallerPaths.cursorHelperPath,
            registered: { CursorHookInstaller.isRegistered }))
        checks.append(contentsOf: hostIntegration(
            label: "WorkBuddy", hostDir: InstallerPaths.workbuddyDir,
            script: InstallerPaths.workbuddyScriptPath, helper: InstallerPaths.workbuddyHelperPath,
            registered: { WorkBuddyHookInstaller.isRegistered }))
        checks.append(contentsOf: hostIntegration(
            label: "Claude Code", hostDir: InstallerPaths.claudeDir,
            script: InstallerPaths.claudeScriptPath, helper: InstallerPaths.claudeHelperPath,
            registered: { ClaudeCodeHookInstaller.isRegistered }))
        // 桌面应用已改名为 ChatGPT，bundle id 仍是 com.openai.codex。
        // 只装了 App、还没生成 ~/.codex 时也要列出，不能当成「没装这个宿主」。
        if CodexHookInstaller.isPresent {
            checks.append(contentsOf: hostIntegration(
                label: "ChatGPT", hostDir: InstallerPaths.codexDir,
                script: InstallerPaths.codexScriptPath, helper: InstallerPaths.codexHelperPath,
                registered: { CodexHookInstaller.isRegistered },
                assumePresent: true,
                registeredDetail: "已登记（需在 ChatGPT 里信任该 hook 后才会触发）"))
        } else {
            checks.append(DoctorCheck(ok: true, label: "ChatGPT 集成",
                                      detail: "本机未检测到该宿主，跳过", hint: nil))
        }
        // Copilot 的配置在 ~/.copilot/hooks，和二进制是否在 PATH 上无关。
        // 放在 ChatGPT 旁边，避免自检页要滚过一长串「跳过」才看得到。
        checks.append(contentsOf: hostIntegration(
            label: "Copilot", hostDir: InstallerPaths.copilotDir,
            script: InstallerPaths.copilotScriptPath, helper: InstallerPaths.copilotHelperPath,
            registered: { CopilotHookInstaller.isRegistered },
            assumePresent: CopilotHookInstaller.isPresent))
        checks.append(contentsOf: hostIntegration(
            label: "Trae CN", hostDir: InstallerPaths.traeCnDir,
            script: InstallerPaths.traeScriptPath(InstallerPaths.traeCnDir),
            helper: InstallerPaths.traeHelperPath(InstallerPaths.traeCnDir),
            registered: { TraeHookInstaller.isRegistered(.cn) }))
        checks.append(contentsOf: hostIntegration(
            label: "Trae", hostDir: InstallerPaths.traeDir,
            script: InstallerPaths.traeScriptPath(InstallerPaths.traeDir),
            helper: InstallerPaths.traeHelperPath(InstallerPaths.traeDir),
            registered: { TraeHookInstaller.isRegistered(.international) }))
        checks.append(contentsOf: hostIntegration(
            label: "Kimi", hostDir: KimiHookInstaller.targetDir,
            script: KimiHookInstaller.scriptPath, helper: KimiHookInstaller.helperPath,
            registered: { KimiHookInstaller.isRegistered }))
        // 注意不能只看目录是否存在：`~/.qoder-cn` 常被链到 `~/.qoder`，
        // 那种情况是同一个安装，列出来只会让自检页出现重复的「Qoder CN」。
        if QoderCnHookInstaller.isPresent {
            checks.append(contentsOf: hostIntegration(
                label: "Qoder CN", hostDir: InstallerPaths.qoderCnDir,
                script: InstallerPaths.qoderCnScriptPath, helper: InstallerPaths.qoderCnHelperPath,
                registered: { QoderCnHookInstaller.isRegistered }))
        }
        checks.append(answerDirWritable())
        checks.append(settingsReadable())
        return checks
    }

    /// 单个宿主的集成状态：脚本 / helper 文件与宿主配置登记情况。
    static func hostIntegration(label: String, hostDir: String, script: String,
                                helper: String?, registered: () -> Bool,
                                assumePresent: Bool = false,
                                registeredDetail: String = "已登记") -> [DoctorCheck] {
        guard assumePresent || InstallerPaths.hostDirectoryExists(hostDir) else {
            return [DoctorCheck(ok: true, label: "\(label) 集成",
                                detail: "本机未检测到该宿主，跳过", hint: nil)]
        }
        var checks = [installedFile(label: "\(label) Hook 脚本", path: script)]
        if let helper {
            checks.append(installedFile(label: "\(label) Helper", path: helper))
        }
        checks.append(registered()
            ? DoctorCheck(ok: true, label: "\(label) Hook 开关", detail: registeredDetail, hint: nil)
            : DoctorCheck(ok: false, label: "\(label) Hook 开关",
                          detail: "未在宿主配置中登记",
                          hint: "菜单 → 一键安装 Hook / Plugin"))
        return checks
    }

    /// 统计未通过的检查数。
    static func failedCount(_ checks: [DoctorCheck]) -> Int {
        checks.filter { !$0.ok }.count
    }

    // MARK: - 各项检查

    /// socket 是否有活跃监听者：能 connect 上即活，陈旧 socket 文件会拒绝连接。
    static func socketAlive() -> DoctorCheck {
        let path = InstallerPaths.socketPath
        // 活跃监听者会应答 connect()；陈旧 socket 文件会拒绝。
        if probeSocket(path) {
            return DoctorCheck(ok: true, label: "Socket",
                               detail: "正在监听 \(path)", hint: nil)
        }
        return DoctorCheck(ok: false, label: "Socket",
                           detail: "\(path) 无人监听",
                           hint: "确认 BetterFocusIDE 正在运行（菜单栏有胶囊图标）")
    }

    /// 检查文件是否存在且可读。
    ///
    /// 内容与模板的差异比对不在 GUI 自检范围内，故只校验存在性与可读性。
    static func installedFile(label: String, path: String) -> DoctorCheck {
        if !FileManager.default.fileExists(atPath: path) {
            return DoctorCheck(ok: false, label: label, detail: "未安装",
                               hint: "菜单 → 一键安装 Hook / Plugin")
        }
        if let _ = try? String(contentsOfFile: path, encoding: .utf8) {
            return DoctorCheck(ok: true, label: label, detail: "已安装", hint: nil)
        }
        return DoctorCheck(ok: false, label: label, detail: "读不出来",
                           hint: "菜单 → 一键安装 Hook / Plugin")
    }

    /// Qoder settings.json 的 PermissionRequest 是否登记了带我们标记的分组。
    static func hookRegistered() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        let permission = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        return permission.contains {
            ($0["_betterfocus_marker"] as? String) == InstallerPaths.marker
        }
    }

    /// 检查应答目录是否可写：实际写一个探针文件再删除。
    static func answerDirWritable() -> DoctorCheck {
        let dir = InstallerPaths.answerDir
        let probe = (dir as NSString).appendingPathComponent(".doctor-probe")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try "ok".write(toFile: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: probe)
            return DoctorCheck(ok: true, label: "答案目录", detail: dir, hint: nil)
        } catch {
            return DoctorCheck(ok: false, label: "答案目录",
                               detail: "\(dir) 不可写：\(error.localizedDescription)",
                               hint: "检查目录权限")
        }
    }

    /// 检查设置文件：不存在视为用默认值（通过）；存在则要求 JSON 可解析。
    static func settingsReadable() -> DoctorCheck {
        let path = InstallerPaths.settingsPath
        guard FileManager.default.fileExists(atPath: path) else {
            return DoctorCheck(ok: true, label: "设置文件", detail: "未自定义，用默认值", hint: nil)
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return DoctorCheck(ok: true, label: "设置文件", detail: "可解析", hint: nil)
        }
        return DoctorCheck(ok: false, label: "设置文件", detail: "JSON 解析失败",
                           hint: "删除该文件后重开设置面板")
    }

    // MARK: - 辅助方法

    /// 尝试连接 Unix socket；返回 true 表示有人正在监听。
    private static func probeSocket(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= maxLen else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (i, b) in bytes.enumerated() where i < maxLen { raw[i] = b }
        }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }
}
