# AGENTS.md — BetterFocusIDE

## 项目概述

BetterFocusIDE 是一款 macOS 15+ 的附属应用（accessory app，LSUIElement，无 Dock 图标），把 MacBook 的刘海变成面向 AI 编码智能体的"灵动岛"通知助手。它通过 Unix 域套接字接收来自 **Qoder**（Python hook）、**OpenCode**（JavaScript 插件）、**Cursor**（`~/.cursor/hooks.json`）和 **WorkBuddy**（`~/.workbuddy/settings.json`）的事件，在刘海区域展示可交互卡片（提问、权限请求、回合完成通知），并把用户的回答回传给发起请求的智能体。

- **许可证**：GPL-3.0-or-later
- **来源**：由 Python 项目 `dynamic-Island-python-validate` 迁移为 Swift（动画 / UI 参考 Vorssaint 的实现）
- **运行要求**：macOS 15+，Apple Silicon（`arm64`）。同一只发行包在 macOS 26 及以上用液态玻璃，在 macOS 15 用卡片磨砂。
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

**改完代码必须重新编译并重启。** 源码、资源、脚本模板或构建脚本有变更时，先 `./build.sh`，再 `pkill -f BetterFocusIDEApp; sleep 1; open .build/debug/BetterFocusIDE.app`。只改文档不必重启。编译失败先修好，不要启动旧包。旧实例占着 socket 时，直接 `open` 会静默退出，看起来像改动没生效。

## 打包 DMG

发行物是 `dist/BetterFocusIDE-<版本>.dmg`（当前 `dist/BetterFocusIDE-0.1.0.dmg`）。先 `./build.sh`，再拿 `.build/debug/BetterFocusIDE.app` 打可写镜像，最后压成 UDZO。包内是这个 app，外加一个指向 `/Applications` 的符号链接。`LSMinimumSystemVersion` 与二进制 `minos` 都是 15.0。液态玻璃符号（`NSGlassEffectView`、`glassEffect`）必须是弱链接，macOS 15 上找不到它们时走磨砂，不能因此拒绝启动。

打包时按这个顺序，少一步图标就会丢：

1. 若 `/Volumes/BetterFocusIDE` 已经挂着，先推出。挂载必须指定独立的 `-mountpoint`。机器上常有别的镜像，按 `diskN` 卸盘会卸错，写进去的图标也不会进最终文件。
2. `hdiutil create -format UDRW`，卷名 `BetterFocusIDE`。拷入已通过 `codesign --verify --deep --strict` 的 app，并放上 `/Applications` 符号链接。
3. 卷图标：把 `Resources/AppIcon-NotchCard.icns` 拷成挂载点上的 `.VolumeIcon.icns`，`SetFile -a V` 把它藏起来，`SetFile -a C` 给卷打上自定义图标。只写 `com.apple.FinderInfo` 这个 xattr，推出后会丢。推出后要只读再挂一次，确认 `.VolumeIcon.icns` 还在，再 `hdiutil convert -format UDZO`。
4. 文件图标：`convert` 会换成一个新的 dmg 文件，之前贴在文件上的图标一起没了。转换完成后再用 `NSWorkspace.shared.setIcon` 把同一枚 icns 贴到 dmg 上（Finder 自定义图标位 + ResourceFork）。访达若仍显示旧的白磁盘，离开该文件夹再进去。

打开 dmg 时，系统会尝试把里面唯一的 app 自动装进「应用程序」。本包是 ad-hoc 签名、没有公证，自动安装会失败，正文是「没有更改任何内容。你仍可将 App 拖到“应用程序”中。」镜像本身是好的，把 `BetterFocusIDE.app` 拖到窗口里的「应用程序」即可。Developer ID 签名并公证之后，这条自动安装才会走通。

签名必须是不带加固运行时的 ad-hoc（`codesign --sign -`，先资源包再外层，不用 `--deep`）。不要加 `--options runtime`，也不要把 `com.apple.security.automation.apple-events` 签进包里。加固运行时加上这项受限权利后，签名只在编译这台 Mac 上有效。别人那边安装能成功，一点开就是「应用程序无法打开」，右键打开也绕不过。改掉之后重新发 `dist/BetterFocusIDE-0.1.0.dmg`，不要把旧包再传一次。不加固运行时，自动化授权仍会弹出，Apple Events 可以继续用。

发给别人之后还有两句系统文案，不要混成同一件事：

- 「应用程序无法打开」：包还是带加固运行时的那一只。换新包。
- 「无法验证开发者」：签名已经能带走，但没有公证。在「应用程序」里右键该 app，选「打开」。

这只包只有 `arm64`。Intel 的 Mac 即使用新包、清掉隔离属性，也打不开。

## 目录结构

