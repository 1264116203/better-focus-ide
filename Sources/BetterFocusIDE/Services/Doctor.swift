// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// One line of the doctor report.
struct DoctorCheck {
    let ok: Bool
    let label: String
    let detail: String
    let hint: String?
}

/// Self-check: "can it run → does it run correctly". Each check carries a
/// fix hint when it fails, so "the card didn't pop" has an explanation.
enum Doctor {
    static func run() -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        checks.append(socketAlive())
        checks.append(installedFile(label: "Qoder Hook 脚本",
                                    path: InstallerPaths.qoderScriptPath))
        checks.append(installedFile(label: "Qoder Helper",
                                    path: InstallerPaths.qoderHelperPath))
        checks.append(installedFile(label: "OpenCode Plugin",
                                    path: InstallerPaths.opencodePluginPath))
        checks.append(hookRegistered())
        checks.append(answerDirWritable())
        checks.append(settingsReadable())
        return checks
    }

    static func failedCount(_ checks: [DoctorCheck]) -> Int {
        checks.filter { !$0.ok }.count
    }

    // MARK: - Checks

    static func socketAlive() -> DoctorCheck {
        let path = InstallerPaths.socketPath
        // A live listener answers a connect(); a stale socket file refuses.
        if probeSocket(path) {
            return DoctorCheck(ok: true, label: "Socket",
                               detail: "正在监听 \(path)", hint: nil)
        }
        return DoctorCheck(ok: false, label: "Socket",
                           detail: "\(path) 无人监听",
                           hint: "确认 BetterFocusIDE 正在运行（菜单栏有胶囊图标）")
    }

    /// Whether the file exists; content-vs-template drift is out of scope for
    /// the GUI doctor, so this checks presence and readability.
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

    static func hookRegistered() -> DoctorCheck {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: InstallerPaths.qoderSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return DoctorCheck(ok: false, label: "Hook 开关", detail: "settings.json 无 hooks",
                               hint: "菜单 → 一键安装 Hook / Plugin")
        }
        let permission = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        let registered = permission.contains {
            ($0["_betterfocus_marker"] as? String) == InstallerPaths.marker
        }
        return registered
            ? DoctorCheck(ok: true, label: "Hook 开关", detail: "已登记", hint: nil)
            : DoctorCheck(ok: false, label: "Hook 开关", detail: "未在 settings.json 登记",
                          hint: "菜单 → 一键安装 Hook / Plugin")
    }

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

    // MARK: - Helpers

    /// Try to connect a Unix socket; true means someone is listening.
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
