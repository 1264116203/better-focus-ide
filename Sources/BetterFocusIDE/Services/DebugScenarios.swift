// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

// MARK: - 目标 IDE

/// 调试面板可选的"目标 IDE"。
///
/// 只伪造 hook 上报的 `provider` / `product` / `host` 三处身份字段，其余全程走与真实事件
/// 相同的分发链路——因此卡片上的图标、来源名、主题色和点击跳转目标都与真机一致，
/// 不需要为了看一眼 WorkBuddy 的图标真的去开一次 WorkBuddy。
struct DebugTarget: Identifiable, Hashable {
    let provider: AgentProvider
    /// 面板下拉里显示的名字。
    let title: String
    /// 真实 bundle id（决定图标与跳转目标）。
    let bundle: String
    /// 宿主应用名（决定卡片上的来源文案）。
    let hostName: String

    /// 面板下拉里的 id。用 title 而非 provider.rawValue：同一个 CLI 产品会在
    /// 不同终端下各占一条（如 `Qoder CLI（Warp）` 与 `Qoder CLI（iTerm）`），
    /// 若用 provider 当 id 就会重复、Picker 与 ForEach 都会错乱。
    var id: String { title }

    /// 上报给 socket 的宿主身份字典（与 hook 的 `host` 字段同构）。
    ///
    /// `cwd` 是消息顶层字段而非 `host` 子字段：真实 hook 的 `host` 里只有
    /// bundle / name / path 三项，cwd 单独上报。放错位置会让历史条目里的
    /// 工作目录丢成空串。
    func host(project: String) -> [String: AnyCodableValue] {
        [
            "bundle": .string(bundle),
            "name": .string(hostName),
            "path": .string("/Applications/\(hostName).app"),
        ]
    }

    /// 模拟工作目录：卡片上那句「项目名」取自它的末级目录。
    static func cwd(project: String) -> String {
        let leaf = project.trimmingCharacters(in: .whitespaces)
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Documents/\(leaf.isEmpty ? "demo-project" : leaf)")
    }

    /// 覆盖所有宿主的全部产品细分。
    ///
    /// GUI 宿主用产品自己的 bundle/名字（决定图标与跳转）；CLI 宿主用终端
    /// bundle/名字——图标画终端、跳转激活终端、卡片标成「产品（终端）」
    /// （见 `AgentProvider.label`）。终端这里挑了 Warp / iTerm / Terminal 三种
    /// 代表性形态，都归到同一产品下，方便对比三种终端下卡片的样子。
    static let all: [DebugTarget] = [
        // ---------------- Qoder 家族 ----------------
        DebugTarget(provider: .qoder, title: "Qoder", bundle: "com.qoder.app",
                    hostName: "Qoder"),
        DebugTarget(provider: .qoder_ide, title: "Qoder IDE", bundle: "com.qoder.ide",
                    hostName: "Qoder IDE"),
        DebugTarget(provider: .jetbrains_plugin, title: "IntelliJ IDEA",
                    bundle: "com.jetbrains.intellij", hostName: "IntelliJ IDEA"),
        DebugTarget(provider: .opencode, title: "OpenCode", bundle: "ai.opencode.desktop",
                    hostName: "OpenCode"),
        // ---------------- Qoder CN 家族 ----------------
        DebugTarget(provider: .qoder_cn, title: "Qoder CN", bundle: "com.qoder.app",
                    hostName: "Qoder CN"),
        DebugTarget(provider: .qoder_cn_ide, title: "Qoder CN IDE", bundle: "com.aliyun.lingma.ide",
                    hostName: "Qoder CN IDE"),
        // ---------------- 新一代 Agent 宿主 ----------------
        DebugTarget(provider: .cursor, title: "Cursor",
                    bundle: "com.todesktop.230313mzl4w4u92", hostName: "Cursor"),
        DebugTarget(provider: .workbuddy, title: "WorkBuddy",
                    bundle: "com.tencent.workbuddy.mac", hostName: "WorkBuddy"),
        DebugTarget(provider: .trae, title: "Trae",
                    bundle: "com.trae.app", hostName: "Trae"),
        DebugTarget(provider: .trae_cn, title: "Trae CN",
                    bundle: "cn.trae.app", hostName: "Trae CN"),
        DebugTarget(provider: .kimi, title: "Kimi（终端）",
                    bundle: "dev.warp.Warp-Stable", hostName: "Warp"),
        // ---------------- CLI 宿主（跑在终端里） ----------------
        DebugTarget(provider: .qoder_cli, title: "Qoder CLI（Warp）",
                    bundle: "dev.warp.Warp-Stable", hostName: "Warp"),
        DebugTarget(provider: .qoder_cli, title: "Qoder CLI（iTerm）",
                    bundle: "com.googlecode.iterm2", hostName: "iTerm"),
        DebugTarget(provider: .qoder_cn_cli, title: "Qoder CN CLI（Warp）",
                    bundle: "dev.warp.Warp-Stable", hostName: "Warp"),
        DebugTarget(provider: .qoder_cn_cli, title: "Qoder CN CLI（iTerm）",
                    bundle: "com.googlecode.iterm2", hostName: "iTerm"),
        DebugTarget(provider: .claude_code, title: "Claude Code（Terminal）",
                    bundle: "com.apple.Terminal", hostName: "Terminal"),
        DebugTarget(provider: .codex, title: "ChatGPT（Terminal）",
                    bundle: "com.apple.Terminal", hostName: "Terminal"),
        DebugTarget(provider: .copilot, title: "Copilot（Terminal）",
                    bundle: "com.apple.Terminal", hostName: "Terminal"),
        DebugTarget(provider: .kimi, title: "Kimi（Terminal）",
                    bundle: "com.apple.Terminal", hostName: "Terminal"),
    ]

