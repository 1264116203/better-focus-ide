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

    /// 深色图标必须靠一圈亮边把方块边界「勾」出来。
    ///
    /// Cursor 的图标是近黑方块（平均亮度 0.23），面板底色是 0.28 —— 没有亮边时
    /// 方块边界几乎看不见，只剩中间那个灰色立方体可见，看起来就比 WorkBuddy /
    /// Qoder 小一圈（用户实际反馈）。这里把徽章压到面板同色背景上渲染，断言
    /// 边缘一圈确实比内部底色亮。
    @MainActor
    func testDarkIconGetsVisibleRim() throws {
        let size = IDEIconProvider.badgeSize
        let view = ZStack {
            Color(white: 0.28)
            IDEIconProvider.badgeView(hostName: "Cursor", fallbackText: "C", tint: .gray, size: size)
        }
        .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4
        let rendered = try XCTUnwrap(renderer.nsImage, "Cursor 徽章渲染失败")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: rendered.tiffRepresentation!))

        // 左侧边缘取一列，避开圆角：只在竖直中段采样。
        func meanLuminance(atX x: Int) -> Double {
            var sum = 0.0, n = 0
            let h = rep.pixelsHigh
            for y in (h / 3)..<(h * 2 / 3) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                sum += 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                n += 1
            }
            return n > 0 ? sum / Double(n) : 0
        }

        // 0.5pt 的边在 @4x 下只有 2px 宽：取第 1 列，第 2 列已经在图标内部了。
        let rim = meanLuminance(atX: 1)
        let inner = meanLuminance(atX: 10)
        XCTAssertGreaterThan(rim, inner + 0.04,
                             "图标边缘没被提亮（边缘 \(rim) vs 内部 \(inner)），深色图标会糊在面板里")
    }

    /// 名称 / bundle 解析仍能命中图标（改尺寸不该动匹配逻辑）。
    func testIconLookupStillWorks() {
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "ChatGPT", bundleID: "com.openai.codex"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "Codex"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "Claude"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "Claude Code", bundleID: "com.anthropic.claudefordesktop"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "Copilot"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "GitHub Copilot", bundleID: "com.github.githubapp"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "WorkBuddy AI", bundleID: "com.workbuddy.workbuddy-ai"))
        XCTAssertTrue(IDEIconProvider.hasIcon(for: "WebStorm", bundleID: "com.jetbrains.WebStorm"))
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "JetBrains"), "jetbrains")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "JetBrains ACP"), "jetbrains")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "DataGrip", bundleID: "com.jetbrains.datagrip"), "jetbrains")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij"), "intellij-idea")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "Claude Code"), "claude")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "Code"), "vscode")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "Cursor"), "cursor")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "WorkBuddy"), "workbuddy")
        XCTAssertEqual(IDEIconProvider.resolvedIconName(for: "Qoder", bundleID: "com.qoder.ide"), "qoder-ide")
        XCTAssertNil(IDEIconProvider.resolvedIconName(for: "Unknown App"))
        // VS Code 的 CFBundleName 就是 "Code"，短键只能留给这个名字。
        // 更长的名字（Claude Code）必须先命中自己的键。
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
