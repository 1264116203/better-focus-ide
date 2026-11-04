---
name: wf-feature-large
description: 大型新功能工作流（复杂业务/多模块交互）。端到端编排从需求澄清到发布归档，默认 enhanced。满足 Mode A 分流条件时使用。编排器只调度技能，不写业务代码。
---

# wf-feature-large — 大型新功能

**适用场景**：Mode A（新表/新模块/≥3 层/新跨层 API/新领域实体/有 PRD/>200 行，满足任意 2 项）。
**默认 profile**：enhanced。
**调用**：`/wf-feature-large "需求描述" [--profile enhanced] [--resume] [--slug xxx]`

> **参数说明**：`--profile`、`--resume`、`--slug` 为文档约定参数，由 AI 解读并执行对应行为，非 Qoder 框架原生支持。

## 配置加载（执行前必做，第一步）

工作流启动时，**必须首先**按 `orchestrator-behavior.md` → "配置加载"：① Read `.qoder/wf-dev.yaml`；② 计算产物目录并 `mkdir -p .../processing-state`。**禁止**采集 `WORKFLOW_STARTED_AT`，**禁止**创建或写入 `workflow-metrics.json`（该文件仅由终点 `ss-util-tracker --aggregate` 根据各 `phaseN-complete.md` 生成）。未完成配置加载不得调用任何技能。

## 包含技能与执行顺序

```
 1. ss-analysis-visual      [条件触发] PRD 图片语义提取 → 01-visual-notes.md（无图/模型不支持多模态则静默跳过，不阻断）
 2. ss-analysis-intake      需求澄清 → 02-intake.md
    └─ 【强制澄清·先问后写】必须用 AskUserQuestion 提问后才可写 intake.md（即使需求看似完整也须至少一轮确认）；intake.md 必含「澄清记录」段，缺失视为未完成
 3. ss-analysis-spec        规格+GWT → 03-spec.md / 03-test-cases.md
 4. ss-analysis-domain      领域建模 → 04-domain.md
 5. ss-design-tech          技术设计 → 05-design.md / 05-api-spec.yaml / databases/05-*-ddl.sql
 6. ss-design-plan          任务拆分 → 06-plan.md / 06-tasks.md
    └─ 【铁律·拆分约束】任务总数（`实现` + `配置`）上限 3 个，超出必须按 ss-design-plan →「合并策略」合并；每个任务须具备完整功能边界（高内聚），禁止将同一业务逻辑强行拆碎。
    └─ 【编排器门禁·任务数校验】ss-design-plan 完成后，编排器必须检查 06-tasks.md 中任务总数（`实现` + `配置`）≤ 3；超标则拒绝进入下一阶段，回退 ss-design-plan 重新拆分。
 7. ss-design-review  [HARD-GATE: design_review] 两级评审 → 07-design-review.md
    └─ 未 APPROVED 不进开发
    └─ 【铁律·enhanced 模式 subagent 派发】本阶段为审查类环节，enhanced profile 下**必须并行派发 subagent**，禁止主会话代审：
       1. 同时派发 @design-completeness-reviewer-subagent 与 @cross-doc-consistency-reviewer-subagent（独立会话，互不读对方结论）→ 分别写逻辑名 `design-review-1.md` / `design-review-2.md`
       2. 编排器 resolver 重命名为 `07-design-review-1.md` / `07-design-review-2.md`，汇总为 `07-design-review.md`（禁止自行评判，只汇总）
       3. 编排器自检：两份结论文件存在且非空，缺失则回退重派
 8. 逐 task: ss-tdd-cycle（串行逐任务执行，每个 task 必须先写测试再写实现 → 08-test-cases.md）
    └─ 【任务数上限】本阶段执行的任务总数（`实现` + `配置`）由阶段 6 控制，上限 3 个。编排器在阶段 6 完成时已校验，此处不再重复计数。
    └─ 【配置任务批量先行】本阶段开始时，先一次性批量执行 tasks.md 中全部 `配置` 类 task（跳过 TDD 循环，每 task 立即写完成标记并注明跳过原因），再进入 `实现` task  TDD 循环。
    └─ 【代码生成唯一来源】本阶段为唯一代码生成阶段：分层类/接口、DDL、映射、配置与全部业务实现均在本阶段按 task 产出（红阶段按需创建类与方法签名，无独立骨架阶段）。
    └─ 【铁律·串行执行】本阶段主会话串行逐 task 执行，禁止批量补写 task 标记——每 task 完成立即写 processing-state/phase8-task<K>-complete.md。实现类环节一律串行，禁止派发 subagent 并行执行。
    └─ 【铁律】每个 task 完成时必须同时产出：实现代码 + 对应单元测试文件。无测试的 task 视为未完成，禁止写 task 完成标记。
    └─ 仅纯配置类 task（无可测业务逻辑，如 DDL/映射/配置文件）可降级为直接实现（跳过 TDD 循环），但须在 task 完成标记中注明原因。
 9. ss-test-run             执行+覆盖率 → 09-test-result.md
10. ss-code-review          双轴审查 → 10-code-review.md
11. ss-util-tracker --aggregate 度量聚合 → processing-state/workflow-metrics.json
```