    /// 支持 todowrite 转发的宿主（用于「各 IDE 快速验证」按钮）。
    ///
    /// Cursor / Trae / Codex 的 hook 收不到 todo 事件（见 todo-tool-adaptation
    /// 调研），即使这里伪造 provider 也测不出真实链路，故不列入快速按钮。
    /// 保留 Qoder、OpenCode、Claude Code、Kimi、WorkBuddy 五个真正能收到
    /// 事件的宿主——每个对应 `all` 里的一条，点按钮即以其身份注入标准进度。
    static let todoCapable: [DebugTarget] = [
        DebugTarget(provider: .qoder, title: "Qoder", bundle: "com.qoder.app",
                    hostName: "Qoder"),
        DebugTarget(provider: .opencode, title: "OpenCode", bundle: "ai.opencode.desktop",
                    hostName: "OpenCode"),
        DebugTarget(provider: .claude_code, title: "Claude Code", bundle: "com.apple.Terminal",
                    hostName: "Terminal"),
        DebugTarget(provider: .kimi, title: "Kimi", bundle: "com.apple.Terminal",
                    hostName: "Terminal"),
        DebugTarget(provider: .workbuddy, title: "WorkBuddy",
                    bundle: "com.tencent.workbuddy.mac", hostName: "WorkBuddy"),
    ]
}

// MARK: - 载荷模板

/// 一个问题的调试模板（对应 `questions[]` 里的一项）。
struct DebugQuestion {
    let header: String
    let text: String
    let options: [(label: String, description: String)]
    var multiSelect: Bool = false
}

/// 一次权限请求的调试模板。
struct DebugPermission {
    let toolName: String
    /// 归一化动作；留空则按 `tool_name` 推导（用于验证推导逻辑本身）。
    let action: String
    let resources: [String]
    let toolInput: [String: String]
    var agent: String = ""
}

