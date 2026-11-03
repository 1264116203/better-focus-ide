# AGENTS.md — BetterFocusIDE

## 项目概述

BetterFocusIDE 是一款 macOS 14+ 的附属应用（accessory app，LSUIElement，无 Dock 图标），把 MacBook 的刘海变成面向 AI 编码智能体的"灵动岛"通知助手。它通过 Unix 域套接字接收来自 **Qoder**（Python hook）和 **OpenCode**（JavaScript 插件）的事件，在刘海区域展示可交互卡片（提问、权限请求、回合完成通知），并把用户的回答回传给发起请求的智能体。

- **许可证**：GPL-3.0-or-later
- **来源**：由 Python 项目 `dynamic-Island-python-validate` 迁移为 Swift（动画 / UI 参考 Vorssaint 的实现）
- **运行要求**：macOS 14+，Apple Silicon（`arm64`）
- **技术栈**：Swift 5.9，SwiftPM 库 + 可执行目标，AppKit 窗口外壳 + SwiftUI 内容

## 构建与运行

```bash
# 编译（debug）
swift build -c debug

# 完整构建：编译 + 组装 .app 包 + ad-hoc 签名
./build.sh
# → .build/debug/BetterFocusIDE.app

# 运行
open .build/debug/BetterFocusIDE.app

# 安装到 /Applications
cp -R .build/debug/BetterFocusIDE.app /Applications/
xattr -dr com.apple.quarantine /Applications/BetterFocusIDE.app  # 绕过 Gatekeeper
```

**没有 Xcode 工程** —— 这是一个纯 SwiftPM 库 + 可执行目标。不要生成 `.xcodeproj` 或 `.xcworkspace`。Xcode 可直接打开 `Package.swift`，SwiftUI Preview 在库目标（`BetterFocusIDE`）下可用。

## 目录结构

```
├── Package.swift                          # SPM 清单（库目标 + 瘦可执行目标）
├── build.sh                               # 构建 + .app 组装 + ad-hoc 签名
├── Resources/
│   ├── Info.plist                         # 包元数据（LSUIElement=true, zh-Hans）
│   └── BetterFocusIDE.entitlements        # 沙盒：apple-events + 进程查询
├── Sources/BetterFocusIDE/
│   ├── Library.swift                      # 库入口：public func run()
│   ├── AppDelegate.swift                  # 生命周期、状态栏菜单、单实例守卫
│   ├── App/
│   │   └── main.swift                     # 瘦入口：import BetterFocusIDE; run()
│   ├── Models/                            # 纯数据类型（不含业务逻辑）
│   │   ├── AgentProvider.swift            # Qoder 与 OpenCode 的身份 + 主题色
│   │   ├── AgentQuestion.swift            # 提问卡片模型（多选、选项）
│   │   ├── AgentSocketMessage.swift       # 线协议：Unix socket 上的 JSON
│   │   ├── HistoryEntry.swift             # 通知历史记录
│   │   ├── PermissionRequest.swift        # 权限卡片模型（允许/总是/拒绝）
│   │   └── TurnNotice.swift               # 回合完成通知 + transcript 解析
│   ├── Services/
│   │   ├── Socket/
│   │   │   └── AgentEventSocketServer.swift   # Unix socket 监听器（DispatchSourceRead）
│   │   ├── Installer/
│   │   │   ├── HelperTemplate.swift           # 内嵌的 Python hook 模板
│   │   │   ├── InstallerPaths.swift           # hook/插件安装所用的文件路径
│   │   │   ├── OpenCodePluginInstaller.swift  # JS 插件安装/卸载
│   │   │   └── QoderHookInstaller.swift       # Python hook 安装/卸载
│   │   ├── NotchService.swift             # ★ 中央编排器（约 960 行）
│   │   ├── NotchSupport.swift              # 布局常量 + 几何 + 弹簧物理
│   │   ├── NotchWindowHost.swift           # 承载 SwiftUI 内容的 AppKit 视图
│   │   ├── Settings.swift                  # 持久化配置（UserDefaults + JSON 文件）
│   │   ├── SettingCatalog.swift            # 声明式设置模式定义
│   │   ├── AnswerDispatcher.swift          # 将回答写回智能体文件
│   │   ├── QuestionController.swift        # 提问卡片状态机
│   │   ├── PermissionController.swift      # 权限卡片状态机
│   │   ├── NoticeController.swift          # 通知横幅 + 铃铛摆动动画
│   │   ├── HistoryController.swift         # 最近 5 条通知
│   │   ├── Keymap.swift                    # 键盘快捷键定义
│   │   ├── Logging.swift                   # 结构化日志（文件 + stderr，5MB×3 轮转）
│   │   ├── Doctor.swift                    # 自诊断检查
│   │   ├── FeedbackService.swift           # 触觉 + 声音反馈
│   │   ├── IDELauncher.swift               # 通过 AppleEvents 激活/聚焦 IDE 窗口
│   │   └── Transcript.swift                # 从 .jsonl 文件读取会话标题
│   └── UI/                                # SwiftUI 视图（强制深色模式）
│       ├── NotchView.swift                 # 主容器：收起/展开路由
│       ├── NotchAgentQuestionView.swift    # 提问卡片 UI
│       ├── NotchPermissionView.swift       # 权限卡片 UI
│       ├── NotchNoticeView.swift           # 通知横幅 UI
│       ├── NotchHistoryView.swift          # 历史面板 UI
│       ├── SettingsView.swift              # 设置面板（可调整大小的窗口）
│       └── DoctorView.swift                # 自检（Doctor）诊断 UI
└── graphify-out/                           # 知识图谱产物（自动生成）
```

