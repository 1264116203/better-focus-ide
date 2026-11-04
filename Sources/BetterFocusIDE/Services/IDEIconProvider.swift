// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// IDE 图标提供者：根据宿主应用名称返回对应的图标 Image。
///
/// 支持真实图标的 IDE（从 Resources/IDE-Icons 加载）：
/// - IntelliJ IDEA, PyCharm, WebStorm, GoLand, Rider, CLion, PhpStorm, RubyMine
/// - VS Code（用于 Qoder IDE 等 VS Code 系 fork）
///
/// 其他 IDE 使用带品牌色的文字徽章：
/// - Cursor（青色）
/// - Claude Code（橙色）
/// - Codex / OpenAI（绿色）
/// - Qoder（紫色）
/// - OpenCode（蓝绿色）
enum IDEIconProvider {
    /// IDE 名称到图标文件名的映射（小写匹配）
    private static let iconMapping: [String: String] = [
        // JetBrains IDEs
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
        // VS Code 系（Qoder IDE, Qoder CN IDE, Cursor 等都是 VS Code fork）
        "visual studio code": "vscode",
        "vscode": "vscode",
        "qoder ide": "vscode",
        "qoder cn ide": "vscode",
        "cursor": "vscode",  // Cursor 也是 VS Code fork
    ]

    /// IDE 名称到品牌色的映射（用于文字徽章背景）
    private static let brandColors: [String: (r: Double, g: Double, b: Double)] = [
        // Qoder 系列 - 紫色
        "qoder": (0.58, 0.45, 0.82),
        "qoder ide": (0.58, 0.45, 0.82),
        "qoder work": (0.58, 0.45, 0.82),
        "qoder cn": (0.58, 0.45, 0.82),
        "qoder cn ide": (0.58, 0.45, 0.82),
        "qoder cn work": (0.58, 0.45, 0.82),
        "通义灵码": (0.58, 0.45, 0.82),
        // Cursor - 青色/蓝色
        "cursor": (0.0, 0.55, 0.75),
        // Claude Code - 橙色
        "claude": (0.85, 0.55, 0.25),
        "claude code": (0.85, 0.55, 0.25),
        "anthropic": (0.85, 0.55, 0.25),
        // Codex / OpenAI - 绿色
        "codex": (0.15, 0.65, 0.45),
        "openai": (0.15, 0.65, 0.45),
        // OpenCode - 蓝绿色
        "opencode": (0.06, 0.73, 0.51),
        // 终端/CLI - 灰色
        "terminal": (0.4, 0.4, 0.45),
        "iterm": (0.4, 0.4, 0.45),
        "warp": (0.4, 0.4, 0.45),
        "ghostty": (0.4, 0.4, 0.45),
        "kitty": (0.4, 0.4, 0.45),
        "alacritty": (0.4, 0.4, 0.45),
        "wezterm": (0.4, 0.4, 0.45),
    ]

    /// 检查是否有对应 IDE 名称的真实图标
    static func hasIcon(for hostName: String?) -> Bool {
        guard let name = hostName?.lowercased() else { return false }
        for (key, _) in iconMapping {
            if name.contains(key) { return true }
        }
        return false
    }

    /// 获取 IDE 图标（如果有真实图标），否则返回 nil
    static func icon(for hostName: String?) -> Image? {
        guard let name = hostName?.lowercased() else { return nil }
        
        for (key, iconName) in iconMapping {
            if name.contains(key) {
                if let image = loadImage(named: iconName) {
                    return image
                }
            }
        }
        return nil
    }

    /// 获取 IDE 的品牌色
    static func brandColor(for hostName: String?) -> Color {
        guard let name = hostName?.lowercased() else {
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
        
        for (key, color) in brandColors {
            if name.contains(key) {
                return Color(red: color.r, green: color.g, blue: color.b)
            }
        }
        // 默认灰色
        return Color(red: 0.5, green: 0.5, blue: 0.5)
    }

    /// 获取徽章视图：优先使用真实图标，回退到带品牌色的文字徽章
    /// - Parameters:
    ///   - hostName: 宿主应用名称（如 "IntelliJ IDEA"、"Cursor"）
    ///   - fallbackText: 文字徽章内容（首字母）
    ///   - tint: 默认背景色（当无法匹配品牌色时使用）
    ///   - size: 徽章尺寸
    @ViewBuilder
    static func badgeView(hostName: String?, fallbackText: String, tint: Color, size: CGFloat = 24) -> some View {
        if let icon = icon(for: hostName) {
            // 真实图标
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            // 带品牌色的文字徽章
            let bgColor = hasBrandColor(for: hostName) ? brandColor(for: hostName) : tint
            // 确保文字不为空
            let displayText = fallbackText.isEmpty ? "?" : fallbackText
            Text(displayText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(bgColor.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// 检查是否有对应的品牌色
    private static func hasBrandColor(for hostName: String?) -> Bool {
        guard let name = hostName?.lowercased() else { return false }
        for (key, _) in brandColors {
            if name.contains(key) { return true }
        }
        return false
    }

    /// 从 Resources 目录加载图片
    private static func loadImage(named: String) -> Image? {
        #if canImport(AppKit)
        // 方式1：尝试从 BetterFocusIDE_BetterFocusIDE.bundle 加载
        let bundleName = "BetterFocusIDE_BetterFocusIDE.bundle"
        var searchPaths: [URL] = []
        
        // SwiftPM build 时的路径
        if let path = Bundle.main.resourceURL?.appendingPathComponent(bundleName) {
            searchPaths.append(path)
        }
        // App 打包后的路径
        searchPaths.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(bundleName))
        // Bundle.module（SwiftPM 资源包）
        searchPaths.append(Bundle.module.bundleURL)
        
        for basePath in searchPaths {
            let iconPath = basePath.appendingPathComponent("IDE-Icons").appendingPathComponent(named).appendingPathExtension("png")
            if FileManager.default.fileExists(atPath: iconPath.path),
               let nsImage = NSImage(contentsOf: iconPath) {
                return Image(nsImage: nsImage)
            }
        }
        
        // 方式2：直接在资源路径中搜索
        if let resourcePath = Bundle.main.resourcePath {
            let directPath = (resourcePath as NSString).appendingPathComponent("IDE-Icons/\(named).png")
            if FileManager.default.fileExists(atPath: directPath),
               let nsImage = NSImage(contentsOfFile: directPath) {
                return Image(nsImage: nsImage)
            }
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