```
├── README.md                              # 用户文档（中文）；与 README.en.md 必须同步
├── README.en.md                           # 用户文档（英文）；与 README.md 必须同步
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
│   │   ├── AgentProvider.swift            # 四个宿主的身份 + 主题色 + 跳转分组
│   │   ├── AgentQuestion.swift            # 提问卡片模型（多选、选项）
│   │   ├── AgentSocketMessage.swift       # 线协议：Unix socket 上的 JSON
│   │   ├── HistoryEntry.swift             # 通知历史记录
│   │   ├── PermissionRequest.swift        # 权限卡片模型（允许/总是/拒绝）
│   │   └── TurnNotice.swift               # 回合完成通知 + transcript 解析
│   ├── Services/
│   │   ├── Socket/
│   │   │   └── AgentEventSocketServer.swift   # Unix socket 监听器（DispatchSourceRead）
│   │   ├── Installer/
│   │   │   ├── HelperTemplate.swift           # 内嵌的 Qoder Python hook 模板
│   │   │   ├── HostHookTemplate.swift         # Cursor / WorkBuddy 共用 hook 正文 + 文件/JSON 工具
│   │   │   ├── InstallerPaths.swift           # hook/插件安装所用的文件路径
│   │   │   ├── CursorHookInstaller.swift      # Cursor hooks.json 安装/卸载（观测型）
│   │   │   ├── OpenCodePluginInstaller.swift  # JS 插件安装/卸载
│   │   │   ├── QoderHookInstaller.swift       # Python hook 安装/卸载
│   │   │   └── WorkBuddyHookInstaller.swift   # WorkBuddy settings.json hooks 安装/卸载
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

**层级职责（2026-11 重构后）**：轮廓遮罩已从 canvas 根层下沉到 `body`（`PassthroughView`）——黑底、磨砂 glass、暗层 dim、SwiftUI host、发丝描边 edge 全部在 body 内，被 `silhouette` mask 裁剪；canvas 根层保持透明且**不带**轮廓 mask，辉光层（`glowLayer`）直接挂在根层以绕过裁剪。两条隐式不变量：
- `body`（`PassthroughView`）必须 `isFlipped = true`，与 `NotchCanvas` 翻转坐标系一致，否则 body 内所有层被垂直翻转（黑色气泡跑到屏幕下方、肩部朝向反了），而挂在 canvas 层的辉光位置正常——两层错位。
- `PassthroughView.hitTest` 必须让落在自身范围内的点返回 `nil`，否则 body 会拦截画布自身的 hover/右键鼠标事件链路。
- 越界特效（辉光/投影）**不能**靠 `zPosition` 或兄弟视图逃逸父层 mask——mask 裁剪作用于整棵子树，唯一出路是把特效移到不含该 mask 的祖先层。`NSPanel` 本身无 `.layer`，只有 `contentView?.layer`。

### 卡片状态机

四种卡片类型，各有一个专用控制器：

| 卡片类型 | 控制器 | 触发事件 | 回答机制 |
|-----------|-----------|---------------|-----------------|
| 提问 | `QuestionController` | `question_requested` | 写 JSON 到 `answers/<session>_<question>.json` |
| 权限 | `PermissionController` | `permission_requested` | 写 JSON 到 `answers/<session>_<request>.json` |
| 通知 | `NoticeController` | `turn_finished` / `session_ended` | 在 `notifyBannerDuration` 后自动消失 |
| 历史 | `HistoryController` | 内部 | 只读面板（最近 5 条） |

卡片支持**钉住模式**（保持展开）与**自动消失**（超时后收拢）。0.5 秒的点击守卫可防止卡片切换过程中误触键盘输入。

### 辉光渲染

外发光（呼吸辉光）采用**单层 CALayer + CPU 预渲染位图**方案：
- `glowLayer.contents` 是一张 `CGContext` + `CIFilter(CIGaussianBlur)` 预渲染的 `CGImage`：源形状先向外膨胀 `inflate ≈ range × 0.5`，再以 `σ = range × 0.5` 模糊。
- 该层插在 `body` 之下（canvas 根层 `at: 0`），内部被不透明的岛面盖住，只露出向外扩散的渐变光晕——因此**不需要**额外遮罩挖洞。
- 窗口 `shadowPad` 必须跟随辉光范围动态扩大（`max(原下限, glowRadius × 扩散系数 + 安全余量)`），否则扩散会被窗口边缘裁平。

**已证伪的方案**（不要再尝试）：
- `CAShapeLayer.shadow`（`shadowRadius`/`shadowOpacity`）：在透明无边框 NSPanel 中只渲染出一圈紧贴轮廓的硬描边，`radius` 从 9 调到 40 视觉几乎无变化。
- `CALayer.filters` 挂 `CIGaussianBlur`：对 `CAShapeLayer` 的矢量绘制内容整层不输出（截图只见纯黑气泡、完全无光晕）。
- 多层同心描边（宽度递增、alpha 递减）：相邻层肉眼可见分层台阶。
- `panel.hasShadow = true`：系统按整窗 alpha 生成投影，会把半透明辉光自身压暗并在衰减末段造出假性"分层线"——必须 `hasShadow = false`，主体投影改由 `body.layer.shadow*` 自绘。

**浓度调节**：浓度必须做进模糊之前的源形状（膨胀宽度），而非模糊后的像素。对预乘位图做通道增益（`CIColorMatrix` 四通道同乘）或多次叠印会导致 RGB 钳到 255 变白雾 + 放大量化台阶产生等高线带状条纹。

### 呼吸动画

呼吸灯（辉光 opacity 循环）的三条不变量：

1. **时间域**：用 `CAKeyframeAnimation` + `calculationMode = .cubic`，关键帧按余弦采样、`duration` 等于完整周期（不再除 2），首尾同值使接缝值与斜率连续。**禁用** `easeInEaseOut` + `autoreverses`——两端各产生约 0.3s 零速度驻留平台，变化被挤进中段。
2. **感知域**：在 CIE L* 感知空间做余弦插值，再用 sRGB 反变换解出每帧 opacity。直接对物理量 opacity 做线性余弦会让约 72% 周期停在 `L* > 85` 的近不可见区。
3. **空间域**：膨胀系数 `inflate = range × 0.5`、模糊 `σ = range × 0.5`（峰值梯度 0.017/pt），使衰减带变宽、台阶不可见。默认值：`glowRadius = 6pt`、`glowBreathAmplitude = 0.65`。

**画布锚点不对称性**：`panelFrame` 高度 = `base.height + shadowPad`（留白仅加在底部），宽度 = `base.width + shadowPad × 2`（两侧对称）。`glowLayer` 默认 `anchorPoint(0.5, 0.5)` 的几何中心位于岛视觉中心正下方约 `shadowPad/2`。对 `glowLayer` 施加 `transform.scale` 时，两侧（距锚点 ≈ 104pt）的径向位移远大于底部（距锚点 ≈ 7–13pt），表现为"两侧鼓动明显而下方几乎不动"。结论：辉光呼吸应只用 opacity 动画（各向同性）。

### 刘海尺寸检测与自适应布局

物理刘海尺寸的公开 API（macOS 12+，项目 target 14+ 无需可用性守卫）：
- **刘海高度** = `NSScreen.safeAreaInsets.top`（14" MBP 实测 32pt）
- **刘海宽度** = `screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`（两属性返回摄像头左右两侧「顶部辅助安全区」`NSRect?`，需解包判 `isEmpty`；14" MBP 实测 185pt）
- 无刘海屏（外接显示器）`safeAreaTop = 0`、辅助区为 `nil`，回退手动值
- 注意：`NSScreen.auxiliaryAreas` / `cameraHousing` 这类 API **不存在**，不要臆造

实现落点（单一源，避免逻辑漂移）：
- `NotchLayout.physicalNotchWidth(of:)` 是刘海宽检测的唯一 helper；`NotchService.detectCameraWidth` 委托它
- **气泡肩部补偿**：`bubbleBase` 跟随模式 `width = cameraWidth + 2 × shoulder(cameraHeight)`，使渲染主体恰好与刘海齐平（不补偿则主体缩在刘海内，左右辉光被挤在刘海硬件上看不见）；高度不补偿
- **卡片黄金分割**：`resolvedCardWidth = notch × goldenSectionMultiplier ÷ goldenSectionDivisor`（当前 1.5:0.618 ≈ 449pt，机型自适应）。用户口中的「X 倍」沿用 `X:0.618` 公式（即 `×X÷0.618`），不是单纯 `×X`
- 两个跟随开关 `bubbleFollowsNotch` / `cardFollowsNotch` 默认开启，开启时对应的手动滑块经 `enabledBy`/`enabledWhen` 置灰

### Product 来源识别

消息来源标识（`product`）由 hook 侧 `_identify_product()` 依据环境变量决策树推导，而非从事件 JSON 或 transcript 中提取：

| 优先级 | 条件 | 结果 |
|--------|------|------|
| 1 | `QODER_PROJECT_DIR` 存在且无 `QODER_SESSION_ID` | `qoder_cli` |
| 2a | 有 `QODER_SESSION_ID` + `QODER_STANDALONE=1` | `qoder` |
| 2b | Bundle ID 含 `jetbrains`/`intellij` | `jetbrains_plugin` |
| 2c | Bundle ID 含 `qoder` | `qoder_ide` |
| 2d | Bundle 缺失但有 `QODER_TRANSCRIPT_PATH` | `qoder_ide`（兜底） |
| 3 | 均不满足 | `unknown` |

- **状态持久化**：`SessionStart` 时识别结果写入会话 state 落盘；后续事件优先读 state，state 缺失才降级重新识别
- **竞态处理**：`_merge_state()` 处理 IDE 双 `SessionStart` 同毫秒到达——新值为空或 `unknown` 时保留磁盘已有值
- **修改来源识别逻辑须同步核对**：`HelperTemplate.swift`（hook 模板）与 `~/.qoder/hooks/betterfocus-hook.py`（已安装 hook）两处
- Swift 侧 `AgentSocketMessage.resolvedProvider` 优先取 `product`、缺失才回退 `provider`
- **国内版**：`BETTERFOCUS_VARIANT=cn` 把 `jetbrains_plugin` 换成 `jetbrains_cn_plugin`。英文版插件和国内版插件可以同时装在同一个 JetBrains IDE 里，两边各有自己的语言服务，不能共用一个 product

### 宿主接入矩阵

四个宿主的 hook 都是「stdin 收 JSON、stdout 回 JSON」的 command hook，差异只在事件方言与可用事件面：

| 宿主 | 配置文件 | 事件方言 | 注册的事件 | 能力 |
|------|----------|----------|------------|------|
| **Qoder** | `~/.qoder/settings.json` | PascalCase | `PermissionRequest` / `PreToolUse` / `Stop` / `SessionEnd` | 提问卡、权限提醒、回合完成、会话结束 |
| **OpenCode** | `~/.config/opencode/plugins/` | JS 事件流 | `session.execution.succeeded`、`message.part.updated`；v1 另有 `tool.execute.after` | 提问卡、回合完成、待办（v2 要 `experimental.todo`）。无权限、无会话结束 |
| **Cursor** | `~/.cursor/hooks.json` | camelCase | `beforeSubmitPrompt` / `stop` / `sessionEnd` / `subagentStop` / `preCompact` | 回合完成、会话结束，以及子任务 / 即将压缩（观测型，无权限卡） |
| **WorkBuddy** | `~/.workbuddy/settings.json` 的 `hooks` | PascalCase | `PreToolUse` / `Notification` / `PermissionRequest` / `Stop` / `SessionEnd` | 提问卡、权限提醒、回合完成、会话结束 |

**Cursor 为什么只做观测**：Cursor 没有 `Notification` 事件。`beforeShellExecution` / `beforeMCPExecution` / `preToolUse` / `beforeReadFile` 必须回 `permission`。`ask` 会盖过 Auto-review 并显示 Hook requested approval，`allow` 直接放行，`deny` 拦住，空对象会挡住调用。因此这些事件都不注册，岛上没有 Cursor 权限卡。观测事件是：`beforeSubmitPrompt`（回 `{"continue":true}`）、`stop` / `sessionEnd` / `subagentStop` / `preCompact`（恒回 `{}`）。工具调用失败不通知。

**WorkBuddy 的事件选择**：
- 提问走 `PreToolUse` + matcher `AskUserQuestion`，用 `hookSpecificOutput.permissionDecision = "deny"` 拦掉宿主原生提问框，并把岛上答案写进 `permissionDecisionReason` 回灌给 Agent（与 Qoder hook 同一手法）。
- 权限提醒同时挂 `Notification`（matcher `permission_prompt`，官方文档入口）与 `PermissionRequest`（27+ 事件族，带 `tool_name` / `tool_input`）。两条都只发 `permission_notice`、**stdout 保持静默**，审批仍由宿主原生对话框完成；重复横幅由 `NoticeController.handlePermissionNotice` 的去抖吸收。
- `Stop` / `SessionEnd` 不使用 matcher，安装器直接省略该字段。

**WorkBuddy 不热加载**：官方文档明确 settings.json 的 hook 改动不会热生效（CLI 会提示在 `/hooks` 面板复核）。安装/卸载后需要重启对应会话，或到 `/hooks` 确认注册。

**共用模板**：`HostHookTemplate.body` 一份 Python 正文，安装时按 `__EVENT_STYLE__`（`cursor` / `claude`）与 `__PROVIDER__` 分流；`HookInstallerSupport` 提供幂等写文件、原子写 JSON、权限位保留与"只删自己条目"的识别逻辑。

### 进程间通信

```
Qoder Hook (Python) ─────┐
OpenCode Plugin (JS) ────┤
Cursor Hook (Python) ────┼── Unix Socket ──→ AgentEventSocketServer ──→ NotchService
WorkBuddy Hook (Python) ─┘                          │                    │
                      ←── Answer Files ←── AnswerDispatcher ←────────────┘
