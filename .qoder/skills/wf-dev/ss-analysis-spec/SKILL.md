---
name: ss-analysis-spec
description: 生成结构化规格（PRD + GWT 验收标准）。openspec 式可归档变更提案，只描述"做什么"，不含技术选型。可独立生成一份规格，也是设计阶段的输入。
allowed-tools: Read, Write, Grep, Glob
---

# ss-analysis-spec — 结构化规格生成

**阶段**: analysis | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 已有 `intake.md` 或明确需求描述。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → 产物写入路径
- `slug.*` → slug 格式校验

未读取配置文件不得开始执行。

## 输入
- `--slug <feature-slug>`
- 工作流模式下自动读取 `WORKFLOW_DIR/intake.md`；独立调用时用户可在 prompt 中指定需求来源

## 执行步骤
1. 读取 intake/需求，提炼业务目标与用户故事。
   - 【引用约束】需求来源追溯用 ID/链接引用 intake（如 `参见 01-intake.md §需求清单`），**禁止复制** intake 原文。
2. 编写规格三段：需求来源追溯 / 业务提案 / 产品需求（功能点列表）。
3. 为每个功能点写 GWT 验收标准（Given-When-Then）。
4. 显式标注 out-of-scope 与非功能需求（性能/安全/兼容）。
5. 写 `spec.md` 到 WORKFLOW_DIR（路径由 `workflow_dir.active` 配置决定）。
   - 【单一事实源】spec 是本阶段唯一权威；后续阶段（domain/design）引用本文件内容时必须用相对链接，不得复述——详见 ss-analysis-domain / ss-design-tech 同名约束。
   - 【视觉引用】涉及流程/UI 行为的功能点与 GWT，若 `01-visual-notes.md` 存在，用相对链接引用其对应图锚点（如 `参见 01-visual-notes.md §图1`），禁止复述图中已提取内容。

## 输出
- `spec.md`：可归档的变更提案 + 逐条 GWT 验收标准。

## 完成标准 (Done)
- 每个功能点均有可测试的 GWT；无技术实现细节混入。

## basic vs enhanced
- basic：合并轻量 spec，仅核心功能点 + 验收。
- enhanced：完整三段结构 + 非功能需求 + 干系人签核位。

## 异常处理
- 与 intake 范围冲突 → 回退 ss-analysis-intake 重新澄清。
