---
name: wf-prd-split
description: 需求分解工作流（预工作流阶段）。将大型 Epic/需求拆分为可独立交付的工作流实例（wf-feature-large / wf-feature-small），产出结构化拆分报告供人工评审。评审通过后用户按依赖顺序逐项启动对应工作流。
---

# wf-prd-split — 需求分解

**适用场景**：大型 Epic/需求需要拆分为多个可独立交付的工作流实例时使用。
**调用**：`/wf-prd-split "Epic 描述或 Story 列表" [--resume] [--slug xxx]`

> **参数说明**：`--resume`、`--slug` 为文档约定参数，由 AI 解读并执行对应行为，非 Qoder 框架原生支持。

## 配置加载（执行前必做，第一步）

工作流启动时，**必须首先**按 `orchestrator-behavior.md` → "配置加载"：① Read `.qoder/wf-dev.yaml`；② 计算 PRD_DIR（原始 PRD 文件所在目录），`mkdir -p PRD_DIR/processing-state`。本工作流**不使用** `WORKFLOW_DIR`（不再写入 `knowledge/technologies/` 目录树）。**禁止**采集 `WORKFLOW_STARTED_AT`，**禁止**写入 `workflow-metrics.json`（仅终点 `--aggregate` 根据 `phaseN-complete.md` 生成）。

未完成配置加载不得调用任何技能。

## 包含技能与执行顺序

```
1. ss-analysis-visual      [条件触发] Epic PRD 图片语义提取 → PRD_DIR/processing-state/01-visual-notes.md（无图时注明跳过原因）
2. ss-analysis-intake      澄清 Epic 范围、确认拆分约束（必须先 AskUserQuestion 提问，禁止跳过） → PRD_DIR/processing-state/02-intake.md
3. ss-analysis-split       三阶段拆分引擎 → PRD_DIR/processing-state/03-split-result.md
4. ss-analysis-report      生成结构化报告 → PRD_DIR/processing-state/04-split-report.md
5. ss-analysis-sub-doc     生成子需求文档 → PRD_DIR/<NNN>-<slug>/<NNN>-<slug>.md（每个拆分项一份，与原始 PRD 同级）
```

每阶段结束由 `ss-util-tracker --mark --started-at <ISO8601_TIMESTAMP>` 写完成标记（时序采集遵循 `orchestrator-behavior.md` → "时序数据采集协议"）。

> **铁律（标记即原子）**：遵循 `orchestrator-behavior.md` → "标记即原子铁律"。

## 产物目录约定

产物按类型均存放于 PRD_DIR（原始 PRD 文件所在目录，如 `knowledge/requirements/active/sprint<YYMM>/<epic-slug>/`），不再区分 WORKFLOW_DIR：

```
PRD_DIR/
├── <epic-slug>.md                 # 原始 PRD 文件（拆分输入，非本工作流产物）
├── processing-state/                  # 中间状态文件（与原始 PRD 同级存放）
│   ├── 01-visual-notes.md         # Phase 1 产物（跳过时注明原因）
│   ├── 02-intake.md               # Phase 2 产物
│   ├── 03-split-result.md         # Phase 3 产物
│   ├── 04-split-report.md         # Phase 4 产物（总报告）
│   └── phaseN-complete.md         # 阶段完成标记
├── 101-<slug>/                    # Phase 5 产物（子需求文档，3位序号，与原始 PRD 同级）
│   └── 101-<slug>.md
├── 102-<slug>/
│   └── 102-<slug>.md
└── NNN-<slug>/
    └── NNN-<slug>.md
```

**规则**：
- **中间状态文件**（02-intake.md、03-split-result.md、04-split-report.md、phase*-complete.md）写入 `PRD_DIR/processing-state/`
- **子需求文档**（`<NNN>-<slug>/<NNN>-<slug>.md`）写入 `PRD_DIR/` 下独立子目录，与原始 PRD 文件同级（不再写入 `knowledge/technologies/` 下的 WORKFLOW_DIR）
- 配置加载时需 `mkdir -p PRD_DIR/processing-state` 确保 `processing-state/` 子目录存在
- `--resume` 扫描断点时在 `PRD_DIR/processing-state/` 下查找 phase*-complete.md

## 子需求文档内容铁律（Phase 5 强制）

步骤 5（`ss-analysis-sub-doc`）生成的每份子需求文档（如 `101-<slug>.md`、`102-<slug>.md`、`103-<slug>.md`）**必须**满足以下三条，缺一即视为该拆分项未完成：

