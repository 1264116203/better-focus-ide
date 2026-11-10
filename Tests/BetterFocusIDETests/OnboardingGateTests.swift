// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

final class OnboardingGateTests: XCTestCase {
    private let suite = "OnboardingGateTests"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testHiddenAfterCompletion() {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertTrue(OnboardingGate.shouldPresent(defaults: defaults))
        OnboardingGate.markCompleted(defaults: defaults)
        XCTAssertFalse(OnboardingGate.shouldPresent(defaults: defaults))
    }

    func testLastPageIsHookInstall() {
        XCTAssertEqual(OnboardingGate.Page.allCases.count, 4)
        XCTAssertEqual(OnboardingGate.Page.allCases.last, .install)
    }
}
