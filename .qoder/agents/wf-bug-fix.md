---
name: wf-bug-fix
description: 缺陷修复工作流。诊断→根因→TDD 修复→审查。铁律：无根因不修复，修复必带回归测试。默认 enhanced。
---

# wf-bug-fix — 缺陷诊断与修复

**适用场景**：已知缺陷的定位-修复-审查。
**默认 profile**：enhanced。
**调用**：`/wf-bug-fix "缺陷描述/报错" [--resume] [--slug xxx]`

> **参数说明**：`--resume`、`--slug` 为文档约定参数，由 AI 解读并执行对应行为，非 Qoder 框架原生支持。

## 配置加载（执行前必做，第一步）

工作流启动时，**必须首先**按 `orchestrator-behavior.md` → "配置加载"：① Read `.qoder/wf-dev.yaml`；② 计算产物目录并 `mkdir -p .../processing-state`。**禁止**采集 `WORKFLOW_STARTED_AT`，**禁止**创建或写入 `workflow-metrics.json`（仅终点 `--aggregate` 根据 `phaseN-complete.md` 生成）。未完成配置加载不得调用任何技能。

## 包含技能与执行顺序

```
1. ss-diag-rootcause  定位根因 + 写失败复现测试 → 01-rootcause.md
   └─ [HARD-GATE: rootcause] 未定位根因不进入修复
2. ss-tdd-cycle       红-绿-重构最小修复（复现测试转绿） → 02-test-cases.md + 测试/实现代码
3. ss-code-review     双轴审查（含回归测试） → 03-code-review.md
```

> **产出物命名规范**：遵循 `orchestrator-behavior.md` → "产出物序号前缀规范"。

> **铁律（标记即原子）**：遵循 `orchestrator-behavior.md` → "标记即原子铁律"。

## Phase 计时

每个 phase 把起止时间与时长写入 `processing-state/phaseN-complete.md` Metrics（`phase_started_at` / `phase_completed_at` / `duration`）。全部阶段完成后调用 `ss-util-tracker --aggregate`，先读各标记再生成 `workflow-metrics.json`。

## 步骤确认机制

编排器在**每个关键步骤执行前**必须：
1. **汇总变更**：列出从工作流启动到当前步骤为止已完成的所有步骤及其产物（文件/结论/状态变更）。
2. **请求确认**：向用户展示下一步即将执行的技能名称与预期行为，等待用户明确确认后再继续。
3. **选项呈现**：严格遵循 `orchestrator-behavior.md` → "确认交互约束（防幻觉铁律）"。

关键步骤定义：本工作流中编号 1-3 的每个技能调用均为关键步骤。

## 关键节点
- **步骤 1** 为 HARD-GATE（见 `wf-dev.yaml → hard_gates.rootcause`）：`01-rootcause.md` 未给出有证据的根因，禁止修改代码。
- **步骤 2（ss-tdd-cycle）** 为代码生成起点，遵循 `orchestrator-behavior.md` →「`yall` 代码生成检查点」——用户选择 `yall` 时，编排器必须在本步骤执行前暂停，汇总中间产物待用户审计确认后继续。
- 修复必须包含步骤 1 产出的回归测试，防止复发。

## 异常处理

- 步骤 1（根因定位）未通过 → 按 `hard_gates.rootcause` 禁止修改代码，重新执行 `ss-diag-rootcause`。
- 步骤 2 修复后原测试仍红或引入新失败 → 回步骤 1 重新定位（可能是错误根因）。
- 若发现是需求理解偏差而非代码缺陷 → 转 `ss-analysis-spec` 澄清。

## --resume 续跑协议

遵循 `orchestrator-behavior.md` → "--resume 续跑协议"。**仅当用户本轮显式传入 `--resume` 时执行**；阶段结束后不得自行停会话或建议 `--resume`。

### 本工作流 phase 映射

| phase | 技能 | 产出物（NN- 前缀） | 标记类型 |
|---|---|---|---|
| 1 | ss-diag-rootcause [HARD-GATE] | `01-rootcause.md` | phase |
| 2 | ss-tdd-cycle | `02-test-cases.md` + 测试/实现代码 | phase |
| 3 | ss-code-review | `03-code-review.md` | phase |

## 复用来源
`ss-diag-rootcause / ss-tdd-cycle / ss-code-review` 均为跨工作流共享技能。
