// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import PackageDescription

let package = Package(
    name: "BetterFocusIDE",
    platforms: [.macOS(.v14)],
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
            exclude: ["App/main.swift"]
        ),
        // 瘦 Executable 目标：仅编译 App/main.swift，依赖 library。
        // 该目标映射为 productType=com.apple.product-type.tool（二进制名 BetterFocusIDEApp）。
        .executableTarget(
            name: "BetterFocusIDEApp",
            dependencies: ["BetterFocusIDE"],
            path: "Sources/BetterFocusIDE/App",
            sources: ["main.swift"]
        ),
    ]
)