```

- **入站**：`~/Library/Application Support/BetterFocusIDE/agent-events.sock` 上的换行分隔 JSON
- **出站**：应答文件写入 `~/Library/Application Support/BetterFocusIDE/answers/`
- **协议**：线格式见 `AgentSocketMessage` 与 `SocketEvent`

### Socket 注入测试

无需真实 IDE 插件，可直接用脚本向 socket 注入测试事件：

```bash
SOCKET=~/Library/Application\ Support/BetterFocusIDE/agent-events.sock

# 最小可用报文（无需 transcript 文件也能产出完整历史行）
echo '{"provider":"qoder","event":"turn_finished","session_id":"test-'$(date +%s)'","payload":{"cwd":"/tmp"},"host":{"name":"Qoder","bundle_id":"com.qoder.ide"}}' | nc -U "$SOCKET"
```

**关键注意事项**：
- **连接保持**：`nc` 默认等待对端关闭（不会过早 RST），可直接用。若用 Python `socket.sendall()` 后必须 `sleep ≥ 1.5s` 再 `close()`，否则服务器在 backlog 中的连接被内核 abort，收不到任何数据且日志无记录（静默丢失）。
- **换行分帧**：`AgentEventSocketServer` 按"一行一个 JSON + `\n`"分帧。`echo ... | nc` 末尾自带换行所以可用；若用 Python 须显式 `sendall((msg + '\n').encode())`。
- **核对点**：`betterfocus.log` 出现 `socket: event=turn_finished provider=qoder session=...` 即代表事件已被接收并入历史。
- **Product 字段**：手工注入报文若要验证来源展示，须显式带上 `product` 字段（如 `"product":"jetbrains_plugin"`），否则仍走旧的 `provider` 回退路径。
- **OpenCode 插件热重载陷阱**：OpenCode 的文件 watcher 在插件文件变化时重新执行 `setup`，而上一次 `setup` 的 `for await (const event of ctx.event.subscribe(...))` 循环未被取消，导致多个循环同时消费同一事件流——一次回合结束在日志出现 3 条完全相同的 `turn_finished`。正确做法：每次 `setup` 开头 `abort` 上一实例遗留的 controller。

### IDE 跳转与二级定位

用户点击通知横幅时，`IDELauncher` 负责激活产生该通知的 IDE 窗口。系统支持**二级定位**：不仅激活 IDE 应用，还能精确聚焦到具体项目窗口。

#### Hook 上报的 Host 字段

每条 socket 消息应携带以下宿主信息以支持二级定位：

| 字段 | 位置 | 类型 | 说明 | 示例 |
|------|------|------|------|------|
| `host.bundle` | `host` 对象 | string | 宿主应用 Bundle ID | `com.jetbrains.intellij` |
| `host.name` | `host` 对象 | string | 宿主应用名称 | `IntelliJ IDEA` |
| `host.path` | `host` 对象 | string | 宿主 `.app` 包路径 | `/Applications/IntelliJ IDEA.app` |
| `cwd` | 消息顶层 | string | **项目工作目录（二级定位关键）** | `/Users/dev/my-project` |

> **注意**：`cwd` 必须在消息顶层，不在 `host` 对象内。所有事件类型（`question_requested`、`permission_notice`、`turn_finished`）都应携带。

#### 二级定位策略

| IDE 类型 | 定位方式 | 回退链 |
|----------|----------|--------|
| **JetBrains** | ① CLI 直达 → ② AXRaise → ③ Window 菜单 | ① `<binary> <cwd>` 让 IDE 自聚焦 → ② System Events `AXRaise` 按窗口标题匹配 → ③ 点击 Window 菜单项（跨 Space 可靠，有闪烁） |
| **Qoder IDE / CN IDE / Cursor** | `code -r <cwd>` + IPC socket | VS Code 系 fork，通过 `VSCODE_IPC_HOOK_CLI` 环境变量指向运行中实例的 IPC socket（`*-main.sock`），复用已打开的 workspace 窗口 |
| **Qoder.app** | App 级激活 | 独立桌面应用，无 `code` 二进制，直接激活应用 |
| **OpenCode / WorkBuddy** | App 级激活 | 按 bundle id 或应用名激活 |

**关键实现细节**：
- **IPC socket 查找**：`findCodeIPCSocket()` 通过 bundle ID 映射到数据目录名（如 `com.qoder.ide` → `Qoder`，`com.aliyun.lingma.ide` → `QoderCN`，`com.todesktop.230313mzl4w4u92` → `Cursor`），在 `~/Library/Application Support/<dir>/` 下查找 `*-main.sock` 文件
- **环境变量设置**：调用 `code -r` 前必须设置 `VSCODE_IPC_HOOK_CLI` 指向找到的 socket 路径，否则 CLI 无法连接运行中实例而会打开新窗口
- **应用名 ≠ 数据目录名**：Qoder IDE.app 的数据目录是 `Qoder`（不是 `Qoder IDE`），因此不能从应用名直接推导
- **provider 兜底反查**：hook 只上报 `host.bundle` 时（老 hook / 第三方脚本），`target(for:host:)` 会用 bundle 反查 `ideBundles` 分组，确保 Cursor / WorkBuddy 的通知也能跳回自己的窗口

#### 支持的应用 Bundle ID 对照表

| 应用 | Bundle ID | 二级定位支持 | 说明 |
|------|-----------|--------------|------|
| **Qoder.app** | `com.qoder.app` | ❌ | 独立桌面应用（类 Electron），无 `code` 二进制 |
| **Qoder IDE.app** | `com.qoder.ide` | ✅ `code -r` | VS Code 系 IDE 英文版 |
| **Qoder CN IDE.app** | `com.aliyun.lingma.ide` | ✅ `code -r` | VS Code 系 IDE 中文版 |
| **IntelliJ IDEA** | `com.jetbrains.intellij` | ✅ CLI/AXRaise/Menu | JetBrains IDE |
| **PyCharm** | `com.jetbrains.pycharm` | ✅ CLI/AXRaise/Menu | JetBrains IDE |
| **GoLand** | `com.jetbrains.goland` | ✅ CLI/AXRaise/Menu | JetBrains IDE |
| **其他 JetBrains** | `com.jetbrains.*` | ✅ CLI/AXRaise/Menu | 所有 JetBrains IDE 均支持 |
| **Cursor.app** | `com.todesktop.230313mzl4w4u92` | ✅ `code -r` | ToDesktop 打包的实际 bundle id；`com.cursor` 为兜底 |
| **OpenCode** | `ai.opencode.desktop` | ❌ | 仅 App 级激活 |
| **WorkBuddy** | `com.tencent.workbuddy.mac` | ❌ | Electron 桌面应用，仅 App 级激活（`ai.workbuddy` 兜底） |
| **终端** | `com.apple.Terminal` 等 | ⛔ 不可跳转 | CLI 模式无 GUI 窗口 |

#### 关键实现文件

- `IDELauncher.swift`：跳转逻辑主入口，包含 `activate(provider:host:)` 和各定位方法
- `HelperTemplate.swift` / `HostHookTemplate.swift`：Python hook 模板，`host_app()` 沿父进程链识别宿主应用
- `AgentSocketMessage.swift`：消息模型，解析顶层 `cwd` 字段
- `HostInfo`：宿主信息结构体，承载 `bundle`/`name`/`path`/`cwd`

### 单实例锁

Unix socket 文件本身就是锁锚点：
1. `AgentEventSocketServer.start()` 尝试对 `<socket>.lock` 加 `flock(LOCK_EX|LOCK_NB)`
2. 用 `connect()` 探测检查是否已有另一个实例在监听
3. 返回 `StartOutcome`：`.started`、`.alreadyRunning`、`.failed`
4. 重复启动必须静默 `NSApp.terminate(nil)` —— **绝不**使用 `NSAlert().runModal()`（会阻塞主线程 → 僵尸进程）
5. `bindAndListen()` 绝不能无条件删除 socket 文件（会从运行中的实例手里抢夺 socket 变幽灵）

**重启陷阱**：`.build/debug` 是指向 `arm64-apple-macosx/debug` 的符号链接，旧实例存活时新进程发现 socket 被占用会静默 terminate，反复 `open` 看似"改动没生效"。正确重启：`pkill -f BetterFocusIDEApp; sleep 1; open .build/debug/BetterFocusIDE.app`

### 设置系统

- **存储**：`~/Library/Application Support/BetterFocusIDE/settings.json`
- **实时生效**：`Settings.changes`（PassthroughSubject）→ `NotchService.handleSettingsChanged()` → 不做动画地重新布局
- **模式**：`SettingCatalog` 用 `SettingDefinition`（key、kind、group、get/set 闭包）声明式地定义所有设置
- **颜色编码**：RGB 以 `"r,g,b"` 字符串通过 `AnyCodableValue` 存储（仅支持 string/int/double/bool）
- **向后兼容**：`Settings.load()` 对缺失键使用 `??` 回退，因此新字段可与旧 JSON 共存

**关键不变量**：`handleSettingsChanged()` 绝不能写回任何 Settings 字段 —— 那会形成反馈回路。

**新增/修改设置项默认值的 4 处同步落点**（缺一即出现"初始值/恢复默认/面板回退值"不一致）：
1. `Settings.swift` 的 `@Published` 属性初值
2. `Settings.swift` 的 `resetAll()`
3. `SettingCatalog.swift` 对应 `SettingDefinition` 的 `defaultValue`
4. `SettingCatalog.swift` 对应 `SettingDefinition` 的 `defaultValue`（滑块以 UI 单位表达时需折算）

**`SettingDefinition` 参数顺序约束**：`enabledBy` / `enabledWhen`（联动置灰条件）必须排在 `keywords` 之前，否则 `swiftc` 报「argument 'enabledBy' must precede argument 'keywords'」而整个 `SettingCatalog` 编译失败。

**`needsReinstall` 项的生效前提**：`QoderHookInstaller`/`OpenCodePluginInstaller` 是幂等的（内容相同即跳过写入），因此 `InstallerPaths.hookTimeoutSeconds` 等必须实际读取 `Settings.agentWaitLimit`（+ 60s hook 余量），OpenCode 插件模板 `ANSWER_TIMEOUT_MS` 必须以占位符注入；若仍硬编码旧值，则改 `agentWaitLimit` 触发的 `install()` 写回将是空操作。

**持久化边界**：全部设置项落盘于 `settings.json`，重装 app（删除 `.app` bundle 或重新 `build.sh`）不会重置任何参数；仅手动删该文件或在 app 内"恢复默认"(`resetAll`) 才会重置。改代码默认值不会影响已保存 `settings.json` 的用户实值，验证前必须先读 `settings.json` 取实际值。

**置顶状态（pinned）链路**：提问、权限、通知、待办、历史共用 `Settings.pinByDefault` 这一份值。卡片图钉通过 `togglePin()` 写回这项设置并落盘；`refreshPinned()` 只读它，接入点为 `showHistory`/`showNoticeBanner`/`showCard`/`revealTodoCard`/`handleSettingsChanged`。换卡片和重新打开都保持上次的选择，不再在进程内另记一份、重启后回落代码默认值。`handleSettingsChanged()` 对这项设置仍然只读。

### 安装器系统

四个安装器（`QoderHookInstaller` / `OpenCodePluginInstaller` / `CursorHookInstaller` / `WorkBuddyHookInstaller`）都是**幂等的**：写入带 `betterfocus` 标识的文件，内容未变则跳过。设置了 `needsReinstall: true` 的项（如 `agentWaitLimit`）会触发重新安装，但安装器必须实际读取当前的设置值，否则写回将成为空操作。

改宿主配置时的不变量：
- **只增删自己的条目**。Qoder 靠分组里的 `_betterfocus_marker` 识别；WorkBuddy 直接靠 `command` 是否指向 `betterfocus-notify.sh`（不写自定义字段，避免宿主 schema 拒绝）；Cursor 同样靠 `command`。删除时**扫描全部事件**，避免升级后旧事件残留。
- **保留其他键与权限位**。`HookInstallerSupport.writeJSON` 原子写回并 `chmod` 回原权限（WorkBuddy 的 `settings.json` 通常为 0600，不能放宽成 0644）。
- **不产生副作用输出**。Shell 启动器在 `python3` 缺失时直接 `exit 0`；WorkBuddy 侧 stdout 静默 = 「无决策」，Cursor 侧恒回 `{}`。

## 编码规范

### 模型回复

回复用户时按这个顺序，三段都要有：

1. **结论**：先说清楚结果或判断。
2. **原因**：接着说明为什么是这个结论。
3. **下一步**：最后给出推荐的下一步。

### 语言与风格

- **Swift 5.9**，shell 脚本中严格使用 `set -euo pipefail`
- 所有源文件都带有 SPDX 头：`// SPDX-License-Identifier: GPL-3.0-or-later`
- 面向用户的字符串使用中文（标签、菜单项、设置分组）
- 代码注释使用中文（文档注释 `///` 与行内 `//`）；提交信息使用英文
- 遵循现有命名：窗口/几何用 `Notch*`，卡片状态用 `*Controller`，SwiftUI 视图用 `*View`

