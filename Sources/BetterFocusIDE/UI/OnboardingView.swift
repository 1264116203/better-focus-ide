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
        .frame(width: 680, height: 520)
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
            textPage(
                symbol: "macbook",
                title: "刘海里的编码助手",
                paragraphs: [
                    "BetterFocusIDE 挂在 MacBook 的刘海上，没有 Dock 图标。",
                    "智能体提问、请求权限、做完一轮时，卡片出现在刘海旁边。你可以就地回答，也可以点一下跳回原来的窗口。",
                ])
        case .features:
            pointsPage(
                title: "它会做这些事",
                points: [
                    ("text.bubble", "提问", "选项和补充说明写在岛上，答案回到发起请求的智能体。"),
                    ("lock.shield", "权限提醒", "IDE 要你审批时，岛上亮起提醒。批准仍在 IDE 自己的对话框里完成。"),
                    ("checkmark.circle", "回合完成", "这一轮结束后弹出横幅，点击后聚焦到对应的项目窗口。"),
                    ("clock.arrow.circlepath", "最近通知", "刚出现过的几条可以再打开看一眼。"),
                ])
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

    private var installPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接上你的 IDE")
                .font(.system(size: 22, weight: .semibold))
            Text(hooks.items.isEmpty
                 ? "这台 Mac 上还没有检测到受支持的 IDE。装好之后，可以从菜单栏图标的「安装 Hook / Plugin…」再装。"
                 : "已检测到这些受支持的 IDE，默认全部勾选。取消勾选的不会安装。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !hooks.items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($hooks.items) { $item in
                            Toggle(item.label, isOn: $item.selected)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 13))
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

    private func textPage(symbol: String, title: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 48)
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