/// 一个调试场景要注入的事件形态。
enum DebugPayload {    /// 提问请求：数组内多问题 = 卡片分页。
    case question([DebugQuestion])
    case permission(DebugPermission)
    /// 权限提醒（只提醒、不拦截，以横幅出现）。
    case permissionNotice(toolName: String, resource: String)
    /// 回复完成横幅：标题 / 正文由合成的 transcript 提供，留空则走兜底文案。
    case turnFinished(title: String, body: String)
    /// 失败、子任务、待审阅、上下文压缩。标题和正文直接写进横幅。
    case statusNotice(SocketEvent, title: String, body: String)
    /// 任务进度：`todos[]` 每项一句正文 + 原始状态字符串。
    case todo([(content: String, status: String)])
    case sessionEnded
    /// 不走 socket，直接调服务方法。
    case history
    case clearCards
    case clearHistory
}

/// 调试页里的一个可触发场景。
struct DebugScene: Identifiable {
    let id: String
    let group: String
    let title: String
    let note: String
    let payload: DebugPayload
}

// MARK: - 场景目录

/// 调试页的场景清单：按卡片类型分组，覆盖 hook 能上报的每一种事件形态。
enum DebugCatalog {
    static let groups = ["提问卡片", "权限卡片", "通知横幅", "状态横幅", "任务进度", "其他"]

    static func scenes(in group: String) -> [DebugScene] {
        scenes.filter { $0.group == group }
    }

