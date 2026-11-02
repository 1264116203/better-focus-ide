// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI
import AppKit

/// The Dynamic Island settings panel — a SwiftUI rebuild of the Python
/// reference's `settings_window.py`: a search bar on top, a seven-category
/// sidebar, a grouped detail page (header + hint + sections + rows), a
/// per-row monospaced readout, audition buttons for sound / haptics, greying
/// for rows whose `enabled_when` is unmet, and a bottom bar with 「恢复默认」
/// plus a live status line.
///
/// `Settings` is the single live config source, so every edit applies at once
/// (the island reads it at call time); writes to disk are debounced 0.5s and
/// `needs=reinstall` items re-install the Hook / Plugin after 0.8s.
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    @State private var selectedGroup: String = SettingCatalog.groups[0]
    @State private var query = ""
    @State private var status = "所有改动即时生效"
    @State private var writebackWork: DispatchWorkItem?

    // MARK: - Layout constants (Python settings_window.py)

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

    /// Label column = widest label measured + 14, clamped to 84…180.
    private static let labelWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 11.5)
        var widest: CGFloat = 0
        for def in SettingCatalog.all {
            let w = (def.label as NSString).size(withAttributes: [.font: font]).width
            widest = max(widest, w)
        }
        return min(180, max(84, (widest + 14).rounded()))
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar.frame(height: Metric.topBarHeight)
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: Metric.sidebarWidth)
                Divider()
                content
            }
            Divider()
            bottomBar.frame(height: Metric.barHeight)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 420, idealHeight: 620)
        .onDisappear { flushOnClose() }
    }

    // MARK: - Search bar

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

    /// When a query is active, open the first category that has a hit.
    private func jumpToFirstHit() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        if let hit = SettingCatalog.groups.first(where: { group in
            SettingCatalog.settings(in: group).contains { $0.matches(q) }
        }) {
            selectedGroup = hit
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            SidebarMaterial()
            VStack(spacing: 2) {
                ForEach(SettingCatalog.groups, id: \.self) { group in
                    sidebarRow(group)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

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

    // MARK: - Content page

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

    private var showEmpty: Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return false }
        return !SettingCatalog.all.contains { $0.matches(q) }
    }

    private var content: some View {
        Group {
            if showEmpty {
                Text("没有匹配的设置，换个词试试")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.rowGap) {
                        Text(selectedGroup)
                            .font(.system(size: 13, weight: .semibold))
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

    /// Rows of a group after the search filter, with a section header emitted
    /// once per contiguous run (Python `_apply_filter` + section dedupe).
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

    // MARK: - Row

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

    // MARK: - Readout / colour / tooltip

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

    private func labelColor(_ def: SettingDefinition, enabled: Bool) -> Color {
        if !enabled { return Color(nsColor: .disabledControlTextColor) }
        let q = trimmedQuery
        if !q.isEmpty, def.matches(q) { return Color.accentColor }
        return Color.primary
    }

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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("恢复默认") { resetDefaults() }
                .controlSize(.small)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - Actions

    /// Live edit: persist (debounced) and, for Hook-affecting items, schedule
    /// a write-back; otherwise just confirm it took.
    private func afterChange(_ def: SettingDefinition) {
        settings.scheduleSave()
        if def.needsReinstall { scheduleWriteback() }
        else { status = "已生效" }
    }

    private func scheduleWriteback() {
        writebackWork?.cancel()
        status = "正在写回 Hook / Plugin…"
        let work = DispatchWorkItem { writeBack() }
        writebackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Metric.writebackDelay, execute: work)
    }

    private func writeBack() {
        writebackWork = nil
        settings.flushSave()
        do {
            try QoderHookInstaller.install()
        } catch {
            status = "Qoder Hook 写入失败：\(error.localizedDescription)"
            Log.error("writeBack: Qoder Hook failed (\(error))", topic: "settings")
            return
        }
        do {
            try OpenCodePluginInstaller.install()
        } catch {
            status = "OpenCode Plugin 写入失败：\(error.localizedDescription)"
            Log.error("writeBack: OpenCode Plugin failed (\(error))", topic: "settings")
            return
        }
        status = "已自动写回 Hook / Plugin · " + Self.clock.string(from: Date())
    }

    private func resetDefaults() {
        settings.resetAll()
        scheduleWriteback()
        status = "已恢复默认"
    }

    private func auditionSound(_ def: SettingDefinition) {
        if case .string(let name) = def.get(), !name.isEmpty,
           FeedbackService.playSound(name) {
            status = "已播放提示音"
        } else {
            status = "该音不可用或未选"
        }
    }

    private func auditionHaptic() {
        status = FeedbackService.buzz() ? "已震动" : "本机不支持触控板震动"
    }

    private func flushOnClose() {
        settings.flushSave()
        if writebackWork != nil {
            writebackWork?.cancel()
            writeBack()
        }
    }
}

/// `.sidebar` material背板, matching the Python panel's translucent category
/// list (NSVisualEffectView, blended behind the window).
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