## 架构

### 库与可执行目标拆分

源码拆分为两个 SwiftPM 目标：

- **库目标 `BetterFocusIDE`**：包含除 `App/main.swift` 外的全部源码（Models / Services / UI / AppDelegate / Library.swift）。映射为 `.library` 产品类型，**支持 Xcode SwiftUI Preview**。
- **可执行目标 `BetterFocusIDEApp`**：仅编译 `App/main.swift`，依赖库目标。映射为 `.tool` 产品类型（二进制名 `BetterFocusIDEApp`）。

`Library.swift` 暴露 `public func run()`，封装原 `main.swift` 的初始化流程（日志 → 创建 AppDelegate → 进入主事件循环）。`AppDelegate` 保持 internal 访问级别，仅库内部使用。

### 四层灵动岛栈

刘海遵循从 Python 参考实现继承而来的严格分层：

1. **窗口外壳** —— `NotchPanel`（NSPanel 子类）：无边框、透明、`level = statusBar + 1`、特定的 `collectionBehavior`。必须调用 `orderFrontRegardless()` 才能真正显示（仅 `setFrame` 不够）。
2. **动画层** —— `NotchCanvas`（NSView）：承载 `CALayer` 形状关键帧动画（用 `CAKeyframeAnimation` 驱动遮罩路径，形成液态岛屿轮廓）。
3. **桥接层** —— `NotchHostingView`（NSHostingView<AnyView> 子类）：桥接 AppKit ↔ SwiftUI。
4. **内容层** —— `NotchView`（SwiftUI）：所有卡片 UI，状态由 `ObservableObject` `NotchService` 驱动。

**关键约束**：切换、自定义命中测试、逐帧弹簧动画都无法用纯 SwiftUI 完成。AppKit 薄外壳 + SwiftUI 内容是强制要求。

### 卡片状态机

四种卡片类型，各有一个专用控制器：