### README 多语言同步

仓库根目录的用户文档按语言拆分，事实与结构必须一致：

| 文件 | 语言 |
|---|---|
| `README.md` | 中文（默认，GitHub 首页） |
| `README.en.md` | 英文 |

改 README 时——功能说明、宿主能力表、截图与图注、安装步骤、快捷键、架构描述，以及新增、删除或调整章节——必须在同一次改动里更新全部分语言文件，并保持文首的语言切换链接可到达每一份。只润色某一种语言的用词、不改变事实时，可以只改那一份。

新增语言沿用 `README.<lang>.md`（例如 `README.ja.md`），在每一份文首补上切换链接，并把新文件加进上表。`AGENTS.md` 面向贡献者，保持中文，不随 README 翻译。

### 功能经验沉淀

新功能的实现思路定下来并落地后，同一次改动里把经验写进 `knowledge/`。写清最终行为、关键路径、实测过的接口和取值、否决过的做法、代码落点。同一主题已有文档时更新那一份；旧方案被取代时在文首标明，不要让旧计划继续被当成现行做法。

目录按主题放在 `knowledge/technologies/active/sprint2611/<主题>/`，经验文用 `NN-开发经验.md` 或 `NN-适配经验.md`。只润色用词、不改变事实时不必另开一篇。用户文档仍走上面的 README 多语言同步，knowledge 不代替用户手册。

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
9. **body 坐标系**：`PassthroughView`（body 容器）必须 `isFlipped = true` 与 `NotchCanvas` 一致，否则 body 内 silhouette/host 被垂直翻转，黑色气泡跑到屏幕下方而辉光位置正常——两层错位
10. **辉光层归属**：辉光层必须挂在**不带轮廓 mask 的祖先层**（canvas 根层），不能靠 `zPosition` 或兄弟视图逃逸 body 的 mask 裁剪
11. **CLI 会话判据**：`Transcript.Session.fromCLI = (entrypoint == "cli") && !hasHumanInput`，其中 `hasHumanInput` 取首条 user 记录的 `humanInput` 字段。单纯 `entrypoint == "cli"` 会误伤 GUI 会话（新版 Qoder 内核把 GUI transcript 也写入 `.jsonl` 并统一标 `entrypoint: "cli"`）
12. **卡片视觉一致性**：四类卡片的图钉 (`pin.fill`) 颜色统一取 `Settings.shared.accentRGB`（主题色），不再使用 `AgentProvider.tint`；`provider.tint` 仍用于徽章/来源标识等强调色

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
| `~/.cursor/hooks/betterfocus-notify.sh` | Cursor hook 启动器 |
| `~/.cursor/hooks/betterfocus-hook.py` | Cursor hook 主体（观测型） |
| `~/.cursor/hooks.json` | Cursor hook 注册（`version` + `hooks`，保留其他条目） |
| `~/.workbuddy/hooks/betterfocus-notify.sh` | WorkBuddy hook 启动器 |
| `~/.workbuddy/hooks/betterfocus-hook.py` | WorkBuddy hook 主体 |
| `~/.workbuddy/settings.json` | WorkBuddy hook 注册（只动 `hooks`，其余设置原样保留） |

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

