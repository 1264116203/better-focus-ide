# 根因报告：Qoder / OpenCode 通知卡片不弹出

日期：2026-11-04
症状（用户描述）：Qoder 的消息在"最近通知"历史中有数据，但通知卡片（横幅）不弹出；OpenCode 则历史和横幅完全没有数据。

---

## 根因 1（Qoder）：新版 Qoder 会话被 `fromCLI` 误判为无头 CLI 会话

### 结论

Qoder 新版（内核 1.1.75-hotfix.1）把会话交给共享内核服务执行，其 transcript 写在 CLI 风格的
`~/.qoder/projects/` 且首条 user 记录带 `entrypoint: "cli"`。BetterFocusIDE 的
`Transcript.Session.fromCLI`（`entrypoint == "cli"` 即判定无头脚本）据此抑制横幅——但只记历史，
正好产生"历史有数据、横幅不弹"的症状。

### 证据链

1. **抑制路径唯一性**：`NoticeController.handleTurnFinished`（Sources/BetterFocusIDE/Services/NoticeController.swift）
   的顺序是 `onRemember`（记历史）→ `if parsed.fromCLI { return }` → `show()`。
   "历史有数据 + 无横幅"只能走 `fromCLI == true`。
2. **运行时证据**：日志 `2026-11-04 16:26:48 / 16:29:23 turn_finished qoder session=1f03a84d`
   之后均无 `animateTo ... activeCard=notice`；对照组 `16:26:19 session=28bd48b4`、
   `16:59:47 session=test-179` 横幅正常弹出。
3. **会话状态**：`sessions/1f03a84d-….json` = `{"product": "qoder_cli"}`——hook 进程环境变量
   `QODER_PROJECT_DIR` 有值且 `QODER_SESSION_ID` 无值（`_identify_product()` 优先级 1）。
4. **transcript 判据命中**：`~/.qoder/projects/-Users-yujie-xu-Documents-Qoder-2026-11-02-1f03a84d/1f03a84d-….jsonl`
   首条 user 记录 `entrypoint: "cli"` → `fromCLI = true` → 横幅被抑制。
5. **为什么真人会话有 CLI 特征**：Qoder GUI（Qoder.app / Qoder IDE.app）通过内核服务跑会话
   （`~/.qoder/shared_client/bin/…/Qoder start` 守护进程、Qoder.app 的 `qoder-agent-sdk` worker、
   Qoder IDE 内嵌 `resources/bin/…/Qoder start`）。内核进程触发 Stop hook 时只带
   `QODER_PROJECT_DIR`，transcript 由内核写入 `~/.qoder/projects/`（type/entrypoint 格式）。
6. **排除终端 CLI**：本机 `qodercli --version` = 1.1.31 ≠ transcript `version` = 1.1.75-hotfix.1；
   transcript `humanInput = {'text': 'hi', 'mode': 'prompt'}`、`origin.kind = 'human'`（真人在 UI 输入）。
7. **对照组（老会话正常）**：28bd48b4（chat-4，2026-10-19 创建）的 transcript 在
   `~/.qoder/cache/projects/chat-4-42b32838/conversation-history/28bd48b4/28bd48b4.jsonl`
   （role/message 格式，**没有 type/entrypoint 字段**）→ `entrypoint == ""` → `fromCLI = false` → 正常弹横幅。
   这解释了"为什么有的 Qoder 通知能弹"的矛盾。
8. **可靠区分判据（关键发现）**：首条 user 记录的 `humanInput` 字段——
   - 真人 UI 输入（含粘贴）：`humanInput = {'text': …, 'mode': 'prompt'}`（1f03a84d 的 "hi"、
     diff-report-test 手动贴 diff 的 53472130 会话）
   - 程序化输入（qodercli -p 管道 diff）：`humanInput = None`（623ad8bf 会话）
   - `origin.kind` 不可靠：管道会话也可能是 `'human'`。

### 次要问题（同根同源）