| 卡片类型 | 控制器 | 触发事件 | 回答机制 |
|-----------|-----------|---------------|-----------------|
| 提问 | `QuestionController` | `question_requested` | 写 JSON 到 `answers/<session>_<question>.json` |
| 权限 | `PermissionController` | `permission_requested` | 写 JSON 到 `answers/<session>_<request>.json` |
| 通知 | `NoticeController` | `turn_finished` / `session_ended` | 在 `notifyBannerDuration` 后自动消失 |
| 历史 | `HistoryController` | 内部 | 只读面板（最近 5 条） |

卡片支持**钉住模式**（保持展开）与**自动消失**（超时后收拢）。0.5 秒的点击守卫可防止卡片切换过程中误触键盘输入。

### 进程间通信

```
Qoder Hook (Python) ──┐
                      ├── Unix Socket ──→ AgentEventSocketServer ──→ NotchService
OpenCode Plugin (JS) ─┘                          │                    │
                      ←── Answer Files ←── AnswerDispatcher ←────────┘
```

- **入站**：`~/Library/Application Support/BetterFocusIDE/agent-events.sock` 上的换行分隔 JSON
- **出站**：应答文件写入 `~/Library/Application Support/BetterFocusIDE/answers/`
- **协议**：线格式见 `AgentSocketMessage` 与 `SocketEvent`

### 单实例锁

Unix socket 文件本身就是锁锚点：
1. `AgentEventSocketServer.start()` 尝试对 `<socket>.lock` 加 `flock(LOCK_EX|LOCK_NB)`
2. 用 `connect()` 探测检查是否已有另一个实例在监听
3. 返回 `StartOutcome`：`.started`、`.alreadyRunning`、`.failed`
4. 重复启动必须静默 `NSApp.terminate(nil)` —— **绝不**使用 `NSAlert().runModal()`（会阻塞主线程 → 僵尸进程）

### 设置系统

- **存储**：`~/Library/Application Support/BetterFocusIDE/settings.json`
- **实时生效**：`Settings.changes`（PassthroughSubject）→ `NotchService.handleSettingsChanged()` → 不做动画地重新布局
- **模式**：`SettingCatalog` 用 `SettingDefinition`（key、kind、group、get/set 闭包）声明式地定义所有设置
- **颜色编码**：RGB 以 `"r,g,b"` 字符串通过 `AnyCodableValue` 存储（仅支持 string/int/double/bool）
- **向后兼容**：`Settings.load()` 对缺失键使用 `??` 回退，因此新字段可与旧 JSON 共存

**关键不变量**：`handleSettingsChanged()` 绝不能写回任何 Settings 字段 —— 那会形成反馈回路。

### 安装器系统

`QoderHookInstaller` 与 `OpenCodePluginInstaller` 是**幂等的**：它们写入带 `betterfocus` 标记的文件，若内容未变则跳过。设置了 `needsReinstall: true` 的项（如 `agentWaitLimit`）会触发重新安装，但安装器必须实际读取当前的设置值，否则写回将成为空操作。

## 编码规范

### 语言与风格

- **Swift 5.9**，shell 脚本中严格使用 `set -euo pipefail`
- 所有源文件都带有 SPDX 头：`// SPDX-License-Identifier: GPL-3.0-or-later`
- 面向用户的字符串使用中文（标签、菜单项、设置分组）
- 代码注释使用中文（文档注释 `///` 与行内 `//`）；提交信息使用英文
- 遵循现有命名：窗口/几何用 `Notch*`，卡片状态用 `*Controller`，SwiftUI 视图用 `*View`

### UI 模式

- 所有 UI 均为 SwiftUI，强制深色模式
- 响应式状态用 `ObservableObject`（NotchService、Settings）
- 视图自动更新用 `@Published` 属性
- 一次性事件广播用 `PassthroughSubject`
- 设置面板使用 `SettingCatalog` 声明式模式 —— 不要硬编码 UI 行

### 动画

- 弹簧物理位于 `NotchMotion.Spring` —— 与 Python 的 `motion.spring_for` 对齐
- `CAKeyframeAnimation` 驱动遮罩路径形成液态岛屿轮廓
- `reduce_motion` 为三态：`"system"` / `"on"` / `"off"` —— 解析为 true 时强制把 bounce 设为 0，但动画仍运行（单调、不过冲）
- 帧率：`animationFps = 0` 表示自动（120Hz ProMotion）

