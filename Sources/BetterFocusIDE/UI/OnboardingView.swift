// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit
import SwiftUI

/// 首次启动引导。左右滑动或点箭头翻页，停留数秒后自动前进，最后一页安装 hook。
struct OnboardingView: View {
    @ObservedObject var hooks: HookInstallPickerModel
    var onInstall: () -> Void
    var onSkip: () -> Void

    @StateObject private var clock = Clock()
    @State private var page: Int? = 0
    @State private var nextAdvance = Date().addingTimeInterval(Self.interval)
    @State private var keyMonitor: Any?

    private static let interval: TimeInterval = 6
    private var pages: [OnboardingGate.Page] { OnboardingGate.Page.allCases }
    private var index: Int { page ?? 0 }
    private var onLastPage: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 760, height: 640)
        .onAppear(perform: armAutoAdvance)
        .onChange(of: page) { _, _ in armAutoAdvance() }
        .onReceive(clock.ticker) { now in
            guard !onLastPage, now >= nextAdvance else { return }
            nextAdvance = .distantFuture
            withAnimation(.easeInOut(duration: 0.35)) {
                page = min(index + 1, pages.count - 1)
            }
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(pages, id: \.rawValue) { item in
                    pageBody(item)
                        .containerRelativeFrame(.horizontal)
                        .id(item.rawValue)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                arrowButton(systemName: "chevron.left", enabled: index > 0) { step(-1) }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(pages, id: \.rawValue) { item in
                        Circle()
                            .fill(item.rawValue == index ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                            .onTapGesture { jump(to: item.rawValue) }
                    }
                }
                Spacer()
                arrowButton(systemName: "chevron.right", enabled: !onLastPage) { step(1) }
            }

            if onLastPage {
                HStack {
                    Button(hooks.items.isEmpty ? "开始使用" : "以后再说", action: onSkip)
                    Spacer()
                    if !hooks.items.isEmpty {
                        Button("安装并开始", action: onInstall)
                            .keyboardShortcut(.defaultAction)
                            .disabled(hooks.selectedIDs.isEmpty)
                    }
                }
            } else {
                HStack {
                    Text("左右滑动翻页，停留数秒后自动继续")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("跳过", action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func pageBody(_ item: OnboardingGate.Page) -> some View {
        switch item {
        case .welcome:
            welcomePage
        case .features:
            featuresPage
        case .notes:
            pointsPage(
                title: "用之前先知道",
                points: [
                    ("hand.raised", "自动化权限", "跳回 IDE 或浏览器需要系统的「自动化」权限。设置里的「权限」页能查看状态，并前往系统设置授权。"),
                    ("cursorarrow.click", "同一份菜单", "右键菜单栏图标和刘海气泡，打开的是同一份菜单：安装 hook、设置、自检都在里面。"),
                    ("display", "刘海屏", "岛锚定在有刘海的内置屏幕上。外接显示器没有刘海时，会改用备用尺寸。"),
                    ("arrow.clockwise", "有的宿主要重开", "WorkBuddy 改完 hook 不会马上生效，需要重开当前会话。"),
                ])
        case .install:
            installPage
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("刘海里的编码助手")
                .font(.system(size: 22, weight: .semibold))
            Text("提问、权限和每轮任务结束时，卡片在刘海下展开。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                OnboardingShot(name: "idle", height: 88)
                Text("通知自己收起、你还没看过时，胶囊外圈会亮起呼吸灯。这是未读提示，点一下就能把那条展开。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingShot(name: "question", height: 248)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("它会做这些事")
                .font(.system(size: 22, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                featureShot("提问", "在岛上选完，答案写回智能体", "question")
                featureShot("权限提醒", "亮起提醒，批准仍在 IDE 里", "permission")
                featureShot("回合完成", "点一下跳回对应的项目窗口", "notice")
                featureShot("最近通知", "点空闲的胶囊，回看刚出现的几条", "history")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func featureShot(_ title: String, _ caption: String, _ image: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OnboardingShot(name: image, height: 148)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接上你的 IDE")
                .font(.system(size: 22, weight: .semibold))
            Text("下面是受支持的 IDE。本机已经安装的默认勾选，没安装的只展示、不勾选。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !hooks.items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($hooks.items) { $item in
                            HookInstallRow(item: $item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pointsPage(title: String, points: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.0)
                        .font(.system(size: 15))
                        .frame(width: 22)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.1)
                            .font(.system(size: 14, weight: .semibold))
                        Text(point.2)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func arrowButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }

    private func step(_ delta: Int) {
        jump(to: min(max(index + delta, 0), pages.count - 1))
    }

    private func jump(to next: Int) {
        withAnimation(.easeInOut(duration: 0.35)) { page = next }
    }

    /// 用户手动翻页后重新计时，避免刚滑过去就被自动翻走。最后一页停住。
    private func armAutoAdvance() {
        nextAdvance = onLastPage ? .distantFuture : Date().addingTimeInterval(Self.interval)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == OnboardingGate.windowTitle else { return event }
            switch event.keyCode {
            case 123:
                step(-1)
                return nil
            case 124:
                step(1)
                return nil
            case 53:
                onSkip()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

/// 引导窗口活着的时候只保留一个翻页计时器。
private final class Clock: ObservableObject {
    let ticker = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
}