**环境变量生效的正确方式**：需要让 `BETTERFOCUS_*` 等调试环境变量生效时**不能用 `open`**——`open` 由 `launchd` 派生进程，shell 前缀的环境变量不会传进 app。必须直接执行二进制：
```bash
BETTERFOCUS_LOG_STDERR=1 BETTERFOCUS_LOG_LEVEL=debug \
  .build/debug/BetterFocusIDE.app/Contents/MacOS/BetterFocusIDE
```

**干净重建**：只 `rm -rf .build/debug` 后 `swift build` 可能在 0.25s 内报 "Build complete" 而并未真正重编。确证干净重建应删除整个 `.build` 目录（全量重建约 60s）。

**双屏截图坐标**：开发机为双屏时（外接 + 内置刘海），`screencapture -R x,y,w,h` 的坐标是全局点坐标（原点在左上角、y 向下），内置屏顶部在主屏底部之下，灵动岛区域约在 `y ≈ 1150~1250`。**每次取证前必须先枚举 `NSScreen.screens` 打印 frame/safeAreaInsets 重新确定截图区域**——外接屏断开后坐标完全不同。配合 `CGWindowListCopyWindowInfo` 可先确认窗口是否真的在屏。

**裁切排查方法论**：内容"疑似被边缘裁切"时，**不可靠**的方式是 `screencapture` + PIL 放大裁剪后肉眼估像素（深色卡片叠在深色桌面上无法区分边界）。正确的取证顺序：
1. 先加临时日志打印 `target` / `host.frame` / `mask.bounds`（silhouette box）三者真实尺寸与 origin
2. 尺寸相同仍被裁时，把对比维度从 width/height 扩展到 **origin**（mask 路径 `boundingBoxOfPath.origin` 与 `host.frame.origin` 必须相等）
3. origin 已对齐仍显示不全，才查行内布局（greedy title 与 fixed meta 在 HStack 争抢空间的压缩歧义）
4. 验证通过后移除临时日志

