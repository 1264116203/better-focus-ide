// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI

/// 引导页实拍。放在资源包的 `Onboarding` 目录里。
///
/// 不走 `Bundle.module`：包还没拷进 `.app` 时那个访问器会直接崩溃。
enum OnboardingArt {
    static func image(named: String) -> Image? {
        guard let nsImage = nsImage(named: named) else { return nil }
        return Image(nsImage: nsImage)
    }

    static func nsImage(named: String) -> NSImage? {
        let bundleName = "BetterFocusIDE_BetterFocusIDE.bundle"
        var roots: [URL] = []
        if let path = Bundle.main.resourceURL?.appendingPathComponent(bundleName) {
            roots.append(path)
        }
        roots.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(bundleName))
        if let exec = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(bundleName) {
            roots.append(exec)
        }
        for root in roots {
            let file = root
                .appendingPathComponent("Onboarding")
                .appendingPathComponent(named)
                .appendingPathExtension("png")
            if let image = NSImage(contentsOf: file) { return image }
            if let bundle = Bundle(url: root),
               let url = bundle.url(forResource: named, withExtension: "png", subdirectory: "Onboarding"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

/// 引导页里的一张实拍。圆角裁在图片自己的边上：外框比图片大时，裁外框看不出圆角。
struct OnboardingShot: View {
    let name: String
    var height: CGFloat = 160
    private let radius: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            if let nsImage = OnboardingArt.nsImage(named: name), width > 1 {
                let fitted = Self.fittedSize(nsImage.size, maxWidth: width, maxHeight: height)
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
                    .frame(width: width, height: height)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: width, height: height)
            }
        }
        .frame(height: height)
    }

    /// 在给定格子里按比例放下整张图，返回图片实际占用的尺寸。
    private static func fittedSize(_ image: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }
        let scale = min(maxWidth / image.width, maxHeight / image.height)
        return CGSize(width: (image.width * scale).rounded(.down),
                      height: (image.height * scale).rounded(.down))
    }
}
