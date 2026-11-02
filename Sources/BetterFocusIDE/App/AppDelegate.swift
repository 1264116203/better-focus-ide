// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var notchService: NotchService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Single-instance guard first: if another island already holds the
        // socket, exit before raising a second (ghost) island. A duplicate
        // launch of a background accessory app should no-op silently (like
        // most menu-bar tools) — a modal alert here would block this thread
        // and leave the rejected process hanging instead of quitting.
        notchService = NotchService.shared
        switch notchService.startSocket() {
        case .started:
            break
        case .alreadyRunning:
            Log.info("another instance already holds the socket; exiting.", topic: "app")
            NSApp.terminate(nil)
            return
        case .failed(let error):
            Log.error("socket start failed (\(error)); exiting.", topic: "app")
            NSApp.terminate(nil)
            return
        }

        // Set up status bar item with a menu.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule", accessibilityDescription: "BetterFocusIDE")
        }
        statusItem.menu = buildMenu()

        // Show the notch initially
        notchService.show()

        // Keyboard answering + settings shortcut wiring.
        notchService.onOpenSettings = { [weak self] in self?.openSettings() }
        notchService.startKeyboard()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "展开 / 收起灵动岛",
                                action: #selector(toggleNotch), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "最近通知",
                                action: #selector(showHistory), keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "一键安装 Hook / Plugin",
                                action: #selector(installAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "卸载 Hook / Plugin",
                                action: #selector(uninstallAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "自检 (Doctor)…",
                                action: #selector(openDoctor), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…",
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 BetterFocusIDE",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let ourSelectors: [Selector] = [
            #selector(toggleNotch), #selector(openSettings), #selector(showHistory),
            #selector(installAll), #selector(uninstallAll), #selector(openDoctor)]
        for item in menu.items {
            if let action = item.action, ourSelectors.contains(action) {
                item.target = self
            }
        }
        return menu
    }

    @objc private func toggleNotch() {
        notchService.toggle()
    }

    @objc private func showHistory() {
        notchService.showHistory()
    }

    @objc private func installAll() {
        let summary = notchService.installAll()
        showAlert(title: "安装完成", message: summary)
    }

    @objc private func uninstallAll() {
        notchService.uninstallAll()
        showAlert(title: "已卸载", message: "Qoder Hook 与 OpenCode Plugin 已移除。")
    }

    @objc private func openDoctor() {
        presentWindow(title: "自检 (Doctor)", rootView: DoctorView(), size: CGSize(width: 460, height: 420))
    }

    @objc private func openSettings() {
        presentWindow(title: "灵动岛设置", rootView: SettingsView(),
                      size: CGSize(width: 760, height: 620),
                      minSize: CGSize(width: 620, height: 420))
    }

    // MARK: - Window / alert helpers

    private var auxiliaryWindows: [String: NSWindow] = [:]

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
            // Resizable panels (settings) enforce a floor so the sidebar +
            // readout columns never collapse into each other.
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

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchService.stopSocket()
        Settings.shared.save()
    }
}
