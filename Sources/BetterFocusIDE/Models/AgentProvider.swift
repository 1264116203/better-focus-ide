// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 通过 Socket 发送事件的编码智能体提供方。
///
/// 每个值对应 hook 侧 `_identify_product()` 决策树的一种输出，或新宿主自身的
/// provider 标识：
/// - `qoder`：独立 Qoder（QODER_STANDALONE=1）
/// - `opencode`：OpenCode JS 插件
/// - `jetbrains_plugin`：JetBrains IDE 内的 Qoder 插件
/// - `qoder_ide`：Qoder IDE（通义灵码）
/// - `qoder_cli`：终端 CLI 模式（无头脚本）
/// - `cursor`：Cursor 用户级 hooks（`~/.cursor/hooks.json`）
/// - `workbuddy`：WorkBuddy 用户级 hooks（`~/.workbuddy/settings.json`）
/// - `claude_code`：Claude Code 用户级 hooks（`~/.claude/settings.json`）
/// - `trae` / `trae_cn`：Trae / Trae CN 用户级 hooks（`~/.trae{,-cn}/hooks.json`）
/// - `kimi`：Kimi Code CLI（`~/.kimi-code/config.toml` 的 `[[hooks]]`）
/// - `codex`：ChatGPT 桌面版（原 Codex，bundle `com.openai.codex`；
///   `~/.codex/config.toml` 的 `notify`）
/// - `copilot`：GitHub Copilot CLI（`~/.copilot/hooks/betterfocus.json`）
/// - `qoder_cn*`：Qoder CN（通义灵码）同名产品，识别结果由启动器里的
///   `BETTERFOCUS_VARIANT=cn` 决定（见 `HelperTemplate`）
/// - `unknown`：无法识别
enum AgentProvider: String, CaseIterable, Codable {
    case qoder
    case opencode
    case jetbrains_plugin
    case qoder_ide
    case qoder_cli
    case cursor
    case workbuddy
    case claude_code
    case codex
    case trae
    case trae_cn
    case kimi
    case copilot
    case qoder_cn
    case qoder_cn_ide
    case qoder_cn_cli
    case unknown

