---
name: ss-session-distill
description: 会话知识蒸馏。从当前 Qoder 会话的用户-模型对话中提取业务知识和技术知识，分类写入 knowledge/technologies/active/ 和 knowledge/requirements/active/ 暂存区，由对应的 update 工作流统一蒸馏到 global/。弥补用户未走 wf-dev / wf-dev-knowledge 流程时知识流失的缺口。
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion
---

# ss-session-distill — 会话知识蒸馏

**阶段**: util | **独立可用**: 是（推荐独立调用） | **profile**: basic/enhanced

## 定位

用户在 Qoder 会话中通过自然语言与模型沟通时，经常产生有价值的业务知识（领域规则、架构决策、配置约定、接口契约等），但这些知识不会自动沉淀到项目知识库中。本技能解决这一缺口：

```
对话中涌现的知识 ──→ ss-session-distill ──→ active/<slug>/ ──→ wf-dev-kb-update ──→ global/
```

**与 wf-dev-kb-update 的关系**：本技能只负责「提取 + 写入暂存区」，不直接修改 `global/`。写入的产物遵循 wf-dev 标准目录结构，`workflow-metrics.json` 标记其为"可蒸馏"状态，后续由 `wf-dev-kb-update`（technologies）或未来的 requirements update 工作流统一蒸馏。

## 前置条件

- 当前会话中存在用户与模型的有效对话内容（非空会话）。
- 项目根目录下存在 `.qoder/wf-dev.yaml` 配置文件。

## 配置加载

执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：

- `workflow_dir.active` → technologies 产物路径模板（`knowledge/technologies/active/sprint<YYMM>/<slug>`）
- `knowledge_base.business` → requirements 知识库路径（推导 active 路径：`knowledge/requirements/active/sprint<YYMM>/<slug>`）
- `knowledge_base.technology` → technologies 知识库路径
- `slug.*` → slug 格式校验（pattern/min_length/max_length/auto_generate）

未完成配置加载不得开始执行。

## 输入

- `--slug <session-slug>`（可选，缺省自动生成；基于对话主题推导，格式遵循 `wf-dev.yaml` 中 `slug.*` 配置）
- `--scope technologies|requirements|all`（可选，缺省 `all`；限定蒸馏范围）
- `--confirm`（可选，写入前逐条确认）

## 知识分类体系

### Technologies 域（写入 `knowledge/technologies/active/`）

| 领域 | 知识类型示例 | 产物文件名模式 |
|------|-------------|---------------|
| databases | 表结构设计、字段约束、索引策略、数据迁移方案 | `databases/{db-type}-{db-name}-ddl-design.md` |
| openapis | API 端点设计、请求/响应契约、错误码定义 | `openapis/restapi-{module}-design.md` |
| middlewares | 中间件配置决策、使用约束、连接策略 | `middlewares/{middleware-name}-config.md` |
| elasticsearch | 索引设计、mapping 变更、分词策略 | `elasticsearch/es-{index-name}-design.md` |
| diagrams | 业务流程、系统交互、状态机 | `diagrams/major-flow-{name}.puml` |

### Requirements 域（写入 `knowledge/requirements/active/`）

| 领域 | 知识类型示例 | 产物文件名模式 |
|------|-------------|---------------|
| domain-rules | 业务规则、领域概念、计算公式 | `domain-rules/{rule-name}.md` |
| constraints | 业务约束、合规要求、性能红线 | `constraints/{constraint-name}.md` |
| decisions | 架构决策、方案选型、trade-off 记录 | `decisions/{decision-name}.md` |
| glossary | 术语定义、缩写说明、领域词典 | `glossary/{term-group}.md` |

## 执行步骤

### Step 1：会话知识扫描

分析当前会话的完整对话上下文，识别具有持久化价值的知识条目。

**识别标准**（满足任一即为候选）：

