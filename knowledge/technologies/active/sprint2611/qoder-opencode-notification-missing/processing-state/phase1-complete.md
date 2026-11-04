# Phase 1 完成：根因诊断（ss-diag-rootcause）

- 产物：`01-rootcause.md`（两个根因均闭环，HARD-GATE 满足）
- 根因 1（Qoder）：新版内核会话 transcript 带 `entrypoint: "cli"` → `fromCLI` 误判抑制横幅；
  可靠判据为首条 user 记录的 `humanInput` 字段（真人 UI 输入有值，管道输入为 None）。
- 根因 2（OpenCode）：插件用 `ctx.event.on(...)`（API 不存在，恒 false 静默跳过）；
  正确 API 为 `ctx.event.subscribe()` 异步迭代 + `session.status`（2.x）/`session.idle`（旧版）双兼容。
- 待确认：修复范围（A Qoder Transcript 判据 / B OpenCode 插件模板 / C 可选 product 误判）。