> **产出物命名规范**：遵循 `orchestrator-behavior.md` → "产出物序号前缀规范"。

每阶段结束由 `ss-util-tracker --mark` 写完成标记，然后继续下一阶段。

> **铁律（标记即原子）**：遵循 `orchestrator-behavior.md` → "标记即原子铁律"。

## Phase 计时

每个 phase 把起止时间与时长写入 `processing-state/phaseN-complete.md` Metrics（`phase_started_at` / `phase_completed_at` / `duration`），**不**写 `workflow-metrics.json`。

工作流级汇总仅在步骤 11：`ss-util-tracker --aggregate` **先读**全部 `phaseN-complete.md`，再生成 `processing-state/workflow-metrics.json`。

## 步骤确认机制

编排器在**每个关键步骤执行前**必须：
1. **汇总变更**：列出从工作流启动到当前步骤为止已完成的所有步骤及其产物（文件/结论/状态变更）。
2. **请求确认**：向用户展示下一步即将执行的技能名称与预期行为，等待用户明确确认后再继续。
3. **选项呈现**：严格遵循 `orchestrator-behavior.md` → “确认交互约束（防幻觉铁律）”。

关键步骤定义：本工作流中编号 1-11 的每个技能调用均为关键步骤。

## 关键节点
- **步骤 7（设计评审）** 为 HARD-GATE（见 `wf-dev.yaml → hard_gates`），未过不得前进。
- **步骤 8（逐 task 实现）** 为代码生成起点，遵循 `orchestrator-behavior.md` →「`yall` 代码生成检查点」——用户选择 `yall` 时，编排器必须在本步骤执行前暂停，汇总中间产物待用户审计确认后继续。含内嵌门禁：每个 task 完成标记写入前，编排器必须验证该 task 对应的单元测试文件已存在（在项目测试目录下可找到对应测试文件，路径按技术栈约定：Java `src/test/`、Python `tests/`、JS/TS `__tests__/` 或 `*.test.*`、Go `*_test.go`、其他按项目惯例）。验证失败 → 该 task 视为未完成，回退执行 ss-tdd-cycle 补齐测试。**步骤 8 主会话串行执行，禁止派发 subagent**；`配置` 类 task 按「配置任务批量先行」一次性执行，不进入 TDD 循环。
- **步骤 10（双轴审查）** 存在 BLOCKING 或 WARNING 时不得前进，按「异常处理（修复回环）」执行修复后重审。

## 异常处理（修复回环）

- 步骤 7（设计评审）BLOCKING → 按 `hard_gates.design_review` 回退 `ss-design-tech` / `ss-design-plan` 修订后重审。
- 步骤 9/10 出现 FAIL/BLOCKING →
  `ss-diag-rootcause`（定位根因）→ `ss-tdd-cycle`（修复+回归测试）→ 重跑失败步骤。
- 按 `escalation` 规则：同一根因修复 **3 次**仍失败 → 暂停，回 `ss-design-tech` 复审架构。
- 任一角色执行失败重试 ≤2 次后标 BLOCKED 并上报编排器。

## --resume 续跑协议

遵循 `orchestrator-behavior.md` → "--resume 续跑协议"。**仅当用户本轮显式传入 `--resume` 时执行**；阶段结束后不得自行停会话或建议 `--resume`。

### 本工作流 phase 映射

| phase | 技能 | 产出物（NN- 前缀） | 标记类型 |
|---|---|---|---|
| 1 | ss-analysis-visual [条件] | `01-visual-notes.md`（跳过时注明原因） | phase(条件) |
| 2 | ss-analysis-intake | `02-intake.md` | phase |
| 3 | ss-analysis-spec | `03-spec.md`、`03-test-cases.md` | phase |
| 4 | ss-analysis-domain | `04-domain.md` | phase |
| 5 | ss-design-tech | `05-design.md`、`05-api-spec.yaml`、`databases/05-*` | phase |
| 6 | ss-design-plan | `06-plan.md`、`06-tasks.md` | phase |
| 7 | ss-design-review [HARD-GATE] | `07-design-review.md` | phase |
| 8 | 逐 task: ss-tdd-cycle（每 task 必须含单元测试） |  `08-test-cases.md` + 测试/实现代码 | **task** |
| 9 | ss-test-run | `09-test-result.md` | phase |
| 10 | ss-code-review | `10-code-review.md` | phase |
| 11 | ss-util-tracker --aggregate | `processing-state/workflow-metrics.json` | phase |

## 复用来源
本工作流全部技能均可独立调用；`ss-tdd-cycle / ss-code-review / ss-util-*` 与其他工作流共享。