- 用户明确陈述的业务规则或领域约束
- 对话中确认的技术方案或架构决策
- 用户纠正模型理解时透露的隐含知识
- 讨论中产生的接口契约、数据模型、配置约定
- 用户描述的系统间交互流程或状态流转

**排除标准**（以下内容不提取）：

- 纯操作性对话（"帮我写个函数"、"格式调整"）
- 通用编程常识（语言特性、框架标准用法）
- 已在 AGENTS.md 或 `global/` 中存在的重复内容
- 临时调试信息、一次性数据

### Step 2：知识分类与结构化

将候选知识按上方分类体系归类，每条知识生成结构化描述：

```yaml
- id: <序号>
  domain: technologies | requirements
  category: databases | openapis | middlewares | elasticsearch | diagrams | domain-rules | constraints | decisions | glossary
  title: <知识标题>
  summary: <一句话摘要>
  content: <结构化内容>
  source_context: <对话中的来源上下文摘要>
  confidence: high | medium | low
```

**confidence 判定**：

| 级别 | 条件 |
|------|------|
| high | 用户明确陈述且无歧义 |
| medium | 从对话推断，用户未明确否认 |
| low | 模型推测，需用户确认 |

### Step 3：用户确认

**必须**使用 AskUserQuestion 向用户展示提取结果并请求确认：

- 展示分类后的知识清单（id + title + summary + confidence）
- 用户可选择：全部确认 / 逐条确认 / 排除特定条目 / 补充修改
- `--confirm` 模式下逐条确认
- low confidence 条目**必须**经用户确认方可写入

### Step 4：产物写入

1. **生成 slug**（若未传入 `--slug`）：
   - 从对话主题提取 2-4 个核心关键词
   - 转为 kebab-case，校验 slug 正则
   - 追加 `-distill` 后缀以区别于开发工作流产物
   - 示例：`order-payment-distill`、`user-auth-distill`

2. **创建目录结构**：
   ```bash
   # Technologies（若有技术知识）
   mkdir -p knowledge/technologies/active/sprint<YYMM>/<slug>/processing-state

   # Requirements（若有业务知识）
   mkdir -p knowledge/requirements/active/sprint<YYMM>/<slug>/processing-state
   ```

3. **写入知识产物文件**：
   - 按分类体系中的文件名模式写入对应子目录
   - 每个文件必须包含元信息头：
     ```markdown
     <!-- session-distill: true -->
     <!-- distilled-at: <ISO8601_TIMESTAMP> -->
     <!-- source: qoder-session -->
     <!-- confidence: high|medium|low -->
     ```
   - 内容格式遵循 `dev-kb-content-standards.md` 的精简清晰原则

4. **写入蒸馏清单**（`distill-summary.md`）：
   ```markdown
   # 会话蒸馏清单

   蒸馏时间：<TIMESTAMP>
   来源：Qoder 会话对话
   Slug：<slug>

   ## Technologies 域
   | # | 领域 | 文件 | 标题 | confidence |
   |---|------|------|------|-----------|

   ## Requirements 域
   | # | 领域 | 文件 | 标题 | confidence |
   |---|------|------|------|-----------|

   ## 统计
   - 技术知识条目：N
   - 业务知识条目：N
   - 总计：N
   ```

### Step 5：标记为可蒸馏状态

对每个写入了产物的 active 目录，生成 `processing-state/workflow-metrics.json`：

```json
{
  "workflow": "ss-session-distill",
  "slug": "<slug>",
  "workflow_started_at": "<STEP1_STARTED_AT>",
  "workflow_completed_at": "<STEP5_COMPLETED_AT>",
  "workflow_duration": "<Xh Ym Zs>",
  "total_duration": "<Xh Ym Zs>",
  "phase_durations": { "1": "<Xh Ym Zs>" },
  "phases": {
    "1": {
      "phase_started_at": "<STEP1_STARTED_AT>",
      "phase_completed_at": "<STEP5_COMPLETED_AT>",
      "duration": "<Xh Ym Zs>",
      "outputs": ["distill-summary.md", "<产物文件列表>"]
    }
  }
}
```

