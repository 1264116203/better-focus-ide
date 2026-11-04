# Phase 2 完成：TDD 修复循环（ss-tdd-cycle）

- 测试（红→绿）：
  - `Tests/BetterFocusIDETests/TranscriptCLITests.swift`（7 个用例）：真人 UI 输入（humanInput
    有值）不再被抑制；管道/无头会话保持抑制；cache 格式与缺字段行为保持；标题解析不受影响。
  - `Tests/BetterFocusIDETests/OpenCodePluginTemplateTests.swift`（7 个用例）：subscribe 流 API、
    session.status/session.idle 双兼容、idle 过滤、去抖、占位符替换完整性。
  - 结果：14/14 通过。全量套件仅剩 SettingsTests 2 个 bodyFont 失败（并行会话修改中的
    预先存在问题，与本轮无关）。
- 实现：
  - `Transcript.swift`：Session 增加 `hasHumanInput`；`fromCLI` 收紧为
    `entrypoint == "cli" && !hasHumanInput`；`lineUser`/`first` 返回三元组。
  - `OpenCodePluginInstaller.swift`：`ctx.event.on(...)`（不存在的 API）替换为
    `ctx.event.subscribe({signal})` 异步迭代 + session.status(idle)/session.idle 双兼容 +
    2 秒同会话去抖。
- 部署：新插件内容已写入 `~/.config/opencode/plugins/betterfocus-notify.js`
  （node --check 通过；OpenCode watcher 已于 17:12:44 热重载，无失败记录）。
  Transcript 修复需重启 BetterFocusIDE 应用生效。
