---
name: wf-feature-small
description: 小型功能工作流（单模块修改/简单增强）。轻量路径，跳过独立 spec/design 与两级审查，但守四条铁律。满足 Mode B 时使用。默认 enhanced。
---

# wf-feature-small — 小型功能

**适用场景**：Mode B（仅改已有代码 / ≤2 层 / ≤200 行 / 无正式 PRD，需全部满足）。
**默认 profile**：enhanced。
**调用**：`/wf-feature-small "需求描述" [--profile enhanced] [--resume] [--slug xxx]`

> **参数说明**：`--profile`、`--resume`、`--slug` 为文档约定参数，由 AI 解读并执行对应行为，非 Qoder 框架原生支持。

## 配置加载（执行前必做，第一步）

工作流启动时，**必须首先**按 `orchestrator-behavior.md` → "配置加载"：① Read `.qoder/wf-dev.yaml`；② 计算产物目录并 `mkdir -p .../processing-state`。**禁止**采集 `WORKFLOW_STARTED_AT`，**禁止**创建或写入 `workflow-metrics.json`（仅终点 `--aggregate` 根据 `phaseN-complete.md` 生成）。未完成配置加载不得调用任何技能。

## 包含技能与执行顺序

```
1. ss-analysis-visual  [条件触发] PRD 图片语义提取 → 01-visual-notes.md（Mode B 常无 PRD/无图 → 自动跳过）
2. ss-analysis-intake  轻量澄清（3-5 个关键问题，必须先 AskUserQuestion 提问再写 intake.md，禁止跳过） → 02-intake.md
3. ss-design-tech      轻量技术设计（enhanced 模式）→ 03-design.md + 按需产出物
4. ss-tdd-cycle        红-绿-重构实现 → 04-test-cases.md + 测试/实现代码
5. ss-code-review      双轴审查 → 05-code-review.md
```

> **产出物命名规范**：遵循 `orchestrator-behavior.md` → "产出物序号前缀规范"。

> **铁律（标记即原子）**：遵循 `orchestrator-behavior.md` → "标记即原子铁律"。

## Phase 计时

每个 phase 把起止时间与时长写入 `processing-state/phaseN-complete.md` Metrics（`phase_started_at` / `phase_completed_at` / `duration`）。全部阶段完成后调用 `ss-util-tracker --aggregate`，先读各标记再生成 `workflow-metrics.json`。

### 步骤 3 说明（轻量技术设计）

enhanced 模式下 `ss-design-tech` 产出完整：
- 必须产出 `03-design.md`（完整设计，含安全/降级章节）
- 涉及新增 API 时独立产出 `openapis/03-restapi-<module>.md`（API 契约独立文件）
- 涉及新增表时仍需独立 `databases/03-{db-type}-{db-name}-ddl.sql` + `databases/03-*-relation-{domain}.puml`
- 图表、中间件设计等按需产出物独立成文件（不合并附录）
- 模板加载与产出规则同 `ss-design-tech` SKILL.md 定义

## 步骤确认机制

编排器在**每个关键步骤执行前**必须：
1. **汇总变更**：列出从工作流启动到当前步骤为止已完成的所有步骤及其产物（文件/结论/状态变更）。
2. **请求确认**：向用户展示下一步即将执行的技能名称与预期行为，等待用户明确确认后再继续。
3. **选项呈现**：严格遵循 `orchestrator-behavior.md` → "确认交互约束（防幻觉铁律）"。

关键步骤定义：本工作流中编号 1-5 的每个技能调用均为关键步骤。

## 关键节点
- 步骤 3 为轻量技术设计（enhanced 模式），跳过独立 spec.md 与两级设计评审；范围仍以 intake 的"已确认范围"为准。
- 步骤 4（ss-tdd-cycle）为代码生成起点，遵循 `orchestrator-behavior.md` →「`yall` 代码生成检查点」——用户选择 `yall` 时，编排器必须在本步骤执行前暂停，汇总中间产物待用户审计确认后继续。

## 异常处理

- 实施中发现实为大改（触发 Mode A 条件）→ 升级为 `wf-feature-large`。
- 按 `escalation` 规则：同一根因修复 3 次仍失败 → 升级人工介入。

## --resume 续跑协议

遵循 `orchestrator-behavior.md` → "--resume 续跑协议"。**仅当用户本轮显式传入 `--resume` 时执行**；阶段结束后不得自行停会话或建议 `--resume`。

### 本工作流 phase 映射

| phase | 技能 | 产出物（NN- 前缀） | 标记类型 |
|---|---|---|---|
| 1 | ss-analysis-visual [条件] | `01-visual-notes.md`（跳过时注明原因） | phase(条件) |
| 2 | ss-analysis-intake | `02-intake.md` | phase |
| 3 | ss-design-tech | `03-design.md` + 按需产出物 | phase |
| 4 | ss-tdd-cycle | `04-test-cases.md` + 测试/实现代码 | phase |
| 5 | ss-code-review | `05-code-review.md` | phase |

## 复用来源
全部技能与 wf-feature-large / wf-bug-fix 共享。