### 错误处理

- 非关键操作（文件 I/O、JSON 解析）使用 `try?`
- 通过带主题标签的 `Log.error()` 记录错误
- 遇到畸形 socket 消息绝不崩溃 —— 静默丢弃

## 关键不变量

以下各项在所有改动中都必须保留：

1. **窗口可见性**：`present()` 只设置 frame；必须调用 `panel.orderFrontRegardless()` 才能真正显示
2. **重复启动不弹模态框**：附属应用再入必须静默（`NSLog` + `terminate`）
3. **设置反馈回路**：`handleSettingsChanged()` 对 Settings 而言是只读的
4. **Socket 锁**：`bindAndListen()` 绝不能无条件删除 socket 文件（会从运行中的实例手里抢夺）
5. **Transcript 标题**：`turn_finished` 载荷只携带 `transcript_path`（没有 `session_title`）；灵动岛自行通过 `Transcript.sessionSummary()` 读取 .jsonl
6. **点击守卫**：卡片在出现后 `clickGuard` 秒内、"其他…"文本输入期间、淡出期间、以及收拢进气泡时都忽略输入
7. **刘海屏幕锚定**：始终 targeting `safeAreaInsets.top > 0` 的显示器，绝不用 `NSScreen.main`
8. **遮罩对齐**：`Shape.path(in:)` 忽略 `rect.origin` —— 遮罩必须感知偏移，否则会偏离居中的宿主

## 数据文件

均位于 `~/Library/Application Support/BetterFocusIDE/`：

| 文件 | 用途 |
|------|---------|
| `agent-events.sock` | 智能体事件的 Unix socket |
| `agent-events.sock.lock` | 基于 flock 的单实例锁 |
| `settings.json` | 用户偏好（带版本、向后兼容） |
| `answers/*.json` | hook/插件读取的应答文件 |
| `logs/betterfocus.log` | 轮转日志（5MB × 3，已脱敏） |

外部安装的 hook/插件文件：

| 文件 | 用途 |
|------|---------|
| `~/.qoder/hooks/betterfocus-notify.sh` | Qoder hook 启动器 |
| `~/.qoder/hooks/betterfocus-hook.py` | Qoder hook 主体 |
| `~/.qoder/settings.json` | Qoder hook 注册（带 `betterfocus` 标记） |
| `~/.config/opencode/plugins/betterfocus-notify.js` | OpenCode 插件 |

## 常见任务

### 新增一个设置

1. 在 `Settings.swift` 中添加带默认值的 `@Published` 属性
2. 在 `Settings.load()` 与 `Settings.save()` 中添加读/写（用 `??` 保证向后兼容）
3. 加入 `Settings.resetAll()`
4. 在 `SettingCatalog.all` 中添加 `SettingDefinition`，设置合适的 `kind`、`group`、`section`
5. 若它需要触发 hook 重装，设置 `needsReinstall: true` 并更新 `InstallerPaths`

### 新增一种卡片类型

1. 在 `Models/` 中创建模型
2. 在 `Services/` 中创建控制器（遵循 `QuestionController` 模式）
3. 在 `NotchService` 的 `ActiveCard` 枚举中添加 case
4. 在 `UI/` 中创建 SwiftUI 视图
5. 接入 `NotchView` 路由
6. 如有需要，在 `Keymap` 中添加键盘处理

### 修改动画

1. 弹簧参数位于 `NotchMotion` —— 不要在视图里硬编码
2. 应用 bounce 前始终检查 `Settings.shared.reduceMotionResolved`
3. `NotchLayout` 常量在调用时从 `Settings.shared` 读取，以实现实时更新

### 调试