`product` 误判为 `qoder_cli`（实际是 GUI 会话），影响历史条目的渠道显示与跳转目标。
hook 父链在内核服务架构下直达 launchd（host 为空），环境变量判据失效。
影响面小（显示与跳转回退仍可用），本轮可作为可选项一并修。

---

## 根因 2（OpenCode）：插件订阅事件用了不存在的 `ctx.event.on` API

### 结论

已安装的 `~/.config/opencode/plugins/betterfocus-notify.js` 用
`ctx.event.on('session.idle', …)` 订阅事件，但 OpenCode（本机 v2.1.2）的 `ctx.event`
是**异步可迭代事件流**（`ctx.event.subscribe({ signal })`），没有 `.on()` 方法。
插件代码 `if (ctx.event && ctx.event.on)` 恒为 false，**静默跳过注册**——插件加载"成功"，
turn_finished 却从未发送。

### 证据链

1. 插件加载正常：`~/.local/share/opencode/log/opencode.log` 今天多次
   `loading plugin … betterfocus-notify.js`，无 `failed to load plugin` WARN（10-22 的失败均为
   vorssaint 旧插件，已被 vorssaint-notify-Python.js 取代）。
2. 会话确有活动：今天日志 176 次 `spawning process`（shell 工具调用），但 BetterFocusIDE
   全天零 `provider=opencode` 事件（11-02/11-03 的 n-9、test-ses、qa-live- 为手动 socket 测试）。
3. **API 形态对照**：同目录 `vorssaint-notify-Python.js`（已验证工作）用
   `for await (const event of ctx.event.subscribe({ signal: … }))`；事件形态
   `{type, data}`：
   - 旧版发 `session.idle`（`data = {sessionID}`）
   - **2.x 发 `session.status`**，需 `data.status.type === 'idle'` 才代表轮次结束
     （busy/retry 是轮次中间态）
   - sub-session 也会触发，需要约 2 秒去抖
4. `ctx.tool.transform`（question 工具接管）API 正确，与 vorssaint 相同——所以 setup 不报错，
   问题被完全掩盖。

---

## 修复方案

### A. Qoder 侧（BetterFocusIDE Swift）

`Transcript.swift`：
1. `Session` 增加"首条 user 记录是否带人类输入标记"的信息（解析 `humanInput` 字段是否存在且非 null）。
2. `fromCLI` 判定收紧：`entrypoint == "cli"` **且** 首条 user 记录无 `humanInput` 才视为无头会话；
   带 `humanInput` 的（真人 UI 输入）正常弹横幅。
3. 单元测试：三种 transcript 形态（带 humanInput 的 projects 格式 / 无 humanInput 的 projects
   格式 / cache conversation-history 格式）。

### B. OpenCode 侧（PluginTemplate.swift 插件模板）

`Sources/BetterFocusIDE/Services/Installer/OpenCodePluginInstaller.swift` 的 `PluginTemplate.body`：
1. 用 `ctx.event.subscribe({ signal })` 异步迭代替换 `ctx.event.on(...)`。
2. 兼容 `session.idle` 与 `session.status`（`status.type === 'idle'` 过滤）。
3. sessionID 从 `event.data` 提取，附 2 秒同会话去抖。
4. 重新安装插件（`install()` 内容比较后自动覆写）；OpenCode watcher 会热重载。

### C. 可选项

hook `_identify_product()` 的 `qoder_cli` 误判（GUI 会话被标为 CLI）——影响历史显示文案与
跳转目标。涉及 hook 模板与已安装脚本同步，建议单独一轮处理。

---

## 验证方法

- Qoder：在 Qoder（新版内核）里发一条消息，等待回复完成 → 灵动岛应弹横幅；
  `qodercli -p "hi"` 跑无头会话 → 不弹横幅但记历史（回归保护）。
- OpenCode：在 OpenCode 里跑一轮对话，结束后灵动岛弹横幅；日志出现
  `turn_finished provider=opencode`。
