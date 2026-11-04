// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// IDE 图标提供者：根据宿主应用名称返回对应的图标 Image。
///
/// 支持真实图标的 IDE（从 Resources/IDE-Icons 加载）：
/// - JetBrains: IntelliJ IDEA, PyCharm, WebStorm, GoLand, Rider, CLion, PhpStorm, RubyMine
/// - VS Code 系: VS Code, Cursor, Qoder IDE, Qoder CN IDE, Trae CN
/// - 终端: Warp, iTerm
/// - 其他: OpenCode, Qoder, Qoder Work, Qoder CN, Qoder CN Work, WorkBuddy, Kimi
///
/// 无真实图标的 IDE（如 Claude Code）使用带品牌色的文字徽章作为回退。
enum IDEIconProvider {
    /// 徽章统一尺寸（四类卡片共用）。
    ///
    /// 图标资源的「内容包围盒」差异很大：JetBrains 全家桶的 PNG 是满画布
    /// （100%），而 Cursor / WorkBuddy / Qoder 这类圆角方片自带约 10% 透明留白
    /// （≈0.80）。同样塞进 24pt 框，前者视觉上要大约 25%——这就是卡片之间
    /// 「图标大小不一」的根因。加载时统一切到不透明包围盒（见 `trimmed`），
    /// 再配合这一个尺寸常量，四个卡片的图标才会真正等大。
    static let badgeSize: CGFloat = 30

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
        // VS Code 及衍生
        "visual studio code": "vscode",
        "vscode": "vscode",
        "code": "vscode",
        // Cursor
        "cursor": "cursor",
        // OpenCode
        "opencode": "opencode",
        // Qoder 系列（英文）
        "qoder ide": "qoder-ide",
        "qoder work": "qoder-work",
        "qoder": "qoder",
        // Qoder 系列（中文）
        "qoder cn ide": "qoder-cn-ide",
        "qoder cn work": "qoder-cn-work",
        "qoder cn": "qoder-cn",
        "通义灵码": "qoder-cn",
        // Trae（字节跳动 VS Code 系 fork）
        "trae cn": "trae-cn",
        "trae": "trae-cn",
        // 终端
        "warp": "warp",
        "iterm": "iterm",
        // 其他应用
        "workbuddy": "workbuddy",
        "kimi": "kimi",
        "moonshot": "kimi",
    ]

    /// Bundle ID → 图标文件名直接映射。
    ///
    /// 当宿主应用名存在歧义（如 Qoder IDE 的 CFBundleName 也是 "Qoder"，
    /// 与 Qoder 聊天应用同名）时，用 bundle ID 做精确匹配，避免回退到错误的图标。
    private static let bundleIconMapping: [String: String] = [
        "com.qoder.ide": "qoder-ide",
        "com.aliyun.lingma.ide": "qoder-cn-ide",
        "com.qoder.app": "qoder",
        "com.microsoft.VSCode": "vscode",
        "com.visualstudio.code": "vscode",
        "com.cursor": "cursor",
        "com.todesktop.230313mzl4w4u92": "cursor",
        "ai.opencode.desktop": "opencode",
        "com.jetbrains.intellij": "intellij-idea",
        "com.jetbrains.pycharm": "pycharm",
        "com.jetbrains.webstorm": "webstorm",
        "com.jetbrains.goland": "goland",
        "com.jetbrains.rider": "rider",
        "com.jetbrains.CLion": "clion",
        "com.jetbrains.PhpStorm": "phpstorm",
        "com.jetbrains.rubymine": "rubymine",
        "com.byte-dance.trae": "trae-cn",
        "com.bytedance.trae": "trae-cn",
        "cn.trae.app": "trae-cn",
        "com.trae.app": "trae-cn",
        "com.tencent.workbuddy.mac": "workbuddy",
        "ai.workbuddy": "workbuddy",
        "ai.moonshot.kimi": "kimi",
        "com.moonshot.kimichat": "kimi",
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
        // Trae - 蓝色（字节跳动）
        "trae": (0.25, 0.48, 0.95),
        "trae cn": (0.25, 0.48, 0.95),
        // Kimi / Moonshot - 深蓝紫色
        "kimi": (0.35, 0.30, 0.75),
        "moonshot": (0.35, 0.30, 0.75),
        // WorkBuddy - 暖橙色
        "workbuddy": (0.85, 0.55, 0.20),
        // 终端/CLI - 灰色
        "terminal": (0.4, 0.4, 0.45),
        "iterm": (0.4, 0.4, 0.45),
        "warp": (0.4, 0.4, 0.45),
        "ghostty": (0.4, 0.4, 0.45),
        "kitty": (0.4, 0.4, 0.45),
        "alacritty": (0.4, 0.4, 0.45),
        "wezterm": (0.4, 0.4, 0.45),
    ]

    /// 按 key 长度降序排列的映射条目，确保更精确的匹配优先
    /// （例如 "qoder cn ide" 优先于 "qoder cn" 优先于 "qoder"）
    private static let sortedMappings: [(key: String, value: String)] = {
        iconMapping.sorted { $0.key.count > $1.key.count }
    }()

    /// 检查是否有对应 IDE 名称的真实图标
    static func hasIcon(for hostName: String?, bundleID: String? = nil) -> Bool {
        // 优先用 bundle ID 精确匹配
        if let bundle = bundleID, !bundle.isEmpty, bundleIconMapping[bundle] != nil {
            return true
        }
        guard let name = hostName?.lowercased() else { return false }
        for (key, _) in sortedMappings {
            if name.contains(key) { return true }
        }
        return false
    }

    /// 获取 IDE 图标（如果有真实图标），否则返回 nil
    ///
    /// 优先用 bundle ID 精确匹配（解决同名歧义，如 Qoder IDE vs Qoder 聊天应用），
    /// 回退到名称模糊匹配。
    static func icon(for hostName: String?, bundleID: String? = nil) -> Image? {
        // 优先用 bundle ID 精确匹配
        if let bundle = bundleID, !bundle.isEmpty,
           let iconName = bundleIconMapping[bundle],
           let image = loadImage(named: iconName) {
            return image
        }
        // 回退到名称模糊匹配
        guard let name = hostName?.lowercased() else { return nil }
        for (key, iconName) in sortedMappings {
            if name.contains(key) {
                if let image = loadImage(named: iconName) {
                    return image
                }
            }
        }
        return nil
    }

    /// 按 key 长度降序排列的品牌色条目
    private static let sortedBrandColors: [(key: String, value: (r: Double, g: Double, b: Double))] = {
        brandColors.sorted { $0.key.count > $1.key.count }
    }()

    /// 获取 IDE 的品牌色
    static func brandColor(for hostName: String?) -> Color {
        guard let name = hostName?.lowercased() else {
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
        
        for (key, color) in sortedBrandColors {
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
    ///   - bundleID: 宿主应用 Bundle ID（用于消歧，如区分 Qoder IDE 与 Qoder 聊天应用）
    ///   - fallbackText: 文字徽章内容（首字母）
    ///   - tint: 默认背景色（当无法匹配品牌色时使用）
    ///   - size: 徽章尺寸
    @ViewBuilder
    static func badgeView(hostName: String?, bundleID: String? = nil, fallbackText: String, tint: Color, size: CGFloat = badgeSize) -> some View {
        let radius = size * 0.22
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if let icon = icon(for: hostName, bundleID: bundleID) {
            // 真实图标：加载时已裁到内容包围盒，.fit 后各图标视觉等大。
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(shape)
                // 极淡的内描边：深色图标（Cursor 方块平均亮度 0.23）压在深色
                // 面板（0.28）上时边缘会糊掉，只剩内部图形可见，看起来「更小」。
                // 有了这圈 0.5pt 的亮边，方块边界才重新对齐到 30pt 框。
                .overlay(shape.strokeBorder(rimColor, lineWidth: rimWidth))
        } else {
            // 带品牌色的文字徽章
            let bgColor = hasBrandColor(for: hostName) ? brandColor(for: hostName) : tint
            // 确保文字不为空
            let displayText = fallbackText.isEmpty ? "?" : fallbackText
            Text(displayText)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(bgColor.opacity(0.9), in: shape)
                .overlay(shape.strokeBorder(rimColor, lineWidth: rimWidth))
        }
    }

    /// 图标外圈的亮边：把深色图标的方块边界从深色面板里「勾」出来。
    ///
    /// 强度是按「压过面板底色」定的：历史面板底色亮度约 0.28，Cursor 的近黑
    /// 方块只有 0.07，白 28% 的描边叠上去约 0.33，刚好比面板亮一档，方形轮廓
    /// 才立得住。再淡（16%）就只有图标内部变亮、整体仍暗于面板，等于没描。
    /// 统一处理，不用为每个图标维护「光学补偿系数」。
    static let rimColor = Color.white.opacity(0.28)
    static let rimWidth: CGFloat = 0.6

    /// 检查是否有对应的品牌色
    private static func hasBrandColor(for hostName: String?) -> Bool {
        guard let name = hostName?.lowercased() else { return false }
        for (key, _) in sortedBrandColors {
            if name.contains(key) { return true }
        }
        return false
    }

    /// 从 Resources 目录加载图片
    ///
    /// 搜索结果统一做两步处理后再缓存：
    /// 1. 裁到不透明内容的包围盒（`trimmed`），消除各图标自带留白的差异；
    /// 2. 转成 SwiftUI `Image` 缓存，避免每次重绘都重新读盘 + 重采样。
    ///
    /// 搜索顺序：
    /// 1. Bundle.main.resourceURL 下的资源包（适用于 .app 打包和 SwiftPM 构建）
    /// 2. Bundle.module（SwiftPM 自动生成的资源包引用）
    /// 3. Bundle.main.resourcePath 直接搜索（兜底）
    private static func loadImage(named: String) -> Image? {
        cacheLock.lock()
        let cached = iconCache[named]
        cacheLock.unlock()
        if let cached { return cached }

        guard let raw = rawImage(named: named) else { return nil }
        let image = Image(nsImage: trimmed(raw))

        cacheLock.lock()
        iconCache[named] = image
        cacheLock.unlock()
        return image
    }

    /// 已处理图标的缓存。SwiftUI body 在主线程求值，锁只是防御性写法。
    private static let cacheLock = NSLock()
    private static var iconCache: [String: Image] = [:]

    private static func rawImage(named: String) -> NSImage? {
        #if canImport(AppKit)
        let bundleName = "BetterFocusIDE_BetterFocusIDE.bundle"
        var searchPaths: [URL] = []
        
        // SwiftPM build / .app 打包后的路径
        if let path = Bundle.main.resourceURL?.appendingPathComponent(bundleName) {
            searchPaths.append(path)
        }
        searchPaths.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(bundleName))
        // Bundle.module（SwiftPM 资源包）
        searchPaths.append(Bundle.module.bundleURL)
        
        for basePath in searchPaths {
            let iconPath = basePath.appendingPathComponent("IDE-Icons").appendingPathComponent(named).appendingPathExtension("png")
            if FileManager.default.fileExists(atPath: iconPath.path),
               let nsImage = NSImage(contentsOf: iconPath) {
                return nsImage
            }
        }
        
        // 兜底：直接在资源路径中搜索
        if let resourcePath = Bundle.main.resourcePath {
            let directPath = (resourcePath as NSString).appendingPathComponent("IDE-Icons/\(named).png")
            if FileManager.default.fileExists(atPath: directPath),
               let nsImage = NSImage(contentsOfFile: directPath) {
                return nsImage
            }
        }
        #endif
        return nil
    }

    /// 把图标裁到不透明内容的外接矩形。
    ///
    /// 图标源的留白差异实测：JetBrains 系满画布（1.00），Cursor 0.803、
    /// WorkBuddy 0.801、Qoder 0.773、iTerm/Warp 0.82。不裁的话同一尺寸框里
    /// 视觉大小相差 25%。包围盒先在 64×64 缩略图上粗测（代价可忽略），
    /// 再映射回原图裁切，避免逐像素扫描 1024×1024。
    static func trimmed(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return image }
        let probe = 64
        var pixels = [UInt8](repeating: 0, count: probe * probe * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress,
                                      width: probe, height: probe,
                                      bitsPerComponent: 8, bytesPerRow: probe * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: probe, height: probe))
            return true
        }
        guard drawn else { return image }

        var minX = probe, minY = probe, maxX = -1, maxY = -1
        for y in 0..<probe {
            for x in 0..<probe {
                // 阈值 24/255：滤掉抗锯齿边缘的半透明像素，只认真正的内容。
                if pixels[(y * probe + x) * 4 + 3] > 24 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0, maxY >= 0 else { return image }
        // 满画布直接原样返回，省一次重采样。
        if minX == 0, minY == 0, maxX == probe - 1, maxY == probe - 1 { return image }

        let sx = CGFloat(cg.width) / CGFloat(probe)
        let sy = CGFloat(cg.height) / CGFloat(probe)
        // CGContext 原点在左下角，换算回自上而下的图像坐标。
        let rect = CGRect(x: CGFloat(minX) * sx,
                          y: CGFloat(cg.height) - CGFloat(maxY + 1) * sy,
                          width: CGFloat(maxX - minX + 1) * sx,
                          height: CGFloat(maxY - minY + 1) * sy).integral
        guard let cropped = cg.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    /// 获取文字徽章（首字母大写）
    static func textBadge(for hostName: String?, fallback: String) -> String {
        let name = hostName ?? fallback
        return String(name.prefix(1)).uppercased()
    }
}
