// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// IDE 图标提供者：根据宿主应用名称返回对应的图标 Image。
///
/// 支持的 IDE 图标（从 Resources/IDE-Icons 加载）：
/// - IntelliJ IDEA → intellij-idea.png
/// - PyCharm → pycharm.png
/// - WebStorm → webstorm.png
/// - GoLand → goland.png
/// - Rider → rider.png
/// - CLion → clion.png
/// - PhpStorm → phpstorm.png
/// - RubyMine → rubymine.png
///
/// 对于无法识别的 IDE（如 Qoder、OpenCode、终端等），回退到文字徽章（首字母）。
enum IDEIconProvider {
    /// IDE 名称到图标文件名的映射（小写匹配）
    private static let iconMapping: [String: String] = [
        "intellij idea": "intellij-idea",
        "intellij_idea": "intellij-idea",
        "intellij": "intellij-idea",
        "pycharm": "pycharm",
        "webstorm": "webstorm",
        "goland": "goland",
        "rider": "rider",
        "clion": "clion",
        "phpstorm": "phpstorm",
        "rubymine": "rubymine",
    ]

    /// 检查是否有对应 IDE 名称的图标
    static func hasIcon(for hostName: String?) -> Bool {
        guard let name = hostName?.lowercased() else { return false }
        for (key, _) in iconMapping {
            if name.contains(key) { return true }
        }
        return false
    }

    /// 获取 IDE 图标（如果有），否则返回 nil
    static func icon(for hostName: String?) -> Image? {
        guard let name = hostName?.lowercased() else { return nil }
        
        for (key, iconName) in iconMapping {
            if name.contains(key) {
                // 尝试从 Bundle 加载图标
                if let image = loadImage(named: iconName) {
                    return image
                }
            }
        }
        return nil
    }

    /// 获取徽章视图：优先使用图标，回退到文字徽章
    /// - Parameters:
    ///   - hostName: 宿主应用名称（如 "IntelliJ IDEA"）
    ///   - fallbackText: 文字徽章内容（首字母）
    ///   - tint: 背景色
    ///   - size: 徽章尺寸
    @ViewBuilder
    static func badgeView(hostName: String?, fallbackText: String, tint: Color, size: CGFloat = 24) -> some View {
        if let icon = icon(for: hostName) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Text(fallbackText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// 从 Resources 目录加载图片
    private static func loadImage(named: String) -> Image? {
        #if canImport(AppKit)
        // SwiftPM 资源访问：Bundle.module 指向 BetterFocusIDE_BetterFocusIDE.bundle
        if let bundleURL = Bundle.module.url(forResource: named, withExtension: "png", subdirectory: "IDE-Icons"),
           let nsImage = NSImage(contentsOf: bundleURL) {
            return Image(nsImage: nsImage)
        }
        // 回退：尝试从主 Bundle 加载（app 打包后）
        if let appBundle = Bundle.main.resourceURL?.appendingPathComponent("BetterFocusIDE_BetterFocusIDE.bundle"),
           let bundleURL = appBundle.appendingPathComponent("IDE-Icons").appendingPathComponent(named).appendingPathExtension("png") as URL?,
           FileManager.default.fileExists(atPath: bundleURL.path),
           let nsImage = NSImage(contentsOf: bundleURL) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }

    /// 获取文字徽章（首字母大写）
    static func textBadge(for hostName: String?, fallback: String) -> String {
        let name = hostName ?? fallback
        return String(name.prefix(1)).uppercased()
    }
}
