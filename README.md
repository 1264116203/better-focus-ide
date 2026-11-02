# BetterFocusIDE

macOS 刘海「灵动岛」通知助手。把 Qoder / OpenCode 的**提问、权限申请、回复完成**三件事，收进屏幕顶部的刘海里：卡片直接弹出、一键跳回 IDE、还能用键盘秒答。

由 Python 版 `dynamic-Island-python-validate` 迁移而来的 Swift 原生实现，参考 [Vorssaint](https://github.com/) 的灵动岛动画与 UI。

- **要求**：macOS 14+，Apple Silicon（`arm64`）
- **技术栈**：Swift 5.9 + SwiftPM executable，AppKit 窗口壳 + SwiftUI 内容
- **许可**：GPL-3.0（`SPDX-License-Identifier: GPL-3.0-or-later`）
- **形态**：`LSUIElement` 后台应用，无 Dock 图标，只在状态栏留一个胶囊图标

---

## 目录

- [功能总览](#功能总览)
- [安装与启动](#安装与启动)
- [绕过 Gatekeeper（未签名应用）](#绕过-gatekeeper未签名应用)
- [同事一键接入 Qoder / OpenCode](#同事一键接入-qoder--opencode)
- [键盘答卡快捷键](#键盘答卡快捷键)
- [图钉固定模式](#图钉固定模式)
- [刘海屏行为](#刘海屏行为)
- [状态栏菜单](#状态栏菜单)
- [数据与文件位置](#数据与文件位置)
- [自检（Doctor）](#自检doctor)

---

## 功能总览

| 能力 | 说明 |
|---|---|
| **灵动岛动画** | 参考 Vorssaint 的弹簧逐帧形变（`CAKeyframeAnimation` 驱动 mask 路径），展开/收起是"液态"的刘海轮廓，不是硬弹 |
| **玻璃 + 投影** | 展开态用 `NSVisualEffectView` 磨砂材质 + 窗口外投影；收起态纯黑融入物理刘海 |
| **提问卡片** | Agent 的选择题在刘海里作答：单选/多选、"其他…"自定义输入、多题翻页 |
| **权限卡片** | 工具调用的审批：允许 / 始终允许 / 拒绝 |
| **回复完成通知** | 一轮回复完成弹横幅，**点一下跳回对应 IDE 窗口**；标题取会话真实首条原话（非套话） |
| **键盘答卡** | 数字键选项、Y/A/N 决策、Enter 发送、Esc 收起、⌘, 设置、⌘⇧P 固定 |
| **图钉固定** | 钉住保持展开 ⇄ 按需自动收起 |
| **通知历史** | 点空闲的岛回顾最近 5 条通知，点某条跳回来源 |
| **设置面板** | 通知开关、声音/震动、卡片行为、默认固定偏好 |
| **声音与触感** | 系统提示音 + 触控板震动 |
| **Hook / Plugin 安装器** | 一键接入 Qoder Hook 与 OpenCode Plugin，幂等、只动自己的条目 |
| **单实例互斥** | `flock` 启动锁，防止重复启动多个灵动岛 |
| **刘海屏优先** | 固定钉在内置刘海屏，不随焦点在两屏间跳 |
| **落盘日志** | `logs/betterfocus.log`，5MB×3 轮转，跨进程消息脱敏 |
| **Doctor 自检** | 一键排查 socket / hook 注册 / 答案目录 / 设置是否就绪 |

---

## 安装与启动

用仓库里的 `build.sh` 打包（SwiftPM 编译 → 手动组装 `.app` → ad-hoc 签名）：

```bash
cd better-focus-ide
./build.sh
# 产物：.build/debug/BetterFocusIDE.app
```

安装到应用程序目录并启动：

```bash
cp -R .build/debug/BetterFocusIDE.app /Applications/
xattr -dr com.apple.quarantine /Applications/BetterFocusIDE.app   # 见下一节
open /Applications/BetterFocusIDE.app
```

启动后屏幕顶部刘海会出现胶囊，状态栏也有一个图标。

---

## 绕过 Gatekeeper（未签名应用）

本应用**不做开发者签名**（仅内部使用），首次从 `/Applications` 或下载目录打开时，macOS 会拦截"无法验证开发者"。任选一种绕过：

**方式 A：命令行去掉隔离属性（推荐，最省事）**

```bash
xattr -dr com.apple.quarantine /Applications/BetterFocusIDE.app
```

**方式 B：访达里右键打开**

在 Finder 中选中 `BetterFocusIDE.app` → **右键 / 双指点按 → 打开 → 打开**（首次右键确认后即可正常双击启动）。

**方式 C：系统设置放行**

`系统设置 → 隐私与安全性` → 底部会出现"已阻止 BetterFocusIDE"，点**仍要打开**。

> ad-hoc 签名（`codesign --sign -`）只保证本地能跑，不替代 Apple 公证；换机器 / 重新下载后隔离属性会回来，需再执行方式 A。

---

## 同事一键接入 Qoder / OpenCode

装好应用后，点状态栏图标 → **一键安装 Hook / Plugin**。它会自动写入两处集成，**幂等、且只增删自己的条目**（用 `betterfocus` 标记隔离，绝不碰你已有的其它 hook）：

**Qoder**（写入 `~/.qoder/`）
- `hooks/betterfocus-notify.sh` —— 启动器
- `hooks/betterfocus-hook.py` —— hook 体（转发事件、轮询答案）
- `settings.json` —— 注册 4 个事件（`PreToolUse` / `PermissionRequest` / `SessionEnd` / `Stop`）

**OpenCode**（写入 `~/.config/opencode/plugins/betterfocus-notify.js`）
- 接管 `question` 工具 + 监听 `session.idle` 发回复完成事件

安装摘要（成功/失败逐条）会弹窗提示。要移除：状态栏图标 → **卸载 Hook / Plugin**。

**接入后验证**：在 Qoder / OpenCode 里让 Agent 提一个选择题，刘海应弹出提问卡片。没反应就用下面的 [Doctor 自检](#自检doctor)。

> 安装器只做语法校验级别的自检，**不会**替你改正在使用的 IDE 配置以外的东西；它只写上述带 `betterfocus` 标记的文件。

---

## 键盘答卡快捷键

> ⚠️ 前提：键盘快捷键**只在灵动岛成为当前焦点窗口后生效**——先**点一下岛**（卡片/胶囊）让它聚焦。岛是后台应用，绝不会主动抢走你终端 / 编辑器里正在敲的字；没被认领的按键原样交还系统。

**提问卡片**

| 键 | 动作 |
|---|---|
| `1` – `9` | 选中第 N 个选项 |
| `←` / `→` | 多题时翻上一题 / 下一题 |
| `Enter` | 发送答案 |
| `Tab` | 跳到"其他…"自定义输入框 |

**权限卡片**

| 键 | 动作 |
|---|---|
| `Y` 或 `1` | 允许（本次） |
| `A` 或 `2` | 始终允许 |
| `N` 或 `3` | 拒绝 |

> 权限卡**刻意不认 `Enter`**：高危操作要有明确的 Y/A/N 意图，防误批。

**通用**

| 键 | 动作 |
|---|---|
| `Esc` | 收起卡片 |
| `⌘ ,` | 打开设置 |
| `⌘ ⇧ P` | 切换图钉固定 |

**内置防误触保护**（与鼠标点击同一口径）：卡片刚出现 0.5 秒内、正在"其他…"里打字时、卡片淡出中、卡片收在气泡里——这四种情况下按键一律不响应，避免"手正搭在键盘上就误批了一条 `rm -rf`"。

---

## 图钉固定模式

每张卡右上角的图钉 = **固定 ⇄ 按需** 开关（点图钉或按 `⌘ ⇧ P` 切换）：

- **固定（`pin.fill` 高亮）**：卡片保持展开，回复完成横幅**不自动收起**，等你点击或手动收起。
- **按需（`pin` 斜置）**：横幅按设置的停留时长（默认 5 秒）自动 retract，把屏幕让回给你。

新出现的卡片默认走哪个模式，由 `设置 → 卡片行为 → 新卡片默认固定（保持展开）` 决定；单张卡上的临时切换不影响这个偏好。

---

## 刘海屏行为

- 灵动岛**固定钉在内置刘海屏**（`safeAreaInsets.top > 0` 的那块显示器），而不是跟随键盘焦点的主屏。
- 多显示器下，即使你把焦点切到外接屏、或外接屏是主屏，岛也**不会漂到外接屏**——它始终贴着物理刘海。
- 插上 / 拔掉显示器时会自动重算位置。
- 若机器没有刘海屏（纯外接），退化为在该屏顶部居中显示。

---

## 状态栏菜单

点状态栏胶囊图标：

| 菜单项 | 快捷键 | 作用 |
|---|---|---|
| 展开 / 收起灵动岛 | `T` | 手动切换 |
| 最近通知 | `H` | 打开历史面板 |
| 一键安装 Hook / Plugin | — | 接入 Qoder + OpenCode |
| 卸载 Hook / Plugin | — | 移除集成 |
| 自检（Doctor）… | `D` | 打开自检窗口 |
| 设置… | `⌘ ,` | 打开设置 |
| 退出 BetterFocusIDE | `⌘ Q` | 退出 |

---

## 数据与文件位置

全部在独立命名空间 `BetterFocusIDE` 下，可与 Vorssaint / Python 版并存不争用：

```
~/Library/Application Support/BetterFocusIDE/
├── agent-events.sock          # 事件通道（Unix socket，换行分隔 JSON）
├── agent-events.sock.lock     # 单实例 flock 锁（内含持有者 pid）
├── answers/                   # 作答结果回写目录
├── settings.json              # 用户设置
└── logs/betterfocus.log       # 运行日志（5MB × 3 轮转，脱敏）

~/.qoder/hooks/betterfocus-notify.sh      # Qoder Hook 启动器
~/.qoder/hooks/betterfocus-hook.py        # Qoder Hook 体
~/.qoder/settings.json                    # Qoder Hook 注册（带 betterfocus 标记）
~/.config/opencode/plugins/betterfocus-notify.js   # OpenCode Plugin
```

**日志环境变量**（排障用）：

```bash
BETTERFOCUS_LOG_STDERR=1   # 同步打到终端
BETTERFOCUS_LOG_LEVEL=info # 调整级别（debug/info/warning/error）
```

---

## 自检（Doctor）

状态栏 → **自检（Doctor）…**，逐项检查并给修复建议：

- **Socket 是否存活**（探活连接）
- **Hook / Plugin 文件是否就位**
- **Qoder `settings.json` 是否注册了带 `betterfocus` 标记的 PermissionRequest 组**
- **答案目录是否可写**
- **设置文件是否可读**

点"重新自检"可再次扫描。装了但卡片不弹，八成是 Qoder 端 hook 没注册成功或 socket 没起来，先跑这个。

---

## 许可

GPL-3.0-or-later。本仓库含从 Vorssaint（GPL-3.0）参考裁剪的灵动岛窗口/动画代码，整体按 GPL 分发，内部使用请保留许可证头。
