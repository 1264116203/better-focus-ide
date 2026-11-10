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
    }

    func testPresentHostsAreASubset() {
        let present = Set(HookInstallCatalog.present().map(\.id))
        let all = Set(HookInstallCatalog.all.map(\.id))
        XCTAssertTrue(present.isSubset(of: all))
    }
}