> **关键**：`workflow-metrics.json` 的存在使 `wf-dev-kb-update` 的蒸馏源扫描能识别此 slug 为"开发已完成、产物就绪"，从而纳入待蒸馏清单。

同时写入 `processing-state/phase1-complete.md`：

```markdown
# Phase 1 Complete — 会话知识蒸馏

## OUTPUTS
- distill-summary.md
- <产物文件列表>

## Metrics
- phase_started_at: <TIMESTAMP>
- phase_completed_at: <TIMESTAMP>
- duration: <Xh Ym Zs>
```

### Step 6：去重校验

写入前**必须**执行去重校验：

1. 读取目标项目 `global/INDEX.md`（若存在）
2. 对每条待写入知识，检查 `global/` 对应目录下是否已有相同主题的文件
3. 已存在相同内容 → 跳过，记入 distill-summary.md 的「已跳过（重复）」段
4. 已存在但内容需更新 → 标记为 `update` 类型，产物文件中注明「本次为增量更新」
5. 不存在 → 标记为 `new` 类型，正常写入

## 输出

- `knowledge/technologies/active/sprint<YYMM>/<slug>/` — 技术知识产物（若有）
- `knowledge/requirements/active/sprint<YYMM>/<slug>/` — 业务知识产物（若有）
- 各目录下的 `distill-summary.md` — 蒸馏清单
- 各目录下的 `processing-state/workflow-metrics.json` — 可蒸馏标记
- 各目录下的 `processing-state/phase1-complete.md` — 完成标记

## 完成标准 (Done)

- 至少提取 1 条有效知识并经用户确认写入（若会话无有价值知识，明确告知用户"本次会话无可蒸馏知识"并正常结束）。
- `distill-summary.md` 已生成且内容与写入的产物文件一致。
- `processing-state/workflow-metrics.json` 已写入，格式符合 schema。
- 写入的产物文件含元信息头（`session-distill: true`）。
- 去重校验已执行，无与 `global/` 完全重复的产物。

## basic vs enhanced

| 行为 | basic | enhanced |
|------|-------|----------|
| 知识识别 | 仅提取 high confidence 条目 | 提取 high + medium，low 需确认 |
| 确认方式 | 展示清单一次性确认 | 逐条确认 + 允许补充修改 |
| 去重校验 | 文件名级去重 | 文件名 + 内容语义级去重 |
| 产物详细度 | 精简摘要 | 完整结构化内容 + source_context |

## 异常处理

- 会话无有价值知识 → 输出"本次会话无可蒸馏知识"，`STATUS: OK`，不创建目录。
- `.qoder/wf-dev.yaml` 不存在 → `STATUS: FAIL`，提示用户先安装 wf-dev 工作流。
- slug 与已有目录冲突 → 追加数字后缀（如 `order-distill-2`）。
- `global/INDEX.md` 不存在 → 跳过去重校验，记 WARNING，正常写入。
- 用户拒绝所有候选知识 → 同"无有价值知识"处理。
- 对话上下文过长无法完整分析 → 聚焦最近 N 轮对话（优先用户主动陈述的内容），记 WARNING。

## 后续流程提示

蒸馏完成后，向用户输出以下提示：

```
✅ 会话知识已写入暂存区：
  - Technologies: knowledge/technologies/active/sprint<YYMM>/<slug>/
  - Requirements: knowledge/requirements/active/sprint<YYMM>/<slug>/

📋 后续操作：
  - 技术知识：运行 /wf-dev-kb-update 将其蒸馏到 global/ 知识库
  - 业务知识：待 requirements update 工作流就绪后自动蒸馏
  - 也可运行 /wf-dev-kb-module --domain <领域> 单独处理某个技术领域
```
