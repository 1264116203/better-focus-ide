// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import Combine
import SwiftUI

/// 应用生命周期代理。
///
/// 负责：单实例互斥锁校验、状态栏菜单搭建、灵动岛服务初始化、
/// 键盘应答与设置/自检辅助窗口的呈现。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 状态栏图标项。关掉「显示状态栏图标」后为 nil。
    private var statusItem: NSStatusItem?
    private var settingsObserver: AnyCancellable?
    /// 灵动岛中央编排服务（单例）。
    private var notchService: NotchService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 以辅助应用模式运行（不在 Dock 显示图标）。
        NSApp.setActivationPolicy(.accessory)

        // 单实例守卫优先执行：若另一个灵动岛实例已持有 socket，则在拉起
        // 第二个（幽灵）实例之前先退出。后台辅助应用的重复启动应静默无操作
        // （与多数菜单栏工具一致）——此处若弹模态框会阻塞主线程，让被拒绝的
        // 进程挂起而非正常退出。
        notchService = NotchService.shared
        switch notchService.startSocket() {
        case .started:
            CrashLog.noteSessionStart()
            LoginItem.applyStoredPreference()
        case .alreadyRunning:
            Log.info("另一实例已持有 socket；退出。", topic: "app")
            NSApp.terminate(nil)
            return
        case .failed(let error):
            Log.error("socket 启动失败（\(error)）；退出。", topic: "app")
            NSApp.terminate(nil)
            return
        }

        // 状态栏图标跟随「通用」里的开关和样式，改完立刻换上或收起。
        settingsObserver = Settings.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyStatusItem() }
        applyStatusItem()

        // 初次显示灵动岛。
        notchService.show()

        // 已装集成自愈：内容与本构建不一致（被手工改坏、或残留半截语句）
        // 就重写回去，避免宿主整份拒绝加载后「已安装但一条通知都没有」。
        notchService.repairInstalledIntegrations()

        // 键盘应答 + 设置快捷键接线。气泡右键与菜单栏图标共用 buildMenu()。
        notchService.onOpenSettings = { [weak self] in self?.openSettings() }
        notchService.makeContextMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        notchService.startKeyboard()
        presentOnboardingIfNeeded()
    }

    /// 按当前设置显示或收起菜单栏图标，并换上选中的样式。
    private func applyStatusItem() {
        let settings = Settings.shared
        guard settings.showStatusBarIcon else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = buildMenu()
            statusItem = item
        }
        if let button = statusItem?.button {
            button.image = StatusBarIcon.make(style: settings.statusBarIcon)
            button.toolTip = "BetterFocusIDE"
        }
    }

    /// 菜单栏图标和气泡右键共用的菜单。每次现建一份，避免同一个 NSMenu 被两处同时持有。
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // 气泡所在窗口不是 key window，默认校验会把条目置灰。
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "展开 / 收起灵动岛",
                                action: #selector(toggleNotch), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "最近通知",
                                action: #selector(showHistory), keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "安装 Hook / Plugin…",
                                action: #selector(installAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "卸载 Hook / Plugin",
                                action: #selector(uninstallAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "自检 (Doctor)…",
                                action: #selector(openDoctor), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…",
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "打开日志文件夹",
                                action: #selector(revealLogs), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 BetterFocusIDE",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let ourSelectors: [Selector] = [
            #selector(toggleNotch), #selector(openSettings), #selector(showHistory),
            #selector(installAll), #selector(uninstallAll), #selector(openDoctor),
            #selector(revealLogs)]
        for item in menu.items {
            if let action = item.action, ourSelectors.contains(action) {
                item.target = self
            }
        }
        return menu
    }

    // MARK: - 菜单动作

    @objc private func toggleNotch() {
        notchService.toggle()
    }

    @objc private func showHistory() {
        notchService.showHistory()
    }

    private let hookPicker = HookInstallPickerModel()
    private let onboardingHooks = HookInstallPickerModel()

    /// 先列出本机已安装的受支持宿主，默认全选，只安装勾中的。
    @objc private func installAll() {
        hookPicker.reload()
        guard !hookPicker.items.isEmpty else {
            showAlert(title: "没有可安装的宿主",
                      message: "这台 Mac 上没有检测到受支持的 IDE。")
            return
        }
        presentWindow(title: "安装 Hook / Plugin",
                      rootView: HookInstallPickerView(
                        model: hookPicker,
                        onInstall: { [weak self] in self?.installSelectedHooks() },
                        onCancel: { [weak self] in self?.closeAuxiliaryWindow("安装 Hook / Plugin") }),
                      size: CGSize(width: 460, height: 520))
    }

    private func installSelectedHooks() {
        let ids = hookPicker.selectedIDs
        closeAuxiliaryWindow("安装 Hook / Plugin")
        let summary = notchService.installHooks(ids)
        showAlert(title: "安装完成", message: summary)
    }

    private func closeAuxiliaryWindow(_ title: String) {
        auxiliaryWindows[title]?.orderOut(nil)
    }

    /// 卸载四个宿主的 Hook / Plugin。
    @objc private func uninstallAll() {
        notchService.uninstallAll()
        showAlert(title: "已卸载", message: "Qoder / OpenCode / Cursor / WorkBuddy 的集成已移除。")
    }

    @objc private func openDoctor() {
        presentWindow(title: "自检 (Doctor)", rootView: DoctorView(), size: CGSize(width: 460, height: 420))
    }

    /// 在访达中打开运行日志所在的目录。
    @objc private func revealLogs() {
        guard let url = Log.directoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开设置面板（可调整大小，带最小尺寸约束）。
    @objc private func openSettings() {
        presentWindow(title: "灵动岛设置", rootView: SettingsView(),
                      size: CGSize(width: 760, height: 620),
                      minSize: CGSize(width: 620, height: 420))
    }

    // MARK: - 窗口 / 弹窗辅助

    /// 按标题缓存辅助窗口，避免同一窗口重复创建。
    private var auxiliaryWindows: [String: NSWindow] = [:]

    /// 呈现（或复用）一个承载 SwiftUI 内容的辅助窗口。
    ///
    /// - 若同名窗口已存在：激活应用并前置该窗口。
    /// - 若传入 `minSize`：窗口可调整大小并强制最小尺寸下限
    ///   （设置面板的侧栏 + 读数列不能被压缩到重叠）。
    private func presentWindow<Content: View>(title: String, rootView: Content, size: CGSize,
                                              minSize: CGSize? = nil) {
        if let existing = auxiliaryWindows[title] {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable]
        if let minSize {
            // 可调整大小的面板强制最小尺寸下限，避免侧栏与读数列被压缩到重叠。
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
        }
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        auxiliaryWindows[title] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 弹出信息型模态告警（仅在用户主动操作后调用，非启动路径）。
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 第一次成功启动时弹出引导。关掉窗口后不再出现。
    private func presentOnboardingIfNeeded() {
        guard OnboardingGate.shouldPresent() else { return }
        presentOnboarding()
    }

    /// 打开引导窗口，并从第一页开始。调试页用来反复看版式，不改「下次还要不要自动出现」。
    func presentOnboarding() {
        onboardingHooks.reloadForGuide()
        let title = OnboardingGate.windowTitle
        let size = CGSize(width: 760, height: 640)
        let hosting = NSHostingView(rootView: OnboardingView(
            hooks: onboardingHooks,
            onInstall: { [weak self] in self?.finishOnboarding(install: true) },
            onSkip: { [weak self] in self?.finishOnboarding(install: false) }))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.sizingOptions = []
        let window: NSWindow
        if let existing = auxiliaryWindows[title] {
            window = existing
            window.contentView = hosting
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.contentView = hosting
            window.title = title
            window.isReleasedWhenClosed = false
            window.delegate = self
            auxiliaryWindows[title] = window
        }
        window.setContentSize(size)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            window.setContentSize(size)
            window.center()
        }
    }

    private func finishOnboarding(install: Bool) {
        let ids = onboardingHooks.selectedIDs
        auxiliaryWindows[OnboardingGate.windowTitle]?.close()
        guard install, !ids.isEmpty else { return }
        let summary = notchService.installHooks(ids)
        showAlert(title: "安装完成", message: summary)
    }

    /// 应用退出前收尾：停止 socket 监听、持久化设置。
    func applicationWillTerminate(_ notification: Notification) {
        notchService.stopSocket()
        Settings.shared.save()
        CrashLog.markCleanExit()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == OnboardingGate.windowTitle else { return }
        OnboardingGate.markCompleted()
    }
}
