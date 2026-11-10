// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

final class HookInstallCatalogTests: XCTestCase {
    func testHostIDsAreUniqueAndStable() {
        let ids = HookInstallCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, "qoder")
        XCTAssertTrue(ids.contains("cursor"))
        XCTAssertTrue(ids.contains("copilot"))
        XCTAssertTrue(HookInstallCatalog.all.allSatisfy { !$0.hint.isEmpty })
    }

    func testCheckboxFollowsInstalledApplications() {
        let ids = Set(HookInstallCatalog.all.map(\.id))
        XCTAssertEqual(ids, Set(HookInstallCatalog.applicationBundles.keys))
        let installed: Set<String> = [
            "com.qoder.ide",
            "com.todesktop.230313mzl4w4u92",
        ]
        XCTAssertFalse(HookInstallCatalog.isApplicationPresent(id: "qoder") { installed.contains($0) })
        XCTAssertTrue(HookInstallCatalog.isApplicationPresent(id: "qoder-ide") { installed.contains($0) })
        XCTAssertFalse(HookInstallCatalog.isApplicationPresent(id: "qoder-cn") { installed.contains($0) })
        XCTAssertTrue(HookInstallCatalog.isApplicationPresent(id: "qoder-cn-ide") {
            $0 == "com.aliyun.lingma.ide"
        })
        XCTAssertTrue(HookInstallCatalog.isApplicationPresent(id: "cursor") { installed.contains($0) })
        XCTAssertFalse(HookInstallCatalog.isApplicationPresent(id: "opencode") { installed.contains($0) })
        XCTAssertTrue(HookInstallCatalog.isApplicationPresent(id: "copilot") {
            $0 == "com.github.githubapp"
        })
        XCTAssertEqual(HookInstallCatalog.applicationBundles["qoder"], ["com.qoder.app"])
        XCTAssertEqual(HookInstallCatalog.applicationBundles["qoder-ide"], ["com.qoder.ide"])
        XCTAssertEqual(HookInstallCatalog.applicationBundles["opencode"], ["ai.opencode.desktop"])
        XCTAssertTrue(HookInstallCatalog.matchesCLI(
            path: "/Users/me/.qoder/bin/qodercli", kind: .english))
        XCTAssertFalse(HookInstallCatalog.matchesCLI(
            path: "/Applications/Qoder IDE.app/Contents/Resources/app/bin/qoder", kind: .english))
        XCTAssertFalse(HookInstallCatalog.matchesCLI(
            path: "/Users/me/.qoder-cn/bin/qodercli", kind: .english))
        XCTAssertTrue(HookInstallCatalog.matchesCLI(
            path: "/Users/me/.qoder-cn/bin/qodercli", kind: .cn))
        XCTAssertFalse(HookInstallCatalog.matchesCLI(
            path: "/Users/me/.qoder/bin/qodercli", kind: .cn))
    }

    func testPresentHostsAreASubset() {
        let present = Set(HookInstallCatalog.present().map(\.id))
        let all = Set(HookInstallCatalog.all.map(\.id))
        XCTAssertTrue(present.isSubset(of: all))
    }
}