**特效范围设置不生效的排查**：先做两步——①打印运行时窗口 frame 与画布 bounds 是否随设置值同步变大；②检查是否有硬编码的 `shadowPad`/留白常量封顶了扩散范围。不要先去怀疑设置订阅链路。

## 测试

没有自动化测试套件。手动测试流程：

1. 构建：`./build.sh`
2. 启动：`open .build/debug/BetterFocusIDE.app`
3. 触发事件：使用装有 hook 的 Qoder/OpenCode，或直接向 socket 发送 JSON
4. 验证：卡片出现、键盘快捷键、钉住/取消钉住、历史、设置改动、自检结果
5. 查看日志：`~/Library/Application Support/BetterFocusIDE/logs/betterfocus.log`

### 二级定位测试

验证 IDE 跳转是否精确聚焦到项目窗口：

```bash
# 向 socket 发送测试消息（替换 bundle/cwd 为实际值）
SOCKET=~/Library/Application\ Support/BetterFocusIDE/agent-events.sock

# JetBrains 测试
echo '{"provider":"qoder","product":"jetbrains_plugin","event":"turn_finished","session_id":"test-'$(date +%s)'","host":{"bundle":"com.jetbrains.intellij","name":"IntelliJ IDEA","path":"/Applications/IntelliJ IDEA.app"},"cwd":"/path/to/your/project","payload":{"transcript_path":""}}' | nc -U "$SOCKET"

# Qoder IDE 测试
echo '{"provider":"qoder","product":"qoder_ide","event":"turn_finished","session_id":"test-'$(date +%s)'","host":{"bundle":"com.qoder.ide","name":"Qoder","path":"/Applications/Qoder IDE.app"},"cwd":"/path/to/your/project","payload":{"transcript_path":""}}' | nc -U "$SOCKET"
```

