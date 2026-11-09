// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation
import ServiceManagement

/// 登录项（开机自启动）。系统状态以 `SMAppService.mainApp` 为准。
enum LoginItem {
    /// 已登记，或已登记但等用户在系统设置里点允许。
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// 单元测试不改本机登录项。
    private static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 把开关落到系统登录项。登记或取消失败时返回 false。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if isTesting { return true }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            switch service.status {
            case .enabled:
                Log.info("开机自启动已打开", topic: "login")
            case .requiresApproval:
                Log.info("开机自启动等待系统设置里允许", topic: "login")
            default:
                Log.info("开机自启动已关闭", topic: "login")
            }
            return true
        } catch {
            Log.error("开机自启动设置失败：\(error.localizedDescription)", topic: "login")
            return false
        }
    }

    /// 按已保存的开关补登记。应用换了安装位置后，系统里的旧登录项不会跟着走。
    static func applyStoredPreference() {
        let want = Settings.shared.launchAtLogin
        guard setEnabled(want) else {
            Settings.shared.launchAtLogin = isEnabled
            Settings.shared.save()
            return
        }
        if Settings.shared.launchAtLogin != isEnabled {
            Settings.shared.launchAtLogin = isEnabled
            Settings.shared.save()
        }
    }
}