    static let scenes: [DebugScene] = [
        // ---------------- 提问卡片 ----------------
        DebugScene(
            id: "question.single",
            group: "提问卡片",
            title: "单选提问",
            note: "三个带描述的选项，最普通的提问卡片",
            payload: .question([
                DebugQuestion(
                    header: "下一步",
                    text: "通知队列的优先级还需要定一下，接下来先做哪一块？",
                    options: [
                        (label: "按来源 IDE 排队",
                         description: "同一宿主连发多条时合并，不同 IDE 之间互不打断"),
                        (label: "保持先到先服务",
                         description: "实现简单，但多个 IDE 同时卡住时无从取舍"),
                        (label: "先补单元测试",
                         description: "把队列边界用例锁死，再动实现"),
                    ]),
            ])),
        DebugScene(
            id: "question.multi",
            group: "提问卡片",
            title: "多选提问",
            note: "multiSelect = true，勾选多项后一次提交",
            payload: .question([
                DebugQuestion(
                    header: "需要改动哪些位置",
                    text: "这次收口会同时影响以下几处，勾选你想让我一并改掉的：",
                    options: [
                        (label: "NotchService", description: "卡片调度与尺寸计算"),
                        (label: "三个 Controller", description: "队列与去抖逻辑"),
                        (label: "SettingsView", description: "调试页入口与分组"),
                        (label: "Hook 模板", description: "上报字段与超时值"),
                    ],
                    multiSelect: true),
            ])),
        DebugScene(
            id: "question.pages",
            group: "提问卡片",
            title: "多个问题（分页）",
            note: "一次请求带两问，单选后自动翻到下一页",
            payload: .question([
                DebugQuestion(
                    header: "范围",
                    text: "先确认改动范围：只动灵动岛本体，还是一并调整 hook 上报？",
                    options: [
                        (label: "只动本体", description: "hook 侧协议不变"),
                        (label: "一起调整", description: "需要重装四个宿主"),
                    ]),
                DebugQuestion(
                    header: "节奏",
                    text: "这两个改动希望一次提交，还是拆成两次提交？",
                    options: [
                        (label: "一次提交", description: "改动内聚，回滚方便"),
                        (label: "拆成两次", description: "协议变更单独可回滚"),
                    ]),
            ])),
        DebugScene(
            id: "question.long",
            group: "提问卡片",
            title: "长文本提问",
            note: "正文五六行，验证卡片高度自适应与省略",
            payload: .question([
                DebugQuestion(
                    header: "上下文说明",
                    text: """
                    现在的问题是：多个 IDE 同时抛请求时，岛只会展示最先到达的那一条，后面的全部进队列，\
                    而队列没有超时概念。用户看到的是"卡片一直在，但 IDE 那边早就超时回落了"。\
                    如果给排队项加倒计时，又会出现卡片刚上屏就倒计时到 0 的极端情况。\
                    你更倾向于哪种收口方式？
                    """,
                    options: [
                        (label: "排队项也计时", description: "入队即开始倒计时，超时直接丢弃"),
                        (label: "只保留最新一条", description: "新请求到达时顶掉排队项"),
                    ]),
            ])),
        DebugScene(
            id: "question.custom",
            group: "提问卡片",
            title: "极简提问（无选项）",
            note: "没有选项时只剩「其他…」输入框，验证卡片退化形态",
            payload: .question([
                DebugQuestion(header: "自由回答", text: "你希望这条通知停留多久？", options: []),
            ])),

        // ---------------- 权限卡片 ----------------
        DebugScene(
            id: "permission.shell",
            group: "权限卡片",
            title: "终端命令",
            note: "action = shell，详情取完整命令行",
            payload: .permission(DebugPermission(
                toolName: "Bash",
                action: "shell",
                resources: ["swift build -c debug 2>&1 | tail -n 40"],
                toolInput: ["command": "swift build -c debug 2>&1 | tail -n 40"]))),
        DebugScene(
            id: "permission.edit",
            group: "权限卡片",
            title: "修改文件",
            note: "action = edit，详情取文件路径",
            payload: .permission(DebugPermission(
                toolName: "Edit",
                action: "edit",
                resources: ["~/Documents/lingyue-projects/better-focus-ide/Sources/BetterFocusIDE/Services/NotchService.swift"],
                toolInput: ["file_path": "Sources/BetterFocusIDE/Services/NotchService.swift"]))),
        DebugScene(
            id: "permission.mcp",
            group: "权限卡片",
            title: "MCP 工具",
            note: "留空 action，验证 mcp__ 前缀推导为「MCP 工具」",
            payload: .permission(DebugPermission(
                toolName: "mcp__playwright__browser_click",
                action: "",
                resources: ["selector=#submit-button"],
                toolInput: ["selector": "#submit-button"]))),
        DebugScene(
            id: "permission.noDetail",
            group: "权限卡片",
            title: "无详情权限",
            note: "没有 resources 也没有 tool_input，卡片只剩标题与按钮",
            payload: .permission(DebugPermission(
                toolName: "permission", action: "", resources: [], toolInput: [:]))),
        DebugScene(
            id: "permission.subagent",
            group: "权限卡片",
            title: "子智能体发起",
            note: "带 agent 字段，标题会标注「Agent（名字）」",
            payload: .permission(DebugPermission(
                toolName: "Grep",
                action: "grep",
                resources: ["pattern=permissionHold", "path=Sources/"],
                toolInput: ["pattern": "permissionHold", "path": "Sources/"],
                agent: "explorer"))),

        // ---------------- 通知横幅 ----------------
        DebugScene(
            id: "notice.turn",
            group: "通知横幅",
            title: "回复完成",
            note: "标题取会话首条提问、正文取最近一轮，点击跳回 IDE",
            payload: .turnFinished(
                title: "把灵动岛的通知队列改成按来源排队",
                body: "顺手把队列上限提到了 8 条，超出的会被挤掉")),
        DebugScene(
            id: "notice.turnLong",
            group: "通知横幅",
            title: "回复完成（长文本）",
            note: "正文超长时截断并补省略号，验证单行排版",
            payload: .turnFinished(
                title: "通读 hook 模板并核对四家宿主的上报字段是否一致",
                body: "我已经把 Qoder、OpenCode、Cursor、WorkBuddy 四份模板逐字段比对了一遍，发现 Cursor 的 tool_input 用的是 camelCase，其余三家是下划线，因此解析处需要兼容两种键名，否则标题会退化成「操作」。")),
        DebugScene(
            id: "notice.turnFallback",
            group: "通知横幅",
            title: "回复完成（无会话记录）",
            note: "transcript 缺失时的兜底文案「… 回复完成」",
            payload: .turnFinished(title: "", body: "")),
        DebugScene(
            id: "notice.permission",
            group: "通知横幅",
            title: "权限提醒（只提醒，不拦截）",
            note: "Qoder / Cursor / WorkBuddy 走这条：只弹提醒，审批看宿主自己的弹窗",
            payload: .permissionNotice(toolName: "Bash",
                                       resource: "npm publish --access public")),

        // ---------------- 状态横幅 ----------------
        DebugScene(
            id: "status.toolFailure",
            group: "状态横幅",
            title: "工具没有跑成",
            note: "PostToolUseFailure：工具名和报错写在正文",
            payload: .statusNotice(.failureNotice, title: "工具没有跑成",
                                   body: "Bash：swift test 退出码 1，HistoryEntryLabelTests 有 2 项失败")),
        DebugScene(
            id: "status.stopFailure",
            group: "状态横幅",
            title: "这一轮没有完成",
            note: "StopFailure：模型这一轮自己停在报错上",
            payload: .statusNotice(.failureNotice, title: "这一轮没有完成",
                                   body: "rate_limit：请求过于频繁，稍后再试")),
        DebugScene(
            id: "status.denied",
            group: "状态横幅",
            title: "自动模式拒绝",
            note: "PermissionDenied：自动模式替你拒绝了这次操作",
            payload: .statusNotice(.failureNotice, title: "自动模式拒绝了这次操作",
                                   body: "Bash：rm -rf ~/Documents/archive")),
        DebugScene(
            id: "status.quota",
            group: "状态横幅",
            title: "额度不足",
            note: "Notification quota_*：额度用完，宿主不会继续跑",
            payload: .statusNotice(.failureNotice, title: "额度不足",
                                   body: "本周额度已用完，等到下个周期或换一个账号")),
        DebugScene(
            id: "status.auth",
            group: "状态横幅",
            title: "登录状态失效",
            note: "Notification auth_storage_failure：需要回宿主重新登录",
            payload: .statusNotice(.failureNotice, title: "登录状态失效",
                                   body: "登录凭证读不出来，打开宿主重新登录后再继续")),
        DebugScene(
            id: "status.subagent",
            group: "状态横幅",
            title: "子任务完成",
            note: "SubagentStop：子代理结束，正文是它最后一句",
            payload: .statusNotice(.subagentFinished, title: "子任务完成",
                                   body: "已把四个宿主的 hook 事件对过，Cursor 只观察、不回决策")),
        DebugScene(
            id: "status.document",
            group: "状态横幅",
            title: "文档待审阅",
            note: "Notification document_review：计划或文档在等你看",
            payload: .statusNotice(.reviewNotice, title: "文档待审阅",
                                   body: "实施计划已写好，回到宿主确认后再继续")),
        DebugScene(
            id: "status.browser",
            group: "状态横幅",
            title: "浏览器在等你",
            note: "Notification browser_interaction：页面停在需要人操作的地方",
            payload: .statusNotice(.reviewNotice, title: "浏览器在等你",
                                   body: "登录页已打开，完成验证后告诉宿主继续")),
        DebugScene(
            id: "status.input",
            group: "状态横幅",
            title: "需要你的输入",
            note: "Elicitation 捞不到题面时的兜底，题面在宿主对话框里",
            payload: .statusNotice(.reviewNotice, title: "需要你的输入",
                                   body: "宿主弹出了补充信息框，岛上没有题面")),
        DebugScene(
            id: "status.compacted",
            group: "状态横幅",
            title: "上下文已压缩",
            note: "PostCompact：压缩已经做完",
            payload: .statusNotice(.compactNotice, title: "上下文已压缩",
                                   body: "较早的对话已被收成摘要")),
        DebugScene(
            id: "status.compacting",
            group: "状态横幅",
            title: "即将压缩上下文",
            note: "PreCompact：Cursor / Copilot / Qoder 只有这一条",
            payload: .statusNotice(.compactNotice, title: "即将压缩上下文",
                                   body: "上下文快满了，宿主准备收成摘要")),

        // ---------------- 任务进度 ----------------
        DebugScene(
            id: "todo.running",
            group: "任务进度",
            title: "进行中（6 项）",
            note: "3 项已完成、1 项进行中、2 项待开始；收起后气泡下沿仍有进度线，再点可展开",
            payload: .todo([
                (content: "读一遍各宿主的 hook 文档", status: "completed"),
                (content: "定下任务条的信息层级", status: "completed"),
                (content: "实现分段进度条与呼吸态", status: "completed"),
                (content: "补充 hooks 模板的 todo matcher", status: "in_progress"),
                (content: "验证事件回传与断线重连", status: "pending"),
                (content: "补齐收起态下沿进度线", status: "pending"),
            ])),
        DebugScene(
            id: "todo.many",
            group: "任务进度",
            title: "12 项（自动分桶）",
            note: "超过 8 项时改成 8 段，每段按桶内完成比例部分填充",
            payload: .todo((0..<12).map { index in
                (content: "第 \(index + 1) 步：梳理接入细节",
                 status: index < 5 ? "completed" : (index == 5 ? "in_progress" : "pending"))
            })),
        DebugScene(
            id: "todo.finished",
            group: "任务进度",
            title: "全部完成",
            note: "4 项全部打勾后进入收尾态，2.5s 后自动收起",
            payload: .todo([
                (content: "读一遍各宿主的 hook 文档", status: "completed"),
                (content: "定下任务条的信息层级", status: "completed"),
                (content: "实现分段进度条与呼吸态", status: "completed"),
                (content: "验证事件回传与断线重连", status: "completed"),
            ])),

        // ---------------- 其他 ----------------
        DebugScene(
            id: "other.sessionEnded",
            group: "其他",
            title: "会话结束",
            note: "结束刚才那条提问 / 权限所在的会话，卡片随之撤下",
            payload: .sessionEnded),
        DebugScene(
            id: "other.history",
            group: "其他",
            title: "最近通知面板",
            note: "空闲态点气泡的效果（最近 5 条历史）",
            payload: .history),
        DebugScene(
            id: "other.clearCards",
            group: "其他",
            title: "清空所有卡片",
            note: "提问 / 权限 / 通知一并撤下，不写任何应答文件",
            payload: .clearCards),
        DebugScene(
            id: "other.clearHistory",
            group: "其他",
            title: "清空历史记录",
            note: "删掉 history.json，列表回到空态",
            payload: .clearHistory),
    ]
}

