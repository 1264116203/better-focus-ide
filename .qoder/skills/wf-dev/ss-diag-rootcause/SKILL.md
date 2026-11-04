---
name: ss-diag-rootcause
description: 系统化调试定位根因。四阶段（复现→缩小→定位→验证假设）找出真正原因，不猜测不乱改。铁律：无根因不修复。可独立用于任意 bug/测试失败/异常行为。
allowed-tools: Read, Bash, Grep, Glob, Write
---

# ss-diag-rootcause — 系统化根因定位

**阶段**: diag | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 有可观察的现象：报错、失败测试或异常行为。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `hard_gates.rootcause` → HARD-GATE 触发条件（未定位根因不进入修复）
- `escalation` → 同一根因多次修复失败的升级规则
- `workflow_dir.active` → 产物写入路径（`rootcause.md`）

未读取配置文件不得开始执行。

## 输入
- `--slug <feature-slug>`（可选）
- 现象描述 / 报错日志 / 失败测试名由用户 prompt 给出

## 执行步骤
1. **复现**：写出稳定复现步骤或失败测试（作为回归测试）。
2. **缩小**：二分/隔离，收敛到最小触发范围。
3. **定位**：读代码与运行时数据，形成根因假设并用证据验证（非猜测）。
4. **确认**：证明"改这里就好、还原就坏"，记录根因与建议修复。

## 输出
- `rootcause.md`（复现步骤 + 根因 + 修复建议 + 回归测试）。

## 完成标准 (Done)
- 根因有证据支撑，非表象；附可复现失败测试。

## basic vs enhanced
- basic：核心根因定位。
- enhanced：根因 + 防御纵深（同类问题排查）+ 回归测试落地。

## 异常处理
- 无法复现 → 收集更多观测数据，不得凭猜测提交修复。
