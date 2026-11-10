// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI
import AppKit

/// 灵动岛设置面板 —— 对 Python 参考实现 `settings_window.py` 的 SwiftUI 重建：
/// 顶部搜索栏、七大分类侧边栏、分组详情页（头部 + 恢复默认按钮 + 提示 + 小节 + 行）、
/// 每行等宽字体读数、声音 / 震动的试听按钮、`enabled_when` 未满足时置灰，
/// 以及底部「恢复默认」按钮与实时状态行。
/// 分组页头部的「恢复默认设置」只恢复当前分组；底部「恢复默认」仍恢复全部。
/// 两处都会弹出确认对话框。
///
/// `Settings` 是唯一的实时配置源，因此每次编辑都即时生效（灵动岛在调用时读取）；
/// 落盘写入做了 0.5 秒防抖，标注 `needs=reinstall` 的项会在 0.8 秒后重新安装
/// Hook / Plugin。
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    @State private var selectedGroup: String = SettingCatalog.groups[0]
    @State private var query = ""
    @State private var status = "所有改动即时生效"
    @State private var writebackWork: DispatchWorkItem?
    @State private var showResetConfirmation = false
    /// 确认框对应的范围。分组按钮为 false，底部「恢复全部」为 true。
    /// 不放进 alert 的 isPresented 绑定里清掉，避免按钮动作读到已被关掉的状态。
    @State private var resetEverything = false

    /// 允许从指定分类开始展示（预览与调试页截图用；默认仍是第一个分类）。
    init(initialGroup: String = SettingCatalog.groups[0]) {
        _selectedGroup = State(initialValue: initialGroup)
    }

    // MARK: - 布局常量（对齐 Python settings_window.py）

    private enum Metric {
        static let topBarHeight: CGFloat = 44
        static let sidebarWidth: CGFloat = 132
        static let sidebarRowHeight: CGFloat = 30
        static let margin: CGFloat = 16
        static let rowHeight: CGFloat = 28
        static let rowGap: CGFloat = 6
        static let readoutWidth: CGFloat = 74
        static let auditionWidth: CGFloat = 56
        static let barHeight: CGFloat = 52
        static let choiceMin: CGFloat = 120
        static let choiceMax: CGFloat = 190
        static let writebackDelay: TimeInterval = 0.8
    }

    /// 标签列宽 = 最宽标签实测宽度 + 14，并钳制在 84…180 之间。
    private static let labelWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 11.5)
        var widest: CGFloat = 0
        for def in SettingCatalog.all {
            let w = (def.label as NSString).size(withAttributes: [.font: font]).width
            widest = max(widest, w)
        }
        return min(180, max(84, (widest + 14).rounded()))
    }()

    /// 时间格式化器，用于状态行末尾的 HH:mm:ss 时间戳。
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 侧边栏末尾的「权限」「调试」页：不是持久化配置，
    /// 因此不进 `SettingCatalog.groups`（那个数组是纯设置分组）。
    private static let permissionPage = "权限"
    private static let debugPage = "调试"
    private static let permissionKeywords = ["权限", "自动化", "授权", "automation", "privacy"]

    /// 去除首尾空白后的搜索词。
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// 当前是否停在调试页。
    private var showingDebugPage: Bool { selectedGroup == Self.debugPage }
    /// 当前是否停在权限页。
    private var showingPermissionPage: Bool { selectedGroup == Self.permissionPage }

    var body: some View {
        VStack(spacing: 0) {
            searchBar.frame(height: Metric.topBarHeight)
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: Metric.sidebarWidth)
                Divider()
                content
            }
            // 权限页和调试页没有设置项，底部的恢复默认与写回状态整栏隐藏。
            if !showingDebugPage && !showingPermissionPage {
                Divider()
                bottomBar.frame(height: Metric.barHeight)
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 420, idealHeight: 620)
        .onDisappear { flushOnClose() }
        .alert(resetEverything ? "恢复全部默认设置" : "恢复当前分组",
               isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .destructive) {
                if resetEverything { resetAllDefaults() }
                else { resetGroupDefaults() }
            }
        } message: {
            Text(resetEverything
                 ? "这将把所有设置恢复为默认值。此操作不可撤销。"
                 : "只恢复「\(selectedGroup)」里的设置，其它分组保持不变。此操作不可撤销。")
        }
    }

    // MARK: - 搜索栏

    /// 顶部搜索框：放大镜图标 + 输入框 + 有内容时的清除按钮。
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("搜索设置…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onChange(of: query) { jumpToFirstHit() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, Metric.margin)
    }

    /// 搜索词非空时，自动跳到第一个命中的分类。
    private func jumpToFirstHit() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        if Self.permissionKeywords.contains(where: { q.localizedCaseInsensitiveContains($0) }) {
            selectedGroup = Self.permissionPage
            return
        }
        if let hit = SettingCatalog.groups.first(where: { group in
            SettingCatalog.settings(in: group).contains { $0.matches(q) }
        }) {
            selectedGroup = hit
        }
    }

    // MARK: - 侧边栏

    /// 左侧分类导航栏：侧边材质背板 + 各分类行 + 末尾的调试入口。
    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            SidebarMaterial()
            VStack(spacing: 2) {
                ForEach(SettingCatalog.groups, id: \.self) { group in
                    sidebarRow(group)
                }
                Divider()
                    .padding(.vertical, 4)
                sidebarRow(Self.permissionPage)
                sidebarRow(Self.debugPage)
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    /// 单条分类行：图标 + 名称，选中时用强调色高亮底。
    private func sidebarRow(_ group: String) -> some View {
        let selected = group == selectedGroup
        return Button {
            selectedGroup = group
        } label: {
            HStack(spacing: 8) {
                Image(systemName: SettingCatalog.groupSymbols[group] ?? "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(group)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Metric.sidebarRowHeight, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容页

    /// 详情页的渲染单元：小节标题或一条设置行（二者共用同一 ForEach 序列）。
    private enum PageItem: Identifiable {
        case section(String)
        case row(SettingDefinition)
        var id: String {
            switch self {
            case .section(let t): return "s|" + t
            case .row(let d): return "r|" + d.key
            }
        }
    }

    /// 搜索状态下全库无任何命中时为 true，用于展示空态文案。
    private var showEmpty: Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return false }
        return !SettingCatalog.all.contains { $0.matches(q) }
    }

    /// 右侧详情区：空态文案，或当前分类的分组页面（头部 + 提示 + 行序列）。
    private var content: some View {
        Group {
            if showingPermissionPage {
                PermissionStatusView()
            } else if showingDebugPage {
                // 调试页自成一个视图：它不是"若干设置行"，而是可点的触发按钮。
                // 标题与提示另给一层水平内边距，与下方调试面板的内边距对齐。
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Metric.rowGap) {
                        HStack {
                            Text(Self.debugPage)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        Text("手动触发各家 IDE 的提问、权限与完成通知，不必回 IDE 里跑一轮。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Metric.margin)
                    .padding(.top, Metric.margin)
                    DebugPanelView()
                }
            } else if showEmpty {
                Text("没有匹配的设置，换个词试试")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.rowGap) {
                        HStack {
                            Text(selectedGroup)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            // 只恢复当前分组，不走 resetAll()。
                            Button("恢复默认设置") {
                                resetEverything = false
                                showResetConfirmation = true
                            }
                            .controlSize(.small)
                            .foregroundStyle(.red)
                            .help("只恢复「\(selectedGroup)」这一组")
                        }
                        if let hint = SettingCatalog.groupHints[selectedGroup], !hint.isEmpty {
                            Text(hint)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 4)
                        }
                        ForEach(pageItems(selectedGroup)) { item in
                            switch item {
                            case .section(let title):
                                Text(title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                            case .row(let def):
                                row(def)
                            }
                        }
                    }
                    .padding(Metric.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 经搜索过滤后的分类行序列，并为每段连续的小节各 emit 一个标题
    /// （对应 Python `_apply_filter` + 小节去重）。
    private func pageItems(_ group: String) -> [PageItem] {
        let q = trimmedQuery
        let defs = SettingCatalog.settings(in: group).filter { $0.matches(q) }
        var items: [PageItem] = []
        var lastSection: String?
        for def in defs {
            if !def.section.isEmpty, def.section != lastSection {
                items.append(.section(def.section))
                lastSection = def.section
            }
            items.append(.row(def))
        }
        return items
    }

    // MARK: - 设置行

    /// 单条设置行：标签 + 控件 + 可选试听按钮 + 等宽读数，未启用时整体置灰。
    private func row(_ def: SettingDefinition) -> some View {
        let enabled = def.isEnabled()
        return HStack(spacing: 8) {
            Text(def.label)
                .font(.system(size: 11.5))
                .foregroundStyle(labelColor(def, enabled: enabled))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.labelWidth, alignment: .leading)
            control(def, enabled: enabled)
            auditionButton(def, enabled: enabled)
            if def.kind != .slider { Spacer(minLength: 0) }
            Text(readoutText(def))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(enabled ? Color.secondary
                                         : Color(nsColor: .disabledControlTextColor))
                .lineLimit(1)
                .frame(width: Metric.readoutWidth, alignment: .trailing)
        }
        .frame(height: Metric.rowHeight)
        .contentShape(Rectangle())
        .help(tooltip(def, enabled: enabled))
    }

    /// 按 `kind` 分发到对应控件（滑块 / 开关 / 颜色 / 下拉），未启用则禁用。
    @ViewBuilder
    private func control(_ def: SettingDefinition, enabled: Bool) -> some View {
        switch def.kind {
        case .slider:
            sliderControl(def).disabled(!enabled).frame(maxWidth: .infinity)
        case .toggle:
            toggleControl(def).disabled(!enabled)
        case .color:
            colorControl(def).disabled(!enabled)
        case .choice:
            choiceControl(def).disabled(!enabled)
        }
    }

    /// 滑块控件：把 `.double` / `.int` 取值桥接为 Double 绑定，`.int` 写入时取整；
    /// `step > 0` 时使用离散步进。
    private func sliderControl(_ def: SettingDefinition) -> some View {
        let binding = Binding<Double>(
            get: {
                switch def.get() {
                case .double(let v): return v
                case .int(let v): return Double(v)
                default: return def.min
                }
            },
            set: { newValue in
                if case .int = def.get() { def.set(.int(Int(newValue.rounded()))) }
                else { def.set(.double(newValue)) }
                afterChange(def)
            }
        )
        return Group {
            if def.step > 0 {
                Slider(value: binding, in: def.min...def.max, step: def.step)
            } else {
                Slider(value: binding, in: def.min...def.max)
            }
        }
        .controlSize(.small)
    }

    /// 开关控件：桥接 `.bool` 取值到一个隐藏标签的 Toggle。
    private func toggleControl(_ def: SettingDefinition) -> some View {
        let binding = Binding<Bool>(
            get: { if case .bool(let v) = def.get() { return v }; return false },
            set: { def.set(.bool($0)); afterChange(def) }
        )
        return Toggle("", isOn: binding)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }

    /// 颜色控件：把 `.rgb` 三元组与 SwiftUI Color 双向桥接，写入时统一到 deviceRGB。
    private func colorControl(_ def: SettingDefinition) -> some View {
        let binding = Binding<Color>(
            get: {
                if case .rgb(let r, let g, let b) = def.get() {
                    return Color(red: r, green: g, blue: b)
                }
                return .white
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
                def.set(.rgb(Double(ns.redComponent),
                             Double(ns.greenComponent),
                             Double(ns.blueComponent)))
                afterChange(def)
            }
        )
        return ColorPicker("", selection: binding, supportsOpacity: false)
            .labelsHidden()
    }

    /// 下拉控件：把 `.string` 取值桥接到菜单风格 Picker，选项来自 `def.choices`。
    private func choiceControl(_ def: SettingDefinition) -> some View {
        let binding = Binding<String>(
            get: { if case .string(let v) = def.get() { return v }; return "" },
            set: { def.set(.string($0)); afterChange(def) }
        )
        return Picker("", selection: binding) {
            ForEach(def.choices, id: \.0) { value, title in
                Text(title).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: Metric.choiceMin, maxWidth: Metric.choiceMax)
    }

    /// 试听按钮：仅提示音（试听）与震动模式（试震）两类设置附带。
    @ViewBuilder
    private func auditionButton(_ def: SettingDefinition, enabled: Bool) -> some View {
        if def.key == "notifySound" {
            Button("试听") { auditionSound(def) }
                .controlSize(.small)
                .frame(width: Metric.auditionWidth)
                .disabled(!enabled)
        } else if def.key == "hapticPattern" {
            Button("试震") { auditionHaptic() }
                .controlSize(.small)
                .frame(width: Metric.auditionWidth)
                .disabled(!enabled)
        }
    }

    // MARK: - 读数 / 颜色 / 提示气泡

    /// 行尾等宽读数文本：滑块显示数值 + 单位，开关显示开 / 关，颜色显示 #RRGGBB。
    private func readoutText(_ def: SettingDefinition) -> String {
        switch def.kind {
        case .slider:
            let v: Double
            switch def.get() {
            case .double(let d): v = d
            case .int(let i): v = Double(i)
            default: v = 0
            }
            let num = def.digits <= 0
                ? String(Int(v.rounded()))
                : String(format: "%.\(def.digits)f", v)
            return num + def.unit
        case .toggle:
            if case .bool(let b) = def.get() { return b ? "开" : "关" }
            return "关"
        case .color:
            if case .rgb(let r, let g, let b) = def.get() {
                let clamp = { (x: Double) in Int((max(0, min(1, x)) * 255).rounded()) }
                return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
            }
            return ""
        case .choice:
            return ""
        }
    }

    /// 标签颜色：禁用置灰；搜索命中时高亮为强调色；否则正常前景色。
    private func labelColor(_ def: SettingDefinition, enabled: Bool) -> Color {
        if !enabled { return Color(nsColor: .disabledControlTextColor) }
        let q = trimmedQuery
        if !q.isEmpty, def.matches(q) { return Color.accentColor }
        return Color.primary
    }

    /// 行提示气泡：拼接备注、需写回说明、以及未启用时的前置开关提示。
    private func tooltip(_ def: SettingDefinition, enabled: Bool) -> String {
        var parts: [String] = []
        if !def.note.isEmpty { parts.append(def.note) }
        if def.needsReinstall { parts.append("改完会自动写回 Hook / Plugin") }
        if !enabled {
            let names = def.enabledBy.compactMap { SettingCatalog.byKey($0)?.label }
            let who = names.isEmpty ? "相关开关" : names.joined(separator: " / ")
            parts.append("需先开启「\(who)」才会生效")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - 底部栏

    /// 底部操作栏：「恢复默认」按钮（全部设置）+ 实时状态行。
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("恢复默认") {
                resetEverything = true
                showResetConfirmation = true
            }
            .controlSize(.small)
            .help("恢复全部设置")
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - 动作

    /// 即时编辑：防抖落盘；影响 Hook 的项安排一次写回，否则仅确认已生效。
    private func afterChange(_ def: SettingDefinition) {
        settings.scheduleSave()
        if def.needsReinstall { scheduleWriteback() }
        else { status = "已生效" }
    }

    /// 安排一次延迟写回（取消已有的排队任务），用于导入 Hook 后重安装。
    private func scheduleWriteback() {
        writebackWork?.cancel()
        status = "正在写回 Hook / Plugin…"
        let work = DispatchWorkItem { writeBack() }
        writebackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Metric.writebackDelay, execute: work)
    }

    /// 实际执行写回：先落盘，再刷新**已经安装过**的集成，让新的超时值进入
    /// hook / 插件生成物。未安装的宿主不会被顺手写入配置（WorkBuddy 的
    /// settings.json 还存着账号与插件配置，不能无故改动）。
    private func writeBack() {
        writebackWork = nil
        settings.flushSave()

        var refreshed: [String] = []
        func refresh(_ label: String, installed: Bool, _ work: () throws -> Void) -> Bool {
            guard installed else { return true }
            do {
                try work()
                refreshed.append(label)
                return true
            } catch {
                status = "\(label) 写入失败：\(error.localizedDescription)"
                Log.error("writeBack: \(label) failed (\(error))", topic: "settings")
                return false
            }
        }

        guard refresh("Qoder Hook", installed: QoderHookInstaller.isInstalled,
                      { try QoderHookInstaller.install() }) else { return }
        guard refresh("OpenCode Plugin", installed: OpenCodePluginInstaller.isInstalled,
                      { try OpenCodePluginInstaller.install() }) else { return }
        guard refresh("Cursor Hook", installed: CursorHookInstaller.isInstalled,
                      { try CursorHookInstaller.install() }) else { return }
        guard refresh("WorkBuddy Hook", installed: WorkBuddyHookInstaller.isInstalled,
                      { try WorkBuddyHookInstaller.install() }) else { return }

        if refreshed.isEmpty {
            status = "已生效（尚未安装 Hook / Plugin）"
        } else {
            status = "已写回 \(refreshed.joined(separator: " / ")) · "
                + Self.clock.string(from: Date())
        }
    }

    /// 只恢复当前分组。默认值经各项 `set` 写回（滑块按面板单位换算）。
    /// 组内有 `needsReinstall` 的项（目前是提问等待上限）才重装 Hook。
    private func resetGroupDefaults() {
        let group = selectedGroup
        guard settings.reset(group: group) else {
            status = "当前分组没有可恢复的设置"
            return
        }
        if SettingCatalog.settings(in: group).contains(where: { $0.needsReinstall }) {
            scheduleWriteback()
        } else {
            status = "已恢复「\(group)」的默认"
        }
    }

    /// 恢复全部设置为出厂值，并触发一次写回。底部按钮专用。
    private func resetAllDefaults() {
        settings.resetAll()
        scheduleWriteback()
        status = "已恢复默认"
    }

    /// 试听当前所选提示音，把结果写进状态行。
    private func auditionSound(_ def: SettingDefinition) {
        if case .string(let name) = def.get(), !name.isEmpty,
           FeedbackService.playSound(name) {
            status = "已播放提示音"
        } else {
            status = "该音不可用或未选"
        }
    }

    /// 触发一次触控板震动反馈（本机不支持时在状态行提示）。
    private func auditionHaptic() {
        status = FeedbackService.buzz() ? "已震动" : "本机不支持触控板震动"
    }

    /// 面板关闭时兜底：立即落盘，并把排队中的写回提前执行掉。
    private func flushOnClose() {
        settings.flushSave()
        if writebackWork != nil {
            writebackWork?.cancel()
            writeBack()
        }
    }
}

/// `.sidebar` 材质背板，对应 Python 面板那种半透明的分类列表
/// （NSVisualEffectView，融合在窗口背后）。
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#if DEBUG
/// Xcode Canvas 预览：直接渲染设置面板（使用 Settings.shared 实时配置）。
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 760, height: 620)
            .preferredColorScheme(.dark)
    }
}
#endif
