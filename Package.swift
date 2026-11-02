// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import PackageDescription

let package = Package(
    name: "BetterFocusIDE",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BetterFocusIDE",
            path: "Sources/BetterFocusIDE"
        )
    ]
)