// MARK: - 注入器

/// 调试面板的事件注入器：把场景翻译成与 hook 完全同构的 socket 消息，再交给
/// `NotchService` 走正常分发（仅绕过「提醒」开关门控，见 `injectDebugMessage`）。
enum DebugInjector {
    /// 最近一条注入的、等着人回答的会话：「会话结束」要结束的是它。
    private static var pendingSession: String?
    /// 合成 transcript 的落盘目录。
    private static var transcriptDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BetterFocusIDE-debug", isDirectory: true)
    }

    /// 触发一个场景，返回展示在面板上的结果文案。
    @discardableResult
    static func fire(_ scene: DebugScene, target: DebugTarget, project: String) -> String {
        let service = NotchService.shared
        let session = sessionID(for: scene)

        switch scene.payload {
        case .question(let items):
            service.flushDebugChannels()
            remember(session)
            service.injectDebugMessage(message(
                event: .questionRequested, payload: questionPayload(items),
                target: target, sessionID: session, project: project))

        case .permission(let spec):
            service.flushDebugChannels()
            remember(session)
            service.injectDebugMessage(message(
                event: .permissionRequested, payload: permissionPayload(spec),
                target: target, sessionID: session, project: project))

        case .permissionNotice(let toolName, let resource):
            service.flushDebugChannels()
            service.injectDebugMessage(message(
                event: .permissionNotice,
                payload: [
                    "request_id": .string(shortID()),
                    "tool_name": .string(toolName),
                    "resources": .array([.string(resource)]),
                ],
                target: target, sessionID: session, project: project))

        case .turnFinished(let title, let body):
            service.flushDebugChannels()
            var payload: [String: AnyCodableValue] = [:]
            if let path = writeTranscript(session: session, title: title, body: body,
                                          provider: target.provider) {
                payload["transcript_path"] = .string(path)
            }
            service.injectDebugMessage(message(
                event: .turnFinished, payload: payload,
                target: target, sessionID: session, project: project))

        case .statusNotice(let event, let title, let body):
            service.flushDebugChannels()
            service.injectDebugMessage(message(
                event: event,
                payload: ["title": .string(title), "body": .string(body)],
                target: target, sessionID: session, project: project))

        case .todo(let items):
            service.flushDebugChannels()
            let todos: [AnyCodableValue] = items.enumerated().map { index, item in
                .dictionary([
                    "id": .string("t\(index + 1)"),
                    "content": .string(item.content),
                    "status": .string(item.status),
                ])
            }
            service.injectDebugMessage(message(
                event: .todoUpdated, payload: ["todos": .array(todos)],
                target: target, sessionID: session, project: project))

        case .sessionEnded:
            // 会话结束按 `session_id` 匹配，只有带着刚才那条会话才清得掉卡片。
            guard let ended = pendingSession else {
                return "没有待结束的会话——先触发一条提问或权限"
            }
            pendingSession = nil
            service.injectDebugMessage(message(
                event: .sessionEnded, payload: [:],
                target: target, sessionID: ended, project: project))
            Log.info("调试注入：结束会话 \(ended)", topic: "debug")
            return "已结束该会话，卡片随之撤下"

        case .history:
            service.showHistory()
            return "已打开最近通知面板"

        case .clearCards:
            pendingSession = nil
            service.clearDebugCards()
            return "已清空所有卡片"

        case .clearHistory:
            service.clearDebugHistory()
            return "已清空历史记录"
        }

        Log.info("调试注入：\(scene.id) → \(target.title)（\(session)）", topic: "debug")
        return "已触发「\(scene.title)」 · \(target.title)"
    }

    // MARK: 消息组装

    /// 各 IDE 快速验证：以指定宿主身份注入一条标准的「进行中」任务进度，
    /// 无需先到顶部选目标 IDE。返回展示在面板上的结果文案。
    ///
    /// 进度内容固定为 6 项（3 完成 / 1 进行中 / 2 待开始），与「任务进度」分组的
    /// `todo.running` 场景一致——快速按钮与逐项触发得到的是同一张卡片，方便对比
    /// 「换宿主身份后徽章 / 主题色 / 跳转目标是否随之变化」。
    @discardableResult
    static func fireTodoQuick(target: DebugTarget, project: String) -> String {
        let service = NotchService.shared
        let session = "debug-todoquick-\(Int(Date().timeIntervalSince1970 * 1000))"
        service.flushDebugChannels()

        let sample: [(String, String)] = [
            ("读一遍各宿主的 hook 文档", "completed"),
            ("定下任务条的信息层级", "completed"),
            ("实现分段进度条与呼吸态", "completed"),
            ("补充 hooks 模板的 todo matcher", "in_progress"),
            ("验证事件回传与断线重连", "pending"),
            ("补齐收起态下沿进度线", "pending"),
        ]
        let todos: [AnyCodableValue] = sample.enumerated().map { index, item in
            .dictionary([
                "id": .string("t\(index + 1)"),
                "content": .string(item.0),
                "status": .string(item.1),
            ])
        }
        service.injectDebugMessage(message(
            event: .todoUpdated, payload: ["todos": .array(todos)],
            target: target, sessionID: session, project: project))

        Log.info("调试注入（快速）：todo → \(target.title)（\(session)）", topic: "debug")
        return "已以「\(target.title)」身份注入任务进度"
    }

    /// 与真实 hook 的 `_identify_product()` 输出保持一致。
    private static func message(event: SocketEvent, payload: [String: AnyCodableValue],
                                target: DebugTarget, sessionID: String,
                                project: String) -> AgentSocketMessage {
        AgentSocketMessage(
            provider: target.provider.providerGroup,
            product: target.provider.rawValue,
            event: event.rawValue,
            sessionID: sessionID,
            timestamp: Date(),
            payload: payload,
            host: target.host(project: project),
            cwd: DebugTarget.cwd(project: project))
    }

    /// 记下等待回答的会话（同一时刻只有一条卡片在屏，新的会顶掉旧的）。
    private static func remember(_ session: String) {
        pendingSession = session
    }

    /// 提问载荷：`questions[]` 每项一个 header/正文/选项组。
    private static func questionPayload(_ items: [DebugQuestion]) -> [String: AnyCodableValue] {
        let questions: [AnyCodableValue] = items.enumerated().map { index, item in
            .dictionary([
                "id": .string("q\(index + 1)"),
                "header": .string(item.header),
                "question": .string(item.text),
                "multiSelect": .bool(item.multiSelect),
                "options": .array(item.options.map { option in
                    .dictionary([
                        "label": .string(option.label),
                        "description": .string(option.description),
                    ])
                }),
            ])
        }
        return [
            "request_id": .string(shortID()),
            "questions": .array(questions),
        ]
    }

    /// 权限载荷：`request_id` 必须有，否则解析层会直接丢弃（无法应答）。
    private static func permissionPayload(_ spec: DebugPermission) -> [String: AnyCodableValue] {
        var payload: [String: AnyCodableValue] = [
            "request_id": .string(shortID()),
            "action": .string(spec.action),
            "tool_name": .string(spec.toolName),
            "resources": .array(spec.resources.map { .string($0) }),
            "flavor": .string("opencode"),
        ]
        if !spec.agent.isEmpty { payload["agent"] = .string(spec.agent) }
        if !spec.toolInput.isEmpty {
            payload["tool_input"] = .dictionary(spec.toolInput.mapValues { .string($0) })
        }
        return payload
    }

    // MARK: 合成 transcript

    /// 写一份最小的会话记录，让「回复完成」横幅能读到真实的标题与正文
    /// （否则只会显示兜底文案，看不出排版问题）。
    ///
    /// 标题取首条用户轮次、正文取最后一条——与 `Transcript.sessionSummary` 的读法一致；
    /// Cursor 的记录形态不同（`role` + `<user_query>` 包裹），按提供方分别合成。
    private static func writeTranscript(session: String, title: String, body: String,
                                        provider: AgentProvider) -> String? {
        guard !title.isEmpty || !body.isEmpty else { return nil }
        let directory = transcriptDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanupTranscripts(in: directory)

        let records: [[String: Any]]
        if provider.providerGroup == "cursor" {
            records = [cursorRecord(title), cursorRecord(body)]
        } else {
            records = [qoderRecord(title), qoderRecord(body)]
        }
        let lines = records.compactMap { record -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: record) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard !lines.isEmpty else { return nil }

        let file = directory.appendingPathComponent("\(session).jsonl")
        guard (try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true,
                                                                 encoding: .utf8)) != nil else {
            return nil
        }
        return file.path
    }

    /// Qoder 形态的用户轮次：顶层 `type == "user"`，正文在 `message.content` 字符串里。
    private static func qoderRecord(_ text: String) -> [String: Any] {
        ["type": "user",
         "message": ["content": text],
         "humanInput": true]
    }

    /// Cursor 形态：顶层 `role == "user"`，正文是文本块列表并被 `<user_query>` 包裹。
    private static func cursorRecord(_ text: String) -> [String: Any] {
        ["role": "user",
         "message": ["content": [["type": "text", "text": "<user_query>\(text)</user_query>"]]]]
    }

    /// 清掉十分钟前的合成记录，避免临时目录无限堆积。
    private static func cleanupTranscripts(in directory: URL) {
        let cutoff = Date().addingTimeInterval(-600)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: 标识

    /// 每次触发都用新会话 id：否则同一会话的第二次提问会顶掉第一张卡片，
    /// 通知也会被 `NoticeController` 的去抖吞掉。
    private static func sessionID(for scene: DebugScene) -> String {
        "debug-\(scene.id)-\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    /// 短请求标识（与真实 hook 的 request_id 形态一致即可）。
    private static func shortID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}
