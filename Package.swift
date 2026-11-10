// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import PackageDescription

// 部署目标是 macOS 15。语言模式保持 Swift 5，避免整包切到 Swift 6 并发检查。
let swift5 = [SwiftSetting.swiftLanguageMode(.v5)]

let package = Package(
    name: "BetterFocusIDE",
    platforms: [.macOS(.v15)],
    products: [
        // 库产品：供 SwiftUI Preview 使用（Xcode Canvas 要求 library 目标）。
        .library(name: "BetterFocusIDE", targets: ["BetterFocusIDE"]),
    ],
    targets: [
        // Library 目标：包含除 App/main.swift 外的全部源码。
        // 该目标映射为 productType=com.apple.product-type.framework/library，
        // 支持 Xcode SwiftUI Preview。
        .target(
            name: "BetterFocusIDE",
            path: "Sources/BetterFocusIDE",
            exclude: ["App/main.swift"],
            resources: [
                // IDE 图标资源（用于徽章显示真实 IDE 图标）
                .copy("Resources/IDE-Icons"),
                // 首次引导页的实拍
                .copy("Resources/Onboarding"),
                // JetBrains ACP 会话的 stdio 桥。安装时拷到 Application Support。
                .copy("Resources/acp-bridge.py")
            ],
            swiftSettings: swift5
        ),
        // 瘦 Executable 目标：仅编译 App/main.swift，依赖 library。
        // 该目标映射为 productType=com.apple.product-type.tool（二进制名 BetterFocusIDEApp）。
        .executableTarget(
            name: "BetterFocusIDEApp",
            dependencies: ["BetterFocusIDE"],
            path: "Sources/BetterFocusIDE/App",
            sources: ["main.swift"],
            swiftSettings: swift5
        ),
        // 测试目标：验证设置系统、控制器逻辑等核心功能。
        .testTarget(
            name: "BetterFocusIDETests",
            dependencies: ["BetterFocusIDE"],
            path: "Tests/BetterFocusIDETests",
            swiftSettings: swift5
        ),
    ]
)
