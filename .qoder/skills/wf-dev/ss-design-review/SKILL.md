---
name: ss-design-review
description: 设计评审（两级）。先审完整性（够不够），再审跨文档一致性（好不好），顺序不可颠倒。作为进入开发前的 HARD-GATE。可独立评审任意设计文档。
allowed-tools: Read, Grep, Glob, Write
---

# ss-design-review — 设计评审（两级）

**阶段**: design | **独立可用**: 不推荐独立调用 | **profile**: enhanced（basic 可简化为单遍）

## 前置条件
- 有 design.md、spec.md、tasks.md。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `hard_gates.design_review` → HARD-GATE 触发条件、回退路径、适用工作流
- `workflow_dir.active` → 产物写入路径（`design-review.md`）

未读取配置文件不得开始执行。

## 输入
- `--slug <feature-slug>`
- 工作流模式下自动读取 `WORKFLOW_DIR/design.md`、`WORKFLOW_DIR/spec.md`、`WORKFLOW_DIR/tasks.md`

## 执行步骤
1. **第一级 完整性审查**：设计是否覆盖 spec 全部功能点/非功能需求？缺口→列出。判定 DESIGN_APPROVED / BLOCKING。
2. 第一级通过后，**第二级 一致性审查**：design/api-spec/ddl/tasks 之间是否一致（字段、错误码、命名、依赖）？判定 CONSISTENCY_APPROVED / BLOCKING。
3. 写 `design-review.md`（直接写入 WORKFLOW_DIR 根目录，与 code-review.md / security-scan.md 保持一致），给出逐条问题与级别。

## 输出
- `design-review.md`（两级结论 + 问题清单）。

## 完成标准 (Done)
- 两级均 APPROVED 方可进入开发（HARD-GATE）。

## basic vs enhanced
- basic：单遍完整性检查即可放行。
- enhanced：**并行**派发 `@design-completeness-reviewer-subagent` 与 `@cross-doc-consistency-reviewer-subagent`；各自独立会话、写逻辑名 `design-review-1.md` / `design-review-2.md`，互不读取对方结论；主 agent 只汇总不评判，编排器 resolver 加 `NN-` 前缀后合并写 `design-review.md`。派发传参协议见 `orchestrator-behavior.md` → "enhanced 模式 subagent 派发协议"。

## 异常处理
- 任一级 BLOCKING → 不放行，回退 ss-design-tech / ss-design-plan 修订后重审。
