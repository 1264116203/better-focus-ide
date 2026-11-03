// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

/// 库入口：把原本散落在可执行目标 `main.swift` 里的初始化流程
/// （日志 → 创建 AppDelegate → 进入主事件循环）封装为单一公开函数，
/// 供瘦 executable 目标调用。
///
/// 该函数位于 library 目标内部，可直接实例化同模块的 `AppDelegate`
/// （`AppDelegate` 保持 internal 访问级别，不对外暴露）。
public func run() {
    Log.setup()
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
