// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import ApplicationServices
import XCTest
@testable import BetterFocusIDE

final class AutomationPermissionTests: XCTestCase {
    func testInterpretMapsAppleEventStatuses() {
        XCTAssertEqual(AutomationPermission.interpret(noErr), .allowed)
        XCTAssertEqual(AutomationPermission.interpret(OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(AutomationPermission.interpret(OSStatus(errAEEventWouldRequireUserConsent)), .notDetermined)
        XCTAssertEqual(AutomationPermission.interpret(OSStatus(procNotFound)), .notRunning)
        XCTAssertEqual(AutomationPermission.interpret(-1), .unknown)
    }

    func testInstalledTargetsLeadWithSystemEvents() {
        let targets = AutomationPermission.installedTargets()
        XCTAssertEqual(targets.first?.bundle, AutomationPermission.systemEventsBundle)
        XCTAssertEqual(targets.first?.kind, .system)
        let bundles = targets.map(\.bundle)
        XCTAssertEqual(Set(bundles).count, bundles.count, "同一个应用不应列两次")
    }
}
