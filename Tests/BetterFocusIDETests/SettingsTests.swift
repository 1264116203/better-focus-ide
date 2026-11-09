// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
import Combine
@testable import BetterFocusIDE

/// 测试设置系统的核心功能：变更广播、持久化、视图观察。
final class SettingsTests: XCTestCase {
    
    var cancellables: Set<AnyCancellable> = []
    
    override func setUp() {
        super.setUp()
        cancellables = []
    }
    
    override func tearDown() {
        cancellables = []
        super.tearDown()
    }
    
    // MARK: - 变更广播测试
    
    /// 测试：修改设置后，changes 主题应广播变更事件。
    func testMarkChangedBroadcastsEvent() {
        let expectation = expectation(description: "changes should broadcast")
        expectation.expectedFulfillmentCount = 1
        
        Settings.shared.changes
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 修改任意设置
        let originalValue = Settings.shared.bodyFont
        Settings.shared.bodyFont = originalValue + 1
        Settings.shared.markChanged()
        
        // 恢复原值
        Settings.shared.bodyFont = originalValue
        
        waitForExpectations(timeout: 1.0)
    }
    
    /// 测试：修改多个设置时，changes 应广播多次。
    func testMultipleChangesBroadcastMultipleTimes() {
        var broadcastCount = 0
        
        Settings.shared.changes
            .sink { _ in
                broadcastCount += 1
            }
            .store(in: &cancellables)
        
        let originalBody = Settings.shared.bodyFont
        let originalOption = Settings.shared.optionFont
        
        Settings.shared.bodyFont = originalBody + 1
        Settings.shared.markChanged()
        
        Settings.shared.optionFont = originalOption + 1
        Settings.shared.markChanged()
        
        // 恢复原值
        Settings.shared.bodyFont = originalBody
        Settings.shared.optionFont = originalOption
        
        XCTAssertEqual(broadcastCount, 2, "Should broadcast twice for two changes")
    }
    
    // MARK: - 设置值读写测试
    
    /// 测试：bodyFont 设置能正确读写。
    func testBodyFontReadWrite() {
        let originalValue = Settings.shared.bodyFont
        let newValue = originalValue == 14 ? 16.0 : 14.0
        
        Settings.shared.bodyFont = newValue
        XCTAssertEqual(Settings.shared.bodyFont, newValue, "bodyFont should be updated")
        
        // 恢复原值
        Settings.shared.bodyFont = originalValue
    }
    
    /// 测试：cardInset 设置能正确读写。
    func testCardInsetReadWrite() {
        let originalValue = Settings.shared.cardInset
        let newValue = originalValue == 20 ? 25.0 : 20.0
        
        Settings.shared.cardInset = newValue
        XCTAssertEqual(Settings.shared.cardInset, newValue, "cardInset should be updated")
        
        // 恢复原值
        Settings.shared.cardInset = originalValue
    }
    
    /// 测试：cardWidth 设置能正确读写。
    func testCardWidthReadWrite() {
        let originalValue = Settings.shared.cardWidth
        let newValue = originalValue == 500 ? 600.0 : 500.0
        
        Settings.shared.cardWidth = newValue
        XCTAssertEqual(Settings.shared.cardWidth, newValue, "cardWidth should be updated")
        
        // 恢复原值
        Settings.shared.cardWidth = originalValue
    }
    
    // MARK: - SettingCatalog 测试
    
    /// 测试：SettingCatalog.byKey 能正确查找设置定义。
    ///
    /// 尺寸页已从面板拿掉，改用仍留在目录里的背景不透明度。
    func testSettingCatalogByKey() {
        let def = SettingCatalog.byKey("backgroundAlpha")
        XCTAssertNotNil(def, "Should find backgroundAlpha definition")
        XCTAssertEqual(def?.key, "backgroundAlpha")
        XCTAssertEqual(def?.label, "背景不透明度")
    }
    
    /// 测试：SettingCatalog 的 get/set 闭包能正确读写 Settings。
    func testSettingCatalogGetSet() {
        guard let def = SettingCatalog.byKey("backgroundAlpha") else {
            XCTFail("backgroundAlpha definition not found")
            return
        }
        
        let originalValue = Settings.shared.backgroundAlpha
        
        def.set(.double(originalValue + 0.01))
        
        XCTAssertEqual(Settings.shared.backgroundAlpha, originalValue + 0.01, "Settings should be updated via catalog")
        
        if case .double(let value) = def.get() {
            XCTAssertEqual(value, originalValue + 0.01, "Catalog get should return updated value")
        } else {
            XCTFail("Expected double value")
        }
        
        def.set(.double(originalValue))
    }
    
    // MARK: - 持久化测试
    
    /// 测试：save() 和 load() 能正确持久化和恢复设置。
    func testSaveAndLoad() {
        let originalBody = Settings.shared.bodyFont
        let originalWidth = Settings.shared.cardWidth
        
        // 修改设置
        Settings.shared.bodyFont = 15
        Settings.shared.cardWidth = 600
        Settings.shared.save()
        
        // 重新加载
        Settings.shared.load()
        
        XCTAssertEqual(Settings.shared.bodyFont, 15, "bodyFont should be persisted and loaded")
        XCTAssertEqual(Settings.shared.cardWidth, 600, "cardWidth should be persisted and loaded")
        
        // 恢复原值
        Settings.shared.bodyFont = originalBody
        Settings.shared.cardWidth = originalWidth
        Settings.shared.save()
    }
    
    // MARK: - RGB 颜色解析测试
    
    /// 测试：parseRGB 能正确解析颜色字符串。
    func testParseRGB() {
        let result = Settings.parseRGB("0.5,0.6,0.7", fallback: (0, 0, 0))
        XCTAssertEqual(result.r, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.g, 0.6, accuracy: 0.001)
        XCTAssertEqual(result.b, 0.7, accuracy: 0.001)
    }
    
    /// 测试：parseRGB 在格式错误时返回 fallback。
    func testParseRGBFallback() {
        let result = Settings.parseRGB("invalid", fallback: (0.1, 0.2, 0.3))
        XCTAssertEqual(result.r, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.g, 0.2, accuracy: 0.001)
        XCTAssertEqual(result.b, 0.3, accuracy: 0.001)
    }
    
    /// 测试：rgbString 能正确格式化颜色三元组。
    func testRgbString() {
        let result = Settings.rgbString(0.5, 0.6, 0.7)
        XCTAssertTrue(result.contains("0.5"))
        XCTAssertTrue(result.contains("0.6"))
        XCTAssertTrue(result.contains("0.7"))
    }
    
    // MARK: - 重置测试
    
    /// 测试：resetAll() 能恢复所有设置为默认值。
    func testResetAll() {
        // 先修改一些设置
        Settings.shared.bodyFont = 18
        Settings.shared.cardWidth = 700
        
        // 重置
        Settings.shared.resetAll()
        
        // 验证恢复为默认值
        XCTAssertEqual(Settings.shared.bodyFont, 12, "bodyFont should reset to default")
        XCTAssertEqual(Settings.shared.cardWidth, 540, "cardWidth should reset to default")
    }
}
