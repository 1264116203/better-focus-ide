// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

#if DEBUG
import SwiftUI
import AppKit

// MARK: - NotchCanvas 预览包装器

/// 将 AppKit 的 NotchCanvas 包装为 SwiftUI 视图，用于 Xcode Canvas 预览。
/// 这样可以直观看到遮罩路径、内容布局、磨砂玻璃等 AppKit 层的实际效果。
struct NotchCanvasPreview: NSViewRepresentable {
    let content: AnyView
    let size: CGSize
    
    func makeNSView(context: Context) -> NotchCanvas {
        return NotchCanvas(content: content, size: size)
    }
    
    func updateNSView(_ nsView: NotchCanvas, context: Context) {
        nsView.setContentSize(size)
    }
}

// MARK: - 预览

struct NotchCanvas_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // 收起态（空闲胶囊）
            VStack(spacing: 8) {
                Text("收起态 (180×29)").font(.caption).foregroundStyle(.secondary)
                NotchCanvasPreview(
                    content: AnyView(
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ),
                    size: CGSize(width: 180, height: 29)
                )
                .frame(width: 232, height: 55)  // 包络尺寸（含阴影留白）
                .background(Color.black.opacity(0.3))
            }
            
            // 通知横幅
            VStack(spacing: 8) {
                Text("通知横幅 (390×56)").font(.caption).foregroundStyle(.secondary)
                NotchCanvasPreview(
                    content: AnyView(
                        HStack {
                            Image(systemName: "bell.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("代码重构已完成").font(.headline).foregroundStyle(.white)
                                Text("已将所有注释翻译为中文").font(.caption).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ),
                    size: CGSize(width: 390, height: 56)
                )
                .frame(width: 442, height: 82)  // 包络尺寸
                .background(Color.black.opacity(0.3))
            }
            
            // 提问卡片
            VStack(spacing: 8) {
                Text("提问卡片 (420×200)").font(.caption).foregroundStyle(.secondary)
                NotchCanvasPreview(
                    content: AnyView(
                        VStack(alignment: .leading, spacing: 12) {
                            Text("重构方案选择").font(.headline).foregroundStyle(.white)
                            Text("是否将当前工程拆分为 library + executable 双目标？")
                                .font(.body).foregroundStyle(.white.opacity(0.9))
                            Spacer()
                        }
                        .padding(18)
                        .frame(width: 420, height: 200, alignment: .topLeading)
                    ),
                    size: CGSize(width: 420, height: 200)
                )
                .frame(width: 472, height: 226)  // 包络尺寸
                .background(Color.black.opacity(0.3))
            }
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
#endif
