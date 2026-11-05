<div align="center">

# 🏝️ BetterFocusIDE

**把 MacBook 的刘海，变成面向 AI 编码智能体的「灵动岛」通知助手**

Turn your MacBook notch into a Dynamic-Island-style assistant for AI coding agents.

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)]()
[![Arch](https://img.shields.io/badge/arch-arm64%20(Apple%20Silicon)-9cf.svg)]()
[![Language](https://img.shields.io/badge/Swift-5.9-orange.svg)]()
[![SPM](https://img.shields.io/badge/SwiftPM-ready-brightgreen.svg)]()

</div>

---

当 Qoder / OpenCode / Cursor / WorkBuddy 里的 AI Agent 需要**向你提问**、**申请权限**、或**完成一轮回复**时，BetterFocusIDE 会在刘海区域弹出可交互卡片——**一键回答、点一下跳回 IDE、键盘秒答**，全程不打断你正在敲的代码。

BetterFocusIDE is a native macOS menu-bar accessory app (no Dock icon) that surfaces agent **questions**, **permission requests**, and **turn-completion notices** as interactive cards in the notch. It's a Swift rewrite of the Python prototype `dynamic-Island-python-validate`, with animation and UI inspired by [Vorssaint](https://github.com/Vorssaint).

---

## ✨ Features

- 🫧 **灵动岛动画** — 弹簧逐帧形变，展开/收起是「液态」刘海轮廓，不是硬弹
- 🪟 **玻璃 + 投影** — 展开态磨砂材质 + 窗口外投影，收起态纯黑融入物理刘海
- ❓ **提问卡片** — 单选/多选、「其他…」自定义输入、多题翻页
- 🔐 **权限卡片** — 工具调用审批：允许 / 始终允许 / 拒绝
- ✅ **回复完成通知** — 点一下跳回对应 IDE 窗口，标题取会话真实首条原话
- ⌨️ **键盘答卡** — 数字键、`Y`/`A`/`N` 决策、`Enter` 发送、`Esc` 收起
- 📌 **图钉固定** — 固定保持展开 ⇄ 按需自动收起
- 🕘 **通知历史** — 点空闲的岛回顾最近 5 条通知
- ⚙️ **设置面板** — 通知开关、声音/震动、卡片行为偏好
- 🔌 **一键接入** — 幂等安装 Qoder / OpenCode / Cursor / WorkBuddy 四处 hook
- 🛡️ **单实例互斥** — `flock` 启动锁，防止重复启动
- 🖥️ **刘海屏优先** — 固定钉在内置刘海屏，不随焦点在两屏间跳
- 🩺 **Doctor 自检** — 一键排查 socket / hook 注册 / 答案目录是否就绪

> 🖼️ **截图**：项目运行截图待补充。欢迎 PR 提交你的实拍图（`design/` 目录下现有 App 图标设计稿可参考）。

---

## 📦 Requirements

| 项 | 要求 |
|---|---|
| OS | macOS 14+ (Sonoma) |
| 芯片 | Apple Silicon (`arm64`) |
| 工具链 | Swift 5.9+ / Xcode 15+ |

---

## 🚀 Getting Started

### 构建

用仓库里的 `build.sh` 打包（SwiftPM 编译 → 手动组装 `.app` → ad-hoc 签名）：

```bash
git clone git@github.com:1264116203/better-focus-ide.git
cd better-focus-ide
./build.sh
# 产物：.build/debug/BetterFocusIDE.app
```

### 安装并启动

```bash
cp -R .build/debug/BetterFocusIDE.app /Applications/
xattr -dr com.apple.quarantine /Applications/BetterFocusIDE.app   # 绕过 Gatekeeper
open /Applications/BetterFocusIDE.app
```

启动后，屏幕顶部刘海会出现胶囊，状态栏也会出现一个图标。

### 接入你的 AI 编码工具

点状态栏图标 → **一键安装 Hook / Plugin**，自动写入四组集成（幂等、只增删自己的条目，绝不碰你已有的其它 hook）：

| 宿主 | 写入位置 | 注册的事件 |
|---|---|---|
| **Qoder** | `~/.qoder/` | `PreToolUse` / `PermissionRequest` / `SessionEnd` / `Stop` |
| **OpenCode** | `~/.config/opencode/plugins/` | `question` 工具 + `session.idle` |
| **Cursor** | `~/.cursor/` | `stop` / `sessionEnd`（观测型，恒回 `{}`） |
| **WorkBuddy** | `~/.workbuddy/` | `PreToolUse` / `Notification` + `PermissionRequest` / `Stop` / `SessionEnd` |

> **宿主的差异**
> - **Cursor 只做「完成/结束」通知**：它的权限类 hook 必须在 stdout 返回 `allow`/`deny`，那等于替你拍板或拦工具，所以审批仍留在 Cursor 自己的界面。
> - **WorkBuddy 的 hook 改动不热加载**：装完需新开一个会话才生效；权限提醒只弹横幅，审批在 WorkBuddy 原生对话框完成。

**接入后验证**：在宿主里让 Agent 提一个选择题，刘海应弹出提问卡片；让它跑完一轮，应弹完成横幅。没反应就用下面的 [Doctor 自检](#doctor-自检)。

---

## ⌨️ 键盘快捷键

> ⚠️ 键盘快捷键**只在灵动岛成为当前焦点窗口后生效**——先点一下岛让它聚焦。岛是后台应用，绝不会主动抢走你终端 / 编辑器里正在敲的字。

| 场景 | 键 | 动作 |
|---|---|---|
| 提问卡片 | `1`–`9` | 选中第 N 个选项 |
| 提问卡片 | `←` / `→` | 多题翻页 |
| 提问卡片 | `Enter` | 发送答案 |
| 提问卡片 | `Tab` | 跳到「其他…」自定义输入框 |
| 权限卡片 | `Y` / `1` | 允许（本次） |
| 权限卡片 | `A` / `2` | 始终允许 |
| 权限卡片 | `N` / `3` | 拒绝 |
| 通用 | `Esc` | 收起卡片 |
| 通用 | `⌘ ,` | 打开设置 |
| 通用 | `⌘ ⇧ P` | 切换图钉固定 |

> 权限卡**刻意不认 `Enter`**：高危操作要有明确的 `Y`/`A`/`N` 意图，防误批。

**内置防误触保护**：卡片刚出现 0.5 秒内、正在「其他…」里打字时、卡片淡出中、卡片收在气泡里——这四种情况按键一律不响应。

---

## 📌 图钉固定模式

每张卡右上角的图钉 = **固定 ⇄ 按需** 开关：

- **固定（`pin.fill` 高亮）**：卡片保持展开，回复完成横幅不自动收起。
- **按需（`pin` 斜置）**：横幅按停留时长（默认 5 秒）自动收起。

新卡片默认模式由 `设置 → 卡片行为 → 新卡片默认固定` 决定；单张卡上的临时切换不影响该偏好。

---

## 🖥️ 刘海屏行为

- 灵动岛**固定钉在内置刘海屏**（`safeAreaInsets.top > 0` 的那块显示器），不跟随键盘焦点的主屏。
- 多显示器下，即使焦点切到外接屏、或外接屏是主屏，岛也**不会漂到外接屏**。
- 插上 / 拔掉显示器时会自动重算位置。
- 机器没有刘海屏时，退化为在该屏顶部居中显示。

---

## 🗂️ 文件位置

全部在独立命名空间 `BetterFocusIDE` 下，可与 Vorssaint / Python 版并存：

```
~/Library/Application Support/BetterFocusIDE/
├── agent-events.sock          # 事件通道（Unix socket，换行分隔 JSON）
├── agent-events.sock.lock     # 单实例 flock 锁
├── answers/                   # 作答结果回写目录
├── settings.json              # 用户设置
└── logs/betterfocus.log       # 运行日志（5MB × 3 轮转，脱敏）

~/.qoder/hooks/betterfocus-*.{sh,py}          # Qoder Hook
~/.config/opencode/plugins/betterfocus-notify.js   # OpenCode Plugin
~/.cursor/hooks/betterfocus-*.{sh,py}         # Cursor Hook
~/.workbuddy/hooks/betterfocus-*.{sh,py}      # WorkBuddy Hook
```

**日志环境变量**（排障用）：

```bash
BETTERFOCUS_LOG_STDERR=1   # 同步打到终端
BETTERFOCUS_LOG_LEVEL=info # 级别：debug/info/warning/error
```

---

## 🩺 Doctor 自检

状态栏 → **自检（Doctor）…**，逐项检查并给修复建议：

- Socket 是否存活（探活连接）
- 各宿主 Hook / Plugin 文件是否就位（本机没装的宿主自动跳过）
- 宿主配置里是否登记了我们的条目
- 答案目录是否可写、设置文件是否可读

> 装了但卡片不弹，八成是宿主端 hook 没注册成功或 socket 没起来，先跑这个。

---

## 🏗️ Architecture

四层灵动岛栈（继承自 Python 参考实现）：

1. **窗口外壳** — `NotchPanel`（`NSPanel`）：无边框、透明、`level = statusBar + 1`
2. **动画层** — `NotchCanvas`（`NSView`）：`CAKeyframeAnimation` 驱动遮罩路径
3. **桥接层** — `NotchHostingView`（`NSHostingView`）：桥接 AppKit ↔ SwiftUI
4. **内容层** — `NotchView`（SwiftUI）：所有卡片 UI，状态由 `NotchService` 驱动

四种卡片各有一个专用状态机控制器：

| 卡片类型 | 控制器 | 触发事件 | 回答机制 |
|---|---|---|---|
| 提问 | `QuestionController` | `question_requested` | 写 JSON 到 `answers/<session>_<question>.json` |
| 权限 | `PermissionController` | `permission_requested` | 写 JSON 到 `answers/<session>_<request>.json` |
| 通知 | `NoticeController` | `turn_finished` / `session_ended` | 超时后自动消失 |
| 历史 | `HistoryController` | 内部 | 只读面板（最近 5 条） |

完整的架构说明见 [`AGENTS.md`](AGENTS.md)。

---

## 📁 Project Structure

```
├── Package.swift              # SwiftPM 清单（库目标 + 瘦可执行目标）
├── build.sh                   # 构建 + .app 组装 + ad-hoc 签名
├── Resources/                 # Info.plist、entitlements、图标
├── Sources/BetterFocusIDE/
│   ├── Models/                # 纯数据类型
│   ├── Services/              # Socket / Installer / 各控制器 / Doctor
│   └── UI/                    # SwiftUI 视图（强制深色模式）
└── Tests/                     # 单元测试
```

---

## 🧪 运行测试

```bash
swift test
```

---

## 📜 License

[GPL-3.0-or-later](LICENSE) © 2026 BetterFocusIDE

本仓库含从 [Vorssaint](https://github.com/Vorssaint)（GPL-3.0）参考裁剪的灵动岛窗口 / 动画代码，整体按 GPL 分发，内部使用请保留许可证头。

---

## 🙏 Acknowledgments

- [Vorssaint](https://github.com/Vorssaint) — 灵动岛动画与 UI 参考
- `dynamic-Island-python-validate` — 原始 Python 原型

---

<div align="center">

Made with ❤️ for developers who live in the terminal.

</div>
