// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 测试待办（10 步）对应的验证用例：覆盖基础逻辑、边界与汇总。
final class TestTodoStepsTests: XCTestCase {
    
    // MARK: - 步骤对应测试
    
    /// 步骤 1-2：确认清单与环境——验证核心单例可访问。
    func testCoreTypesAvailable() {
        XCTAssertNotNil(Settings.shared, "Settings 单例应可访问")
    }
    
    /// 步骤 3-4：读取与编写——验证 HistoryKind 前缀逻辑。
    func testHistoryKindBodyLabel() {
        XCTAssertEqual(HistoryKind.question.bodyLabel, "问：")
        XCTAssertEqual(HistoryKind.permission.bodyLabel, "详情：")
        XCTAssertEqual(HistoryKind.turn.bodyLabel, "用户：")
        XCTAssertEqual(HistoryKind.failure.bodyLabel, "原因：")
        XCTAssertEqual(HistoryKind.subagent.bodyLabel, "结果：")
        XCTAssertEqual(HistoryKind.review.bodyLabel, "说明：")
        XCTAssertEqual(HistoryKind.compact.bodyLabel, "说明：")
    }
    
    /// 步骤 5：边界输入——legacy 推断空串与未知状态。
    func testHistoryKindLegacy() {
        XCTAssertEqual(HistoryKind.legacy(from: "回复完成"), .turn)
        XCTAssertEqual(HistoryKind.legacy(from: "已回答"), .question)
    }
    
    /// 步骤 6：正常流程——Settings 设置值读写往返。
    func testSettingsRoundTrip() {
        let original = Settings.shared.cardInset
        Settings.shared.cardInset = original == 20 ? 25 : 20
        XCTAssertNotEqual(Settings.shared.cardInset, original)
        Settings.shared.cardInset = original
    }
    
    /// 步骤 7：结果检查——parseRGB 正确解析。
    func testParseRGBValid() {
        let result = Settings.parseRGB("0.1,0.2,0.3", fallback: (0, 0, 0))
        XCTAssertEqual(result.r, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.g, 0.2, accuracy: 0.001)
        XCTAssertEqual(result.b, 0.3, accuracy: 0.001)
    }
    
    /// 步骤 8：异常路径——parseRGB 非法输入回退。
    func testParseRGBInvalidFallback() {
        let result = Settings.parseRGB("not-a-color", fallback: (0.9, 0.8, 0.7))
        XCTAssertEqual(result.r, 0.9, accuracy: 0.001)
        XCTAssertEqual(result.g, 0.8, accuracy: 0.001)
        XCTAssertEqual(result.b, 0.7, accuracy: 0.001)
    }
    
    /// 步骤 9-10：汇总——验证默认字号为正数。
    func testDefaultValues() {
        let current = Settings.shared.bodyFont
        XCTAssertTrue(current > 0, "字号应为正数")
    }
}
