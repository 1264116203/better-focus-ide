---
name: ss-analysis-intake
description: 需求澄清与拆解。通过 brainstorming 式提问澄清意图、边界与约束，只回答"做什么"不涉及技术选型。独立可用，也是 wf-feature-* 的入口技能。
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion
---

# ss-analysis-intake — 需求澄清与拆解

**阶段**: analysis | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 有一段需求描述、PRD 路径或 Confluence pageId。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `slug.*` → slug 格式校验（pattern/min_length/max_length/auto_generate）
- `workflow_dir.active` → 产物写入路径（wf-feature-* 使用）
- `workflow_dir.prd_split` → wf-prd-split 专用路径模板
- `profile.default` → 缺省 profile（basic/enhanced）

工作流模式下，**PRD_DIR**（原始 PRD 文件所在目录）由编排器通过上下文传入。未完成配置加载不得开始执行。

## 输入
- `--slug <feature-slug>`（可选，缺省自动生成；格式规则见 `wf-dev.yaml` 中 `slug.*` 配置）
- 需求来源（需求文本 / PRD 路径 / Confluence pageId）由用户在 prompt 中给出
- 若存在 `01-visual-notes.md`（Phase 1 产物，按 orchestrator「跨阶段文件解析协议」定位）→ 作为视觉上下文输入；不存在则按无视觉产物正常执行。

## 执行步骤
1. 读取需求来源；若为 Confluence/PRD，加载全文与附件。
2. 【铁律·先问后写】**必须**使用 AskUserQuestion 与用户完成澄清提问，**禁止跳过提问直接生成 intake.md**：
   - 按 brainstorming checklist（意图/用户/场景/边界/约束/成功标准）逐项提问，每轮 ≤4 个问题，选项需含"其他"兜底。
   - basic：至少 3-5 个关键问题；enhanced：完整 checklist + 干系人/风险。
   - 即使需求描述/PRD 看似完整（信息可推断），**也必须至少进行一轮 AskUserQuestion 确认**关键决策点（范围/边界/成功标准），不得以"信息已足够"为由跳过交互。
   - 用户答复含未确认点或选择继续澄清 → 追加提问，直至无阻断性未确认点。
   - 【视觉存疑点优先】若 `01-visual-notes.md` 存在，**必须**将其「存疑点清单」中的 `⚠️待确认` 项纳入 AskUserQuestion 提问；已确认的视觉事实（流程分支/UI 字段/多端差异等）写入 intake.md 的"已确认范围"，并**用相对链接引用** `01-visual-notes.md` 对应锚点，禁止复述图内容。
3. 汇总澄清结果，显式记录"已确认范围"与"暂不做（out-of-scope）"。
4. 写逻辑名 `intake.md`（**必含「澄清记录」段**：提问清单 + 用户答复要点）；路径规则：wf-prd-split 工作流写入 `PRD_DIR/processing-state/`，wf-feature-* 工作流写入 WORKFLOW_DIR 根目录，独立调用写入当前工作目录。编排器 resolver 再加 `NN-` 前缀（拆分场景为 `01-intake.md`）。PRD_DIR 由编排器上下文传入。

## 输出
- `01-intake.md`：问题清单、已确认范围、out-of-scope、初步验收要点。

## 完成标准 (Done)
- 【澄清证据】intake.md 含「澄清记录」段且非空（记录了 AskUserQuestion 提问清单与用户答复要点）；**无澄清记录 → 判定未完成**，回退重新提问。
- 无阻断性未确认点；范围与 out-of-scope 明确记录。

## basic vs enhanced
- basic：3-5 个关键澄清问题，轻量记录。
- enhanced：完整 checklist + 干系人/风险，产出结构化 intake.md。

## 异常处理
- 需求源不可读或信息严重不足 → 标 BLOCKING，回退用户补充。
