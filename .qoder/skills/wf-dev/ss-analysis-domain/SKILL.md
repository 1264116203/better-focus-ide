---
name: ss-analysis-domain
description: 领域建模与统一语言维护。识别核心概念、实体、关系与限界上下文，产出/更新术语表，为设计与编码提供一致语言。可独立用于梳理某模块领域模型。
allowed-tools: Read, Write, Grep, Glob
---

# ss-analysis-domain — 领域建模

**阶段**: analysis | **独立可用**: 不推荐独立调用 | **profile**: enhanced（basic 可跳过）

## 前置条件
- 有 spec.md 或现有代码可供分析。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → 产物写入路径
- `slug.*` → slug 格式校验

未读取配置文件不得开始执行。

## 输入
- `--slug <feature-slug>`
- 工作流模式下自动读取 `WORKFLOW_DIR/spec.md`；独立调用时用户可在 prompt 中指定目标模块

## 执行步骤
1. 从需求/代码中抽取名词与业务动作，识别核心实体与值对象。
2. 定义实体属性、关系（1:1/1:N/N:N）与聚合边界。
3. 标注限界上下文与跨上下文交互；补充/修订统一语言词表（含 Avoid 同义词）。
4. 写 `domain.md` 到 WORKFLOW_DIR（路径由 `workflow_dir.active` 配置决定）。
   - 【引用约束】实体/关系描述引用 spec 功能点时用相对链接（如 `参见 02-spec.md §功能点 F1`），**禁止复述** spec 已有内容；本文件只承载 spec 未覆盖的领域新内容（术语表、实体关系、上下文边界）。
   - 【视觉引用】实体/关系/状态建模可参考 `01-visual-notes.md` 中业务流程图与架构图的提取结果；引用时用相对链接（如 `参见 01-visual-notes.md §图2`），禁止复述。该产物不存在时正常跳过。

## 输出
- `domain.md`：术语表 + 实体关系 + 限界上下文。

## 完成标准 (Done)
- 术语无歧义；实体关系与 spec 一致；关键概念有唯一命名。

## basic vs enhanced
- basic：通常跳过（小改动无需建模）。
- enhanced：完整领域模型 + 统一语言更新。

## 异常处理
- 术语与现有项目术语冲突 → 标 WARNING，提请团队裁决后再落库。