```bash
# 启用 stderr 日志
BETTERFOCUS_LOG_STDERR=1 open .build/debug/BetterFocusIDE.app

# 设置日志级别
BETTERFOCUS_LOG_LEVEL=debug BETTERFOCUS_LOG_STDERR=1 .build/debug/BetterFocusIDE

# 检查 socket
ls -la ~/Library/Application\ Support/BetterFocusIDE/agent-events.sock

# 运行自检
# 状态栏 → 自检 (Doctor)…
```

## 测试

没有自动化测试套件。手动测试流程：

1. 构建：`./build.sh`
2. 启动：`open .build/debug/BetterFocusIDE.app`
3. 触发事件：使用装有 hook 的 Qoder/OpenCode，或直接向 socket 发送 JSON
4. 验证：卡片出现、键盘快捷键、钉住/取消钉住、历史、设置改动、自检结果
5. 查看日志：`~/Library/Application Support/BetterFocusIDE/logs/betterfocus.log`


## Graphify 知识图谱（硬性规则）

本项目已有知识图谱 `graphify-out/graph.json`。回答任何代码库事实问题（某功能如何实现 / 某类被谁调用 / 数据流向 / 表结构与字段）时，**在调用任何 Grep/SearchCodebase/Read 源码之前**，按以下顺序执行：

1. **第一步必须**先用 Bash 运行：

   ```bash
   graphify query "<英文关键词，空格分隔>"
   ```

   ❌ **禁止把用户的中文提问原样作为查询词**：图谱按英文标识符索引，中文查询必返回空。即使用户用中文提问，也必须由你把问题翻译/提炼成 3-8 个英文关键词后再查询。
   示例：用户问“注册流程是怎么实现的” → `graphify query "register registration SysUser controller service password encrypt"`

2. 查询 A→B 关系用 `graphify path "A" "B"`；解释单个类/概念用 `graphify explain "Name"`。
3. 若 query 无结果：换 3-5 个英文关键词**重试一次**；仍无结果才允许 Grep/Read 源码。
4. graphify 返回的 `source_location` 是精确坐标，用它直接 Read 对应文件，不要全局 grep。
5. **修改代码后**运行 `graphify update .`（纯 AST，无 token 成本）保持图谱最新。
6. **例外**（不适用本规则）：用户明确说明不使用 graphify；查询/维护 graphify-out 产物本身（构建、更新、验证产物文件）；阅读 `GRAPH_REPORT.md` 做整体架构审查（仅当 query/path/explain 无法提供足够上下文时）。
7. `graphify-out/` 下文件出现脏状态是 hooks/增量更新后的**预期行为**，不是跳过 graphify 的理由；`graphify-out/wiki/index.md` 可作为 query 之后的导航辅助，但不能替代第 1 步的 query 调用。
8. **适用范围包含工作流与技能**：执行 `/wf-feature-large`、`/wf-feature-small`、`/wf-bug-fix` 或任何 `ss-*` 技能时，各阶段中"摸清现状"（现有实现/类调用关系/表结构/字段归属）同样属于本规则约束的代码库事实查询。**不得**以"本阶段是产出文档、不是在回答提问"为由跳过。阶段划分与门禁见 `.qoder/wf-rules/orchestrator-behavior.md` → 「代码图谱优先协议（graphify-first）」。
9. **取证必须留痕（否则视为未取证）**：在上述阶段中，本阶段主产物（`02-intake.md` / `03-spec.md` / `04-domain.md` / `05-design.md` / `06-tasks.md` / `rootcause.md` 等）必须包含 `## 图谱证据` 段，记录：执行的 `graphify` 命令原文、每条命令得到的关键结论（含 `source_location`）、以及不得早于两次 graphify 重试失败前使用 Grep/Read 源码的兜底原因。**禁止仅在对话中口头声称已使用 graphify**：客观验证通道是 `graphify-out/cache/last_query_stamp`（`query`/`path`/`explain` 均会刷新，仅写入该文件的声称无效）。