点击通知后检查日志中的定位方式：
- `已用 JetBrains CLI 定位窗口` → 第一层成功
- `AXRaise 定位 JetBrains 窗口` → 第二层成功
- `已定位 JetBrains 窗口...菜单定位` → 第三层兜底
- `已用 code -r 定位 Qoder 窗口` → VS Code 系成功
- `已激活 ...` → 回退到 App 级激活

## 经验教训

从开发过程中提炼的常见陷阱与排查方法论，按领域分组。

### 窗口与图层

- **透明窗口系统投影**：`panel.hasShadow = true` 时系统按整窗 alpha 生成投影，会把半透明辉光自身压暗并在衰减末段造出假性"分层线"。解决：`hasShadow = false`，主体投影下沉到 `body.layer.shadow*` 自绘。
- **越界特效不能靠 zPosition 逃逸父层 mask**：`CALayer.mask` 裁剪作用于整棵子树。唯一出路是把特效移到不含该 mask 的祖先层。
- **悬浮窗特效范围设置不生效**：先查固定窗口留白（`shadowPad`）是否封顶了扩散，再查 `masksToBounds` 双重裁剪——不要先怀疑设置订阅链路。
- **NSPanel 无 `.layer`**：只有 `contentView?.layer` 存在。

### SwiftUI 命中测试

- **透明装饰层 + `contentShape` 会吞掉下层按钮点击**：`bubbleWithGlow` 在 ZStack 中位于 `expandedContent` 之后（渲染在上层），若设 `.contentShape(Rectangle()) + .onTapGesture{collapse()}`，气泡高度调大后透明矩形向下延伸盖住按钮。解决：纯装饰层用 `.allowsHitTesting(false)`。
- **含 `disabled` 子视图的 HStack 行需 `contentShape`**：被 `disabled()` 置灰的控件会吞掉自身区域的鼠标事件，导致整行 `.help()` tooltip 悬停不弹出。解决：`.contentShape(Rectangle())` 把整行纳入统一命中区。

### 图像后处理

- **预乘位图乘增益或叠印提浓会钳成白雾**：高斯模糊输出是预乘 alpha（RGB ≤ alpha），对整张位图做通道增益会把 RGB 钳到 255 变白雾 + 放大量化台阶产生等高线。解决：浓度做进模糊之前的源形状膨胀宽度。
- **循环呼吸动画禁用极值零速度缓动**：`easeInEaseOut` + `autoreverses` 在两端各产生约 0.3s 驻留平台。解决：余弦关键帧 + `CAKeyframeAnimation(.cubic)`，在 L* 感知空间插值。

### 内嵌脚本模板

- **Swift 内嵌 Python 模板的三引号转义**：`HelperTemplate.swift` 用 `"""..."""` 承载 Python 源码，Python docstring 三引号必须写成 `\"""`。离线部署手工重写 hook 时必须先还原 Swift 转义再替换占位符，并立刻用 `py_compile.compile(doraise=True)` 校验。
- **shell 可见的环境变量不代表 Python 子进程能读到**：`echo "$KEY"` 在 shell 层返回 YES 不保证子进程继承了该变量（可能未 export、被 `uv tool` 隔离环境屏蔽）。解决：在目标解释器内验证或直接降级为宿主内联。
- **整文件复制参考工程源码会因依赖闭包过大编译失败**：大型参考工程的单文件内部引用大量同工程其他模块类型。解决：按最小可运行子集手写裁剪。

### 排查方法论

- **裁切排查必须以运行时尺寸与 origin 日志替代肉眼估图**：`screencapture` + PIL 放大裁图在深色背景下极不可靠。先打印 `target`/`host.frame`/`mask.bounds` 三者真实尺寸与 origin。
- **修 UI 表现前必须先确认"用户看到的是哪一层"**：BetterFocusIDE 采用 AppKit 画形状 + SwiftUI 叠内容双层结构，症状可能来自任一层。
- **回滚后必须立刻 `swift build` 验证**：手写 `SearchReplace` 容易引入语法错误，不能仅凭 diff 目测。
- **面板内容水平 inset 必须 ≥ shoulder(14)**：`NotchShape` 轮廓在中间段按 `shoulder` 内缩，inset 小于 shoulder 的内容会被黑 mask 裁掉行边缘。

## 重要决策

从技术选型中提炼的关键决策记录。

### 外发光方案选型

**结论**：单层 CALayer + CPU 预渲染位图（`CGContext` + `CIGaussianBlur`），插在 body 之下。
**否决方案**：`CAShapeLayer.shadow`（透明窗口只出硬描边）、`CALayer.filters`（对矢量内容整层不输出）、多层同心描边（肉眼可见台阶）。
**适用边界**：borderless/透明/无系统阴影的合成环境。若改用有正常背景的常规窗口或 Apple 提供可用的 `layer.shadow` 合成条件，可重新评估。

### 提问拦截策略