    /// 界面展示名称（用于徽章首字母、来源文案等）。
    ///
    /// 注意：JetBrains 插件模式返回空字符串，强制使用 host.name（具体 IDE 名称如
    /// "IntelliJ IDEA"、"PyCharm"）；其他提供方返回各自的展示名。
    var displayName: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
        case .jetbrains_plugin: return ""  // 必须由 host.name 提供具体 IDE 名称
        case .qoder_ide: return "Qoder"
        case .qoder_cli: return "Qoder CLI"
        case .cursor: return "Cursor"
        case .workbuddy: return "WorkBuddy"
        case .claude_code: return "Claude Code"
        case .codex: return "ChatGPT"
        case .trae: return "Trae"
        case .trae_cn: return "Trae CN"
        case .kimi: return "Kimi"
        case .copilot: return "Copilot"
        case .qoder_cn: return "Qoder CN"
        case .qoder_cn_ide: return "Qoder CN IDE"
        case .qoder_cn_cli: return "Qoder CN CLI"
        case .unknown: return "Unknown"
        }
    }

    /// 是否为「跑在终端里的 CLI 产品」。
    ///
    /// 这类产品没有自己的窗口，卡片上要标成「产品（终端）」并借用终端图标，
    /// 点击时也要把终端窗口激活到前台。IDE / 桌面应用返回 false。
    var isCLI: Bool {
        switch self {
        case .claude_code, .codex, .kimi, .copilot, .qoder_cli, .qoder_cn_cli:
            return true
        case .qoder, .opencode, .jetbrains_plugin, .qoder_ide, .cursor,
             .workbuddy, .trae, .trae_cn, .qoder_cn, .qoder_cn_ide, .unknown:
            return false
        }
    }

    /// 提供方的主题色（用于徽章着色，实时取自 Settings）。
    var tint: Color {
        let c = tintRGB
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// 原始 RGB 分量。
    ///
    /// 供无法使用 SwiftUI `Color` 的场景（视图层之前存储的历史条目、
    /// AppKit 绘制）使用。在调用时读取 Settings，因此 qoder_tint /
    /// opencode_tint 的修改可实时生效。
    var tintRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .qoder, .jetbrains_plugin, .qoder_ide, .qoder_cli,
             .qoder_cn, .qoder_cn_ide, .qoder_cn_cli:
            // Qoder 系（含 CN 发行版）共用一个可配置主题色：同一个产品的
            // 两种发行版，没有理由让用户在设置里分别调两次。
            let c = Settings.shared.qoderTintRGB
            return (c.r, c.g, c.b)
        case .opencode:
            let c = Settings.shared.opencodeTintRGB
            return (c.r, c.g, c.b)
        case .cursor:
            let c = Settings.shared.cursorTintRGB
            return (c.r, c.g, c.b)
        case .workbuddy:
            let c = Settings.shared.workbuddyTintRGB
            return (c.r, c.g, c.b)
        // 以下宿主用固定品牌色：它们各自只有一个身份，不需要用户配置。
        case .claude_code: return (0.85, 0.55, 0.25)   // Anthropic 橙
        case .codex: return (0.15, 0.65, 0.45)         // OpenAI 绿
        case .trae, .trae_cn: return (0.25, 0.48, 0.95) // 字节蓝
        case .kimi: return (0.35, 0.30, 0.75)          // 月之暗面紫蓝
        case .copilot: return (0.55, 0.36, 0.96)       // Copilot 紫
        case .unknown:
            return (red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    /// 归组到 IDE 跳转用的提供方键（`qoder` / `opencode` / `cursor` / `workbuddy`）。
    ///
    /// `IDELauncher.ideBundles` 按大类索引，产品细分值需映射回组键才能查到
    /// 对应的 bundle id 列表。
    var providerGroup: String {
        switch self {
        case .opencode: return "opencode"
        case .cursor: return "cursor"
        case .workbuddy: return "workbuddy"
        case .trae, .trae_cn: return "trae"
        case .kimi: return "kimi"
        case .copilot: return "copilot"
        case .claude_code: return "claude_code"
        case .codex: return "codex"
        case .qoder, .jetbrains_plugin, .qoder_ide, .qoder_cli,
             .qoder_cn, .qoder_cn_ide, .qoder_cn_cli, .unknown:
            return "qoder"
        }
    }

    /// 获取有效的展示名称：优先使用 host.name（具体 IDE 名称），回退到 displayName。
    ///
    /// 对于 JetBrains 插件模式，displayName 为空，必须依赖 host.name 提供具体名称
    /// （如 "IntelliJ IDEA"、"PyCharm"）。如果 host.name 也为空，返回 "JetBrains"
    /// 作为最终兜底。
    static func effectiveName(provider: AgentProvider, hostName: String?) -> String {
        // 优先使用 host.name（具体 IDE 名称）
        if let name = hostName, !name.isEmpty {
            return name
        }
        // 回退到 provider.displayName
        let displayName = provider.displayName
        if !displayName.isEmpty {
            return displayName
        }
        // JetBrains 插件模式且 host.name 缺失：最终兜底
        if provider == .jetbrains_plugin {
            return "JetBrains"
        }
        return "Unknown"
    }

    /// 卡片 / 历史 / 横幅上展示的完整来源名。
    ///
    /// CLI 类产品（Claude Code / Codex / Kimi / Qoder CLI / Qoder CN CLI）本身
    /// 没有窗口，跑在某个终端里。此时只写产品名分不清是哪个终端里的会话，
    /// 只写终端名又丢了产品——所以标成 `产品（终端）`，例如：
    ///
    /// - `Qoder CLI（Warp）`
    /// - `Qoder CN CLI（iTerm）`
    /// - `Claude Code（Ghostty）`
    ///
    /// 终端识别优先用 bundle ID（可靠），名称是兜底（hook 在某些容器里拿不到 bundle）。
    /// 认不出终端时退回 `effectiveName`，也就是产品名本身。
    static func label(provider: AgentProvider,
                      hostName: String?,
                      bundleID: String? = nil) -> String {
        if provider.isCLI {
            // 认得出终端才加括号标注；认不出就只写产品名。
            // 不能退回 host.name——CLI 的祖先进程往往是「启动它的那个宿主」
            // （IDE、甚至另一个 agent），把 "WorkBuddy" 当成来源会掩盖真正的产品。
            if let terminal = TerminalHost.displayName(bundle: bundleID, name: hostName) {
                return "\(provider.displayName)（\(terminal)）"
            }
            return provider.displayName
        }
        // GUI 宿主：默认信 host.name，它能区分同一个产品下的具体 IDE
        //（JetBrains 插件必须靠它显示 "IntelliJ IDEA" 而不是 "Qoder"）。
        // 但祖先链可能根本没走到产品自身——脚本被别的应用拉起、或在别人的
        // 终端里手动跑——那时 host 报的是那个「别人」。实测在 WorkBuddy 的
        // shell 里触发 Trae CN 的 hook，卡片会写成 "WorkBuddy 回复完成"。
        // 所以先校验 bundle 归属：明确属于另一个应用家族时，只写产品名。
        if let bundle = bundleID, !bundle.isEmpty,
           let family = IDELauncher.group(for: bundle),
           family != provider.providerGroup,
           provider != .jetbrains_plugin,
           !provider.displayName.isEmpty {
            return provider.displayName
        }
        return effectiveName(provider: provider, hostName: hostName)
    }

    /// 获取徽章文本：取有效展示名称的首字母大写。
    static func badgeText(provider: AgentProvider,
                          hostName: String?,
                          bundleID: String? = nil) -> String {
        let name = label(provider: provider, hostName: hostName, bundleID: bundleID)
        return String(name.prefix(1)).uppercased()
    }

    /// 徽章图标该按哪个身份去找图标与品牌色。
    ///
    /// - CLI 宿主：用**终端**身份（`Claude Code` 的图标就是它跑在的那个终端）。
    /// - GUI 宿主：用**产品自己**的身份。正常情况下 host 就是产品，原样返回；
    ///   但 host 的 bundle 明确属于另一个应用家族时（祖先链没走到产品），
    ///   若继续用 host 就会「文字写 Trae CN、图标画 WorkBuddy」——两者必须同源。
    static func iconIdentity(provider: AgentProvider,
                             hostName: String?,
                             bundleID: String?) -> (name: String?, bundle: String?) {
        guard !provider.isCLI else { return (hostName, bundleID) }
        guard let bundle = bundleID, !bundle.isEmpty,
              let family = IDELauncher.group(for: bundle),
              family != provider.providerGroup,
              provider != .jetbrains_plugin,
              !provider.displayName.isEmpty else {
            return (hostName, bundleID)
        }
        return (provider.displayName, IDELauncher.ideBundles[provider.providerGroup]?.first)
    }

    /// 同上，接受原始字符串标识（历史条目里存的是 rawValue）。
    static func iconIdentity(provider: String,
                             hostName: String?,
                             bundleID: String?) -> (name: String?, bundle: String?) {
        guard let provider = AgentProvider(rawValue: provider) else {
            return (hostName, bundleID)
        }
        return iconIdentity(provider: provider, hostName: hostName, bundleID: bundleID)
    }
}