1. **细节完整回溯**：必须包含该拆分项对应的**所有** Story 在原始 PRD 中出现的全部细节（功能描述、字段定义、业务规则、展示信息、边界/异常场景等），禁止摘要式转述导致细节丢失，开发者无需回看原始 PRD 即可完整理解需求。
2. **图片与 HTML 原型文件全量携带**：原始 PRD 中与本拆分项相关的**每一张**图片（Markdown `![]()` + HTML `<img>` 两种格式）以及**每一个** HTML 原型/附件文件链接（如 `<iframe>`、指向 `.html`/`.htm` 的原型预览链接）都必须出现在对应子需求文档中，链接路径经重新计算并用 `test -f` 验证可达（具体提取与验证步骤见 `ss-analysis-sub-doc` SKILL.md）。
3. **依赖子 PRD 显式引用**：若该拆分项依赖其他子 PRD（依赖关系来自 `split-result.md`），文档必须：
   - 在元信息「前置依赖」字段与正文「8. 推荐执行顺序与依赖说明」中显式写出被依赖的子 PRD 标题与**可跳转的 Markdown 相对链接**（如 `[101-<dep-slug>](../101-<dep-slug>/101-<dep-slug>.md)`），不能只写编号或名称；
   - 正文对应依赖点必须包含明确的「参考/先阅读该子 PRD」提示语（如「⚠️ 本需求依赖 [101-<dep-slug>](../101-<dep-slug>/101-<dep-slug>.md)，开发前请先阅读该子需求文档」）；
   - 链接指向的路径需经 `test -f` 验证可达（依赖文档可能尚未生成时降级为 WARNING 并在文档内注明「待生成后校验」，不阻断本拆分项产出）。

> 以上三条由 `ss-analysis-sub-doc` 的「完成校验」步骤逐条验证；编排器在 Phase 5 标记前需确认校验结论为 PASS，否则视为该阶段未完成，不得写 `phase5-complete.md`。

## 步骤确认机制

编排器在**每个关键步骤执行前**必须：
1. **汇总变更**：列出从工作流启动到当前步骤为止已完成的所有步骤及其产物（文件/结论/状态变更）。
2. **请求确认**：向用户展示下一步即将执行的技能名称与预期行为，等待用户明确确认后再继续。
3. **选项呈现**：严格遵循 `orchestrator-behavior.md` → "确认交互约束（防幻觉铁律）"。

关键步骤定义：本工作流中编号 1-5 的每个技能调用均为关键步骤。

## 关键节点
- 本工作流**无 HARD-GATE**（拆分报告是建议性的，供人工评审，不阻断后续流程）。
- 步骤 3 为核心拆分引擎，产出质量直接决定报告可用性。

## 异常处理

- 步骤 2（intake）BLOCKING（信息严重不足）→ 暂停工作流，要求用户补充 Epic/Story 信息。
- 步骤 3（decompose）某拆分项 BLOCKING → 标 WARNING 继续处理其余项，最终报告中注明"待补充"。
- 步骤 3（decompose）依赖环检测 → 暂停，列出环路径，要求用户确认优先级打破环。
- 按 `escalation` 规则：同一问题重试 **2 次**仍失败 → 标 BLOCKED 上报用户。

## --resume 续跑协议

遵循 `orchestrator-behavior.md` → "--resume 续跑协议"。**仅当用户本轮显式传入 `--resume` 时执行**；阶段结束后不得自行停会话或建议 `--resume`。

### 扫描目录差异化
- 本工作流的完成标记位于 `PRD_DIR/processing-state/`（非 WORKFLOW_DIR），`ss-util-tracker --resume` 需按此路径扫描。
- **【中文路径回退 — 强制】** PRD 目录名常含中文字符，断点扫描**必须**以 `Bash`（`find PRD_DIR/processing-state -maxdepth 1 -name "phase*-complete.md"`）为主手段或 Glob 的二次验证，以 Bash 结果为准。

### 本工作流 phase 映射

| phase | 技能 | 标记类型 |
|---|---|---|
| 1 | ss-analysis-visual [条件] | phase(条件) |
| 2 | ss-analysis-intake | phase |
| 3 | ss-analysis-split | phase |
| 4 | ss-analysis-report | phase |
| 5 | ss-analysis-sub-doc | phase |

## 与后续 wf-* 的衔接

报告评审通过后，用户按依赖顺序逐项调用：
- `/wf-feature-large "子任务描述 + GWT" --slug <child-slug>`
- `/wf-feature-small "子任务描述 + GWT" --slug <child-slug>`

每个子任务有独立 slug 和独立 WORKFLOW_DIR（该 WORKFLOW_DIR 是 `wf-feature-large` / `wf-feature-small` 自身运行时的产物目录，与本工作流产出的子 PRD 所在目录无关）。wf-prd-split 本身**不启动**后续工作流。

## 复用来源
- `ss-analysis-intake` 与 wf-feature-large / wf-feature-small 共享。
- `ss-analysis-split` / `ss-analysis-report` / `ss-analysis-sub-doc` 为本工作流新建，亦可独立调用。
