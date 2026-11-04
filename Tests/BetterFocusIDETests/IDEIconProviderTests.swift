// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
import SwiftUI
@testable import BetterFocusIDE

/// 徽章图标「等大」的回归测试。
///
/// 图标源的留白差异实测很大：JetBrains 系满画布（包围盒 1.00），Cursor 0.803、
/// WorkBuddy 0.801、Qoder 0.773。若不裁切，同样塞进 30pt 框里视觉大小能差 25%。
/// 这里把每个图标离屏渲染成 30pt（@2x = 60px）位图，直接量不透明像素的包围盒。
final class IDEIconProviderTests: XCTestCase {

    /// 源码树里的图标目录（测试进程拿不到库目标的 Bundle.module 资源）。
    private var iconDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // BetterFocusIDETests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // 仓库根
            .appendingPathComponent("Sources/BetterFocusIDE/Resources/IDE-Icons")
    }

    private var iconNames: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: iconDir.path))?
            .filter { $0.hasSuffix(".png") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted() ?? []
    }

    /// 裁切后内容必须填满画布（≥97%），否则说明包围盒没算对。
    func testTrimFillsBoundingBox() throws {
        let names = iconNames
        XCTAssertGreaterThan(names.count, 10, "图标资源目录没找到")

        for name in names {
            let url = iconDir.appendingPathComponent(name).appendingPathExtension("png")
            guard let raw = NSImage(contentsOf: url) else {
                XCTFail("读不到 \(name).png"); continue
            }
            let cropped = IDEIconProvider.trimmed(raw)
            let box = try XCTUnwrap(alphaBoundingBox(cropped), "\(name) 全透明")
            XCTAssertGreaterThan(box.width, 0.97, "\(name) 裁切后仍有横向留白 \(box.width)")
            XCTAssertGreaterThan(box.height, 0.97, "\(name) 裁切后仍有纵向留白 \(box.height)")
        }
    }

    /// 渲染成 30pt（@2x=60px）后，每个图标的不透明范围必须接近满格。
    ///
    /// 这条断言直接对应「卡片里的 IDE 图标看起来一样大」——只要每个图标都
    /// 填满同一个 60×60 的格子，视觉尺寸就一致。
    @MainActor
    func testRenderedBadgesOccupySameArea() throws {
        let size = IDEIconProvider.badgeSize
        XCTAssertEqual(size, 30, "尺寸常量变了，下面的像素断言要跟着更新")

        var failed: [String] = []
        for name in iconNames {
            let url = iconDir.appendingPathComponent(name).appendingPathExtension("png")
            guard let raw = NSImage(contentsOf: url) else { continue }
            let view = Image(nsImage: IDEIconProvider.trimmed(raw))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let rendered = renderer.nsImage else {
                XCTFail("\(name) 渲染失败"); continue
            }
            let box = try XCTUnwrap(alphaBoundingBox(rendered), "\(name) 渲染后全透明")
            // 30pt @2x = 60px；允许 1px 的抗锯齿误差。
            let longSide = max(box.width, box.height) * 60
            if longSide < 58 {
                failed.append(String(format: "%@ 长边 %.1fpx", name, longSide))
            }
        }
        XCTAssertTrue(failed.isEmpty, "以下图标没填满 30pt 框：" + failed.joined(separator: ", "))
    }

    /// 名称 / bundle 解析仍能命中图标（改尺寸不该动匹配逻辑）。
    func testIconLookupStillWorks() {
        XCTAssertNotNil(IDEIconProvider.icon(for: "Cursor"))
        XCTAssertNotNil(IDEIconProvider.icon(for: "WorkBuddy"))
        XCTAssertNotNil(IDEIconProvider.icon(for: "Qoder", bundleID: "com.qoder.ide"))
        XCTAssertNil(IDEIconProvider.icon(for: "Unknown App"))
        // 注意（既有行为，不属本次改动）：名称走子串匹配，"code" 会让任何含
        // code 的名字都判成 VS Code（如 "Claude Code"）。宿主名取的是 .app 的
        // CFBundleName，实际不会撞上；将来要给 CLI 宿主配图标时需先补精确匹配。
    }

    // MARK: - 工具

    /// 返回不透明像素占整幅图的比例（宽、高）；全透明返回 nil。
    private func alphaBoundingBox(_ image: NSImage) -> (width: Double, height: Double)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0, maxY >= 0 else { return nil }
        return (Double(maxX - minX + 1) / Double(w), Double(maxY - minY + 1) / Double(h))
    }
}
