// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        // The black island surface and its morphing silhouette are drawn by the
        // AppKit canvas (a masked layer); the SwiftUI layer only carries the
        // content, so it stays transparent and never fights the shape morph.
        ZStack(alignment: .top) {
            if service.expanded || service.closingCard != nil {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture {
            // Anti-mistouch: ignore clicks within the guard window after a card appears.
            // Only applies to interactive cards (question/permission).
            if service.activeCard == .question || service.activeCard == .permission {
                guard !service.isClickGuarded else { return }
            }
            service.handleSurfaceTap()
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }
    
    private var collapsedContent: some View {
        // Pure black capsule with a centered dot (aligned with Python idle state).
        // When pending items exist, the dot uses the provider tint and shows count.
        HStack(spacing: 4) {
            if service.pendingTotal > 0 {
                Circle()
                    .fill(Color(red: service.pendingTint.r,
                                green: service.pendingTint.g,
                                blue: service.pendingTint.b))
                    .frame(width: NotchLayout.idleDotRadius * 2,
                           height: NotchLayout.idleDotRadius * 2)
                if service.pendingTotal > 1 {
                    Text("\(service.pendingTotal)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: service.pendingTint.r,
                                               green: service.pendingTint.g,
                                               blue: service.pendingTint.b))
                }
            } else {
                // Idle accent dot with breathing pulse (Python IDLE_PULSE_PERIOD=2.4s).
                Circle()
                    .fill(Color(red: NotchLayout.accentColor.r,
                                green: NotchLayout.accentColor.g,
                                blue: NotchLayout.accentColor.b))
                    .frame(width: NotchLayout.idleDotRadius * 2,
                           height: NotchLayout.idleDotRadius * 2)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: NotchLayout.idlePulsePeriod / 2)
                            .repeatForever(autoreverses: true)) {
                            pulseScale = 1.0 + NotchLayout.idleDotPulse / NotchLayout.idleDotRadius
                        }
                    }
                    .onDisappear { pulseScale = 1.0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Show closingCard content during withdrawal animation.
            let card = service.activeCard != .none ? service.activeCard : (service.closingCard ?? .none)
            switch card {
            case .question:
                NotchAgentQuestionView(controller: service.questionController,
                                       pinned: service.pinned,
                                       onTogglePin: { service.togglePin() })
            case .permission:
                NotchPermissionView(controller: service.permissionController,
                                    pinned: service.pinned,
                                    onTogglePin: { service.togglePin() })
            case .notice:
                if let notice = service.noticeController.notice {
                    NotchNoticeView(notice: notice,
                                    pinned: service.pinned,
                                    onTogglePin: { service.togglePin() },
                                    onTap: { service.noticeController.tapped() },
                                    bellSwingStart: service.bellSwingStart)
                }
            case .history:
                NotchHistoryView(controller: service.historyController) { entry in
                    service.historyController.tapped(entry)
                    service.collapse()
                }
            case .none:
                // No card active — show nothing (toggle will not expand to .none).
                EmptyView()
            }
        }
        .padding(.top, service.geometry.safeContentTop)
    }
}

// MARK: - NotchShape

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    var floatingGap: CGFloat? = nil
    
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    
    static func island(height: CGFloat, geometry: NotchGeometry) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height), floatingGap: geometry.floatingGap)
    }
    
    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        if let floatingGap {
            return Path(NotchLayout.capsulePath(in: rect, gap: floatingGap))
        }
        let shoulder = NotchLayout.shoulder(height: rect.height)
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        // The silhouette is traced in local coordinates; translate it to the
        // island rect's origin so the mask lines up with the centered host.
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
