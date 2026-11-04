---
name: ss-code-review
description: 双轴代码审查——Standards（规范合规）+ Spec（是否满足需求）。依据 review-checklist.md 对 diff/PR 逐条评审并分级问题。可独立审查任意 diff/PR。
allowed-tools: Read, Bash, Grep, Glob, Write
---

# ss-code-review — 双轴代码审查

**阶段**: review | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 有可审查的 diff/PR/分支；按「规则依赖」读取审查检查单与编码/技术栈规则。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → 产物写入路径

未读取配置文件不得开始执行。

## 规则依赖（按需读取）
执行前按需 Read（路径以 `.qoder/` 为基准，缺失则跳过）：
- `wf-rules/review-checklist.md` — 双轴审查检查单（Standards 轴依据）
- `wf-rules/coding-standards.md` + `wf-rules/coding-standards-<stack>.md` — 编码规范（按项目技术栈）
- `wf-rules/tech-stacks/` — 技术栈规则（按项目技术栈读取对应子目录）

## 输入
- `--slug <feature-slug>`（可选，用于 Spec 轴对照 `WORKFLOW_DIR/spec.md`）
- 审查目标（diff ref / PR / 分支）由用户 prompt 给出

## 执行步骤
0. **【模式分支·强制】** 执行前先确认 profile：
   - **enhanced**：**禁止主 agent 直接执行审查**，必须按 `orchestrator-behavior.md` → "enhanced 模式 subagent 派发协议"**并行**派发 `spec-reviewer-subagent`（Spec 轴）与 `code-reviewer-subagent`（Standards 轴），各自独立产出逻辑名 `review-spec.md` / `review-standards.md`；主 agent 只汇总不评判，编排器 resolver 加前缀后合并写 `code-review.md`。
   - **basic**：单遍双轴审查（下方步骤 1-4）。
1. 获取 diff（`git diff`/PR），通读改动范围。
2. **Spec 轴**：对照 spec/验收标准，检查是否满足需求、有无超范围。
3. **Standards 轴**：对照 review-checklist.md（分层/命名/性能/安全/校验/测试）。
4. 逐条问题标注 文件:行号 + 级别(BLOCKING/WARNING/建议) + 修复建议，写 `code-review.md`。

## 输出
- `code-review.md`（分级问题清单 + 结论 APPROVED/CHANGES_REQUESTED）。

## 完成标准 (Done)
- 覆盖两轴；结论基于 diff 与测试证据，不采信作者自述。
- BLOCKING 与 WARNING 问题均须修复清零方可 APPROVED；仅「建议」级可保留不阻断。
- **enhanced**：`review-spec.md` 与 `review-standards.md` 两个 subagent 结论文件存在且非空；`code-review.md` 为两轴汇总（主 agent 未代审）。

## basic vs enhanced
- basic：单遍双轴审查。
- enhanced：**并行**派发 `@spec-reviewer-subagent`（Spec 轴）与 `@code-reviewer-subagent`（Standards 轴），独立会话、互不读取对方结论；各自写逻辑名 `review-spec.md` / `review-standards.md`；主 agent 只汇总不评判。派发传参协议见 `orchestrator-behavior.md` → "enhanced 模式 subagent 派发协议"。

## 异常处理
- 存在 BLOCKING 或 WARNING → CHANGES_REQUESTED，回退作者/ss-tdd-cycle 修复后复审，两者清零方可 APPROVED。