**结论**：用 `PermissionRequest` 而非 `PreToolUse` 拦截 `AskUserQuestion`。
**理由**：`PermissionRequest` 是阻塞式（Qoder 等待 hook 返回决策后再继续），`PreToolUse` 是 fire-and-forget（Qoder 不等待响应）。
**适用范围**：`AskUserQuestion` 仍走提问卡。带 `command` 的 Qoder `PermissionRequest` 等岛上的三按钮卡：`允许` / `拒绝` 回 `allow` / `deny`；Qoder IDE 的 `始终允许` 走设置页保存时用的语言服务。先 `config/getGlobal` 取整份配置，再 `config/updateGlobal` 只改这一张卡对应的一项：终端是 `terminalRunMode=fullAccess`，Web 是 `webToolsExecutionMode=enabledAutoExecute`，计划智能体是 `planModeRunConfig=autoRunInFuture`。终端卡再调 `config/updateGlobalTerminalRunMode`。点 Web 卡不会改计划智能体。套接字是 `~/Library/Application Support/Qoder{,CN}/SharedClientCache/qoder.sock`。JetBrains 里的 Qoder 插件中间按钮同样是「始终允许」，方法和枚举与 IDE 相同，但语言服务是插件自己拉起的：英文版 `~/.qoder/shared_client/qoder.sock`（product `jetbrains_plugin`），国内版 `~/.qoder-cn/shared_client/qodercn.sock`（product `jetbrains_cn_plugin`）。插件设置页读这次 `config/getGlobal`，不读 IDE 的 `User/app.json`，所以不要把 IDE 的 `app.json` / `settings.json` 写进去。设置页重新打开时读 `User/app.json`，并会把它同步回语言服务。所以同一决定还要写进 `app.json` 和 `User/settings.json` 里这一项：终端是 `terminalRunMode` / `configChatTerminalRunMode`，Web 是 `webToolsMode`=`Auto-execute` / `configChatWebToolsMode`，计划是 `planModeRunConfig`=`Auto-run` / `configIntegrationsPlanModeRunConfig`。语言服务枚举和设置页文案不是同一套字符串。这条 hook 仍回 `allow`。Qoder 会采信 `allow` / `deny`，stdout 没有「始终允许」字段。允许列表只在终端模式 `askEveryTime` 时减少后续确认。`PermissionRequest` 只在宿主已经要问人时触发，`acceptEdits` / `auto` 下的终端命令也会走到这里，不能按会话模式提前回 `ask`。stdout 始终写 `permissionDecision`。`decision.behavior` 只附在 Qoder.app 上；IDE 不认这个对象，附上会把整段 stdout 丢掉，卡片上的允许不会生效。Qoder.app 的「本会话允许」带 `updatedPermissions`（`命令名:*`，`destination` 为 `session`）。不要写成 `userSettings`：那会进 `~/.qoder/settings.json` 的 `permissions.allow`，永久作用于整个 Qoder，设置页里没有地方改回去。Qoder.app 的终端命令在会话模式为每次询问（`accept_edits`）时，于 PreToolUse 上等岛上的卡片：允许和本会话允许都回 allow，拒绝回 deny，检查结果不再是 ask，原生审批框不会先画出来。自动审批（`auto`）和完全访问（`bypass_permissions`）不开卡，也不回决策，让 Qoder 自己放行。本会话允许记在 hook 的会话状态里，同一个会话的下一次同类命令不再开卡，会话结束就失效。若检查仍然要问（工作区外的安全询问），紧接着的 PermissionRequest 立刻回放同一决定。IDE 的 PreToolUse 仍然立刻退出；IDE 的始终允许只改这一张卡对应的那一项，不再写允许名单，stdout 只回 `permissionDecision`。没有 `command`、也不是 `WebSearch` / `WebFetch` / `SwitchMode` / `EnterPlanMode` / `ExitPlanMode` / `PlanAgent` 的权限请求仍只发 `permission_notice` 并立刻 `emit("ask")`。`SwitchMode` 是执行方式，等三按钮卡。`CreatePlan` 是这份计划要不要执行，只发通知（点击仍跳回 IDE），立刻回 `ask`，选择留在 IDE 的「执行」上。允许回 `allow`、拒绝回 `deny`。`AskUserQuestion` 的 `allow` 会被收下，IDE 仍会弹出自己的确认；语言服务对这个工具名关掉了 hook allow 后的跳过。超时同样回 `ask`。

### 布局参照基准

**结论**：灵动岛各卡片的尺寸与行布局一律以 Python 原工程 `dynamic-Island-python-validate` 的 `config.py` 常量与显式矩形绘制算法为权威参照。
**否决方案**：凭 SwiftUI 自适应直觉自拟数值（`maxWidth: .infinity` + `fixedSize` + `layoutPriority` 组合调参），对 greedy/fixed 混合行的压缩顺序不确定，肉眼难判定且反复返工。
**适用边界**：只要目标是与 Python 原版逐像素对齐的迁移即成立。若未来脱离原设计做全新 UI 风格，需重新评估。

## 宿主适配矩阵（多宿主接入）

**结论**：每个宿主一个安装器，一套 Python 正文覆盖四种方言（`cursor` / `claude` / `codex`，Qoder 另有一份 `HelperTemplate`）。

| 宿主 | 配置 | 协议 | 能接管 |
|---|---|---|---|
| Qoder / Qoder CN | `~/.qoder{,-cn}/settings.json` | matcher 分组 | 提问、权限、回合、会话结束 |
| OpenCode | `~/.config/opencode/plugins/*.js` | 插件 | 提问、回合、待办（v2 要 `experimental.todo`，听 `message.part.updated`） |
| Cursor | `~/.cursor/hooks.json` | camelCase；不注册权限钩子 | 回合、会话结束、子任务、即将压缩 |
| WorkBuddy | `~/.workbuddy/settings.json` | PascalCase | 全部 |
| Claude Code | `~/.claude/settings.json` | PascalCase | 全部 |
| Trae / Trae CN | `~/.trae{,-cn}/hooks.json` | 同 Claude + `version:1` | 提问、权限提醒、回合（**无 SessionEnd**） |
| Kimi Code CLI | `~/.kimi-code/config.toml` | TOML `[[hooks]]`（只认 4 字段） | 全部 |
| Codex / ChatGPT | `~/.codex/hooks.json`；`notify` 仅在槽位空着时写入 | stdin 的 PascalCase hook；`notify` 的 payload 走 argv | 提问（仅当工具名是 AskUserQuestion）、权限提醒、回合完成、会话结束 |

**CLI 宿主的双身份**：产品身份来自 hook（编译期写入的 `PROVIDER`），终端身份来自父进程走查到的
最外层 `.app`。卡片标成 `Qoder CLI（Warp）`、图标用终端图标、点击激活终端窗口，
三者共用 `Models/TerminalHost.swift` 一份名单。认不出终端时**只写产品名**，不要退回 `host.name`
（那会把「Qoder CN CLI」显示成「WorkBuddy」）。

**三条踩过的坑**（详见 `knowledge/technologies/active/sprint2611/cli-host-adaptation/01-适配经验.md`）：
1. Codex 的 `notify` payload 在 **argv**：启动器必须 `exec python hook.py "$@"`。有 argv 时不能读 stdin（notify 不关 stdin，会卡死终端）。`hooks.json` 没有 argv，这时才读 stdin。
2. TOML 没有「只加一条」的入口：用注释界标维护受管区块，界标外一字节不碰。`notify` 被别人占用时跳过这一键，改登记 `hooks.json`，不要覆盖、也不要因此让整个安装失败。
3. Trae 的 `Notification` matcher 匹配 `notification_type`（不是工具名），应为 `permission_prompt`。

