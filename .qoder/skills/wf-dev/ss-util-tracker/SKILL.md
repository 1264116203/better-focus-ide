---
name: ss-util-tracker
description: 工作流状态跟踪与度量管理。--mark 只写阶段完成标记（起止时间、duration、OUTPUTS），不写 workflow-metrics.json。--aggregate 读取全部 phaseN-complete.md 后生成工作流级汇总。统一存放于 WORKFLOW_DIR/processing-state/。一般由 wf- 内部调用。
allowed-tools: Read, Write, Bash, Glob
---

# ss-util-tracker — 状态跟踪与度量管理

**阶段**: util | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 存在 WORKFLOW_DIR（路径由 `workflow_dir.active` 配置决定）；执行状态文件统一存放于 `WORKFLOW_DIR/processing-state/`（完成标记；`workflow-metrics.json` 仅由 `--aggregate` 生成），与中间产物分离。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → WORKFLOW_DIR 路径模板
- `slug.*` → slug 格式校验

未读取配置文件不得开始执行。

## 输入

三种模式（互斥，每次调用只选一种；同时出现两个模式 flag → `STATUS: FAIL`）：

- **`--mark`**：`--slug <feature-slug> --mark <phase-id>`（必填 `--started-at <ISO8601_TIMESTAMP>`）。只写完成标记文件。
- **`--resume`**：`[--slug <feature-slug>] --resume`（断点定位扫描；slug 可选）。只读，不写文件。
- **`--aggregate`**：`--slug <feature-slug> --aggregate`（**先读**全部 `phaseN-complete.md`，再生成 `workflow-metrics.json` 工作流级汇总。此文件的**唯一写入者**）。

`--mark` 的 `<phase-id>` 必须匹配下方「标记命名规范」四种正则之一（如 `phase1`、`phase7-task2`），禁止只传数字 `1`。

> 所有时间戳统一格式：`date +"%Y-%m-%dT%H:%M:%S"`（本地时间，如 `2026-09-08T14:30:00`）。

## 标记命名规范（3 层封死）

所有标记文件统一存放于 `WORKFLOW_DIR/processing-state/`（wf-prd-split 为 `PRD_DIR/processing-state/`），下表文件名均相对该状态目录：

| 层级 | 文件名格式 | 说明 |
|---|---|---|
| L1 阶段 | `phase<N>-complete.md` | 阶段整体完成 |
| L2 任务 | `phase<N>-task<K>-complete.md` | phase 内第 K 个 task 完成 |
| L2 子流程实例 | `phase<N>-wf-<name>-<M>-complete.md` | 第 M 次子流程调用完成 |
| L3 子流程步骤 | `phase<N>-wf-<name>-<M>-step<S>-complete.md` | 子流程内第 S 步完成 |

**互斥规则**：
- 同一 phase 内 task 模式与 sub-wf 模式互斥。
- task 标记不可嵌套 step（`phaseN-task-K-step-*` 禁止）。
- sub-wf step 不可再嵌套（最大深度 = 3）。

**命名正则**：
```regex
^phase(\d+)-complete\.md$
^phase(\d+)-task(\d+)-complete\.md$
^phase(\d+)-wf-([a-z-]+)-(\d+)-complete\.md$
^phase(\d+)-wf-([a-z-]+)-(\d+)-step(\d+)-complete\.md$
```

## 执行步骤

### --mark 模式（只写完成标记）

写标记文件（OUTPUTS + 阶段起止时间）。由编排器在阶段推进协议步骤 8 调用。

1. `mkdir -p WORKFLOW_DIR/processing-state`（wf-prd-split 为 `PRD_DIR/processing-state/`），确保状态目录存在。
2. 校验 `--started-at` 已传入；缺失 → **整体失败**：不创建标记文件，返回 `STATUS: FAIL / BLOCKING_ISSUES: --started-at is required`，工作流不得推进。
3. 根据 `--mark` 参数值写对应标记文件（均位于 `processing-state/`）：
   - `--mark phase<N>` → 写 `phase<N>-complete.md`
   - `--mark phase<N>-task<K>` → 写 `phase<N>-task<K>-complete.md`
   - `--mark phase<N>-wf-<name>-<M>` → 写 `phase<N>-wf-<name>-<M>-complete.md`
   - `--mark phase<N>-wf-<name>-<M>-step<S>` → 写 `phase<N>-wf-<name>-<M>-step<S>-complete.md`
4. 标记文件内容：
   - **OUTPUTS 段**（**仅 L1 阶段标记必填**；L2/L3 禁止写 OUTPUTS——跨阶段查找只通过 L1）：
     ```
     ## OUTPUTS
     - 04-design.md
     - 04-api-spec.yaml
     - 04-databases/mysql-order-ddl.sql
     ```
   - **Metrics 段**（所有层级必填，**只允许**下列字段）：
     - `phase_started_at`：= `--started-at`（格式 `%Y-%m-%dT%H:%M:%S`），**禁止自行生成/伪造**
     - `phase_completed_at`：= 写标记时刻 `$(date +"%Y-%m-%dT%H:%M:%S")`
     - `duration`：= `phase_completed_at - phase_started_at` 实际秒差，转为 `Xh Ym Zs`（见下方转换规则）。负数（时钟回拨）填 `"0s"`，记 WARNING
     - **禁止**写入 `human_interaction` / `ai_duration` / 工作流级 `workflow_*` 字段

   > **时长格式**：`h = total / 3600`；`m = (total % 3600) / 60`；`s = total % 60`。省略零值段。示例：`5430` → `"1h 30m 30s"`；`325` → `"5m 25s"`；`45` → `"45s"`；`0` → `"0s"`。聚合回算秒数：`h*3600 + m*60 + s`。
5. **禁止**读取、创建或修改 `workflow-metrics.json`。阶段度量不在 mark 时落入 json；工作流级汇总只在 `--aggregate` 进行。
6. 写完标记后返回成功，由编排器继续下一阶段。本技能**不得**提示用户开新会话或使用 `--resume`。

### --aggregate 模式（读标记 → 写工作流汇总）

`workflow-metrics.json` 的**唯一写入点**。由编排器在工作流全部 L1 阶段标记写完后调用（如 wf-feature-large 步骤 10）。

1. **先扫描** `processing-state/phase<N>-complete.md`（只认 L1；忽略 task / sub-wf 文件）。按 N 升序读取每份 Metrics 的 `phase_started_at` / `phase_completed_at` / `duration` 与 OUTPUTS。
2. 无任何 L1 标记 → `STATUS: FAIL / BLOCKING_ISSUES: no phaseN-complete.md`，不写 json。
3. 由标记推导并**整文件生成** `processing-state/workflow-metrics.json`（覆盖已有文件，不依赖启动时预写头部）：
   - `workflow` / `slug`：来自编排器上下文与 `--slug`
   - `workflow_started_at`：各 L1 `phase_started_at` 的最早值
   - `workflow_completed_at`：本命令执行时 `date +"%Y-%m-%dT%H:%M:%S"`
   - `workflow_duration`：`workflow_completed_at - workflow_started_at`（秒差转 `Xh Ym Zs`）
   - `phases.<N>`：该阶段的 `phase_started_at` / `phase_completed_at` / `duration`（优先用标记里已写的 `Xh Ym Zs`；缺失则由起止时间重算）、`outputs`（取 OUTPUTS 列表）
   - `total_duration`：各阶段 `duration` 秒值之和，再转 `Xh Ym Zs`
   - `phase_durations`：各阶段 `duration` 列表
4. 某 L1 标记缺 `phase_started_at` 或 `phase_completed_at` → 该阶段 `duration` 填 `N/A`，记 WARNING，**不阻断**；`workflow_started_at` 忽略该阶段。缺 `duration` 但起止齐全 → 按起止重算写入 json。
5. **禁止**从标记或其它地方读取 `human_interaction` / `ai_duration`；json **不得**含这些字段。

#### 聚合校验规则
- `phase_started_at` > `phase_completed_at` → 该阶段 duration 填 `N/A`，记 WARNING
- `workflow_duration` 反向解析秒数 < 0 → N/A，记 WARNING
- 缺失单项不影响其余字段写入

### --resume 模式（断点定位扫描算法）

扫描范围为 WORKFLOW_DIR 下的 `processing-state/`（wf-prd-split 为 `PRD_DIR/processing-state/`）。**仅当用户显式传入 `--resume` 时**由编排器调用；阶段结束后禁止主动建议续跑。

```
1. 找最大 N 使 processing-state/phase<N>-complete.md 存在 → 断点在 phase N+1
2. 对断点 phase：
   a. 存在 processing-state/phase<N+1>-task-*-complete.md → task 模式，取最大 K，从 task K+1 续跑
   b. 存在 processing-state/phase<N+1>-wf-<name>-*-complete.md → 子流程模式：
      按 <name> 分组，每组内独立取最大 M：
      - 若 processing-state/phase<N+1>-wf-<name>-<M>-complete.md 存在 → 该 name 第 M 个已完成，从第 M+1 个开始
      - 若不存在 → 该 name 第 M 个未完成，深入扫描 step：
        取最大 S 使 processing-state/phase<N+1>-wf-<name>-<M>-step<S>-complete.md 存在 → 从 step S+1 续跑
      多 name 时，取各组中断点最靠前的（即最需要续跑的 name）优先推进
   c. 两者都不存在 → 从 phase N+1 第 1 步开始
```

若已存在 `workflow-metrics.json` 且含 `workflow_completed_at`，且最大 L1 N 已覆盖该工作流最后业务阶段 → 视为已完成，返回 `STATUS: OK / RESUME_POINT: complete`。

### slug 缺失处理

**仅 `--resume`**：未传 `--slug` 时，扫描 `knowledge/technologies/active/` 下所有子目录的 `processing-state/`，找出存在 `*-complete.md` 但工作流未全部完成的目录，列出未完成工作流清单（slug + 工作流类型 + 最后完成阶段），让用户选择。`--mark` / `--aggregate` 缺 `--slug` → `STATUS: FAIL`。

### workflow-metrics.json schema（仅 --aggregate 写入）

```json
{
  "workflow": "wf-feature-large",
  "slug": "order-export",
  "workflow_started_at": "2026-09-08T10:00:05",
  "workflow_completed_at": "2026-09-08T11:30:00",
  "workflow_duration": "1h 29m 55s",
  "total_duration": "1h 20m 10s",
  "phase_durations": { "1": "5m 25s", "2": "12m 00s" },
  "phases": {
    "1": {
      "phase_started_at": "2026-09-08T10:00:05",
      "phase_completed_at": "2026-09-08T10:05:30",
      "duration": "5m 25s",
      "outputs": ["01-intake.md"]
    }
  }
}
```

> `workflow_started_at` = 各 L1 标记 `phase_started_at` 最早值；`workflow_completed_at` / `workflow_duration` / `total_duration` / `phases` 全部在 `--aggregate` 由标记算出。`--mark` 不写此文件。

### 返回

**--mark 模式**：`STATUS: OK|FAIL / OUTPUTS: <标记文件路径> / BLOCKING_ISSUES: <问题列表或 none>`
- STATUS=OK：标记写入成功；Metrics 含起止时间与 `duration`；未改 json
- STATUS=FAIL：`--started-at` 缺失等，标记文件未创建

**--resume 模式**：`STATUS: OK|NO_WORKFLOW / RESUME_POINT: <phase N+1 / task K+1 / step S+1 / complete> / BLOCKING_ISSUES: <问题列表或 none>`

**--aggregate 模式**：`STATUS: OK|FAIL / OUTPUTS: processing-state/workflow-metrics.json / BLOCKING_ISSUES: <WARNING 列表或 none>`

## 输出
- `--mark`：完成标记文件。
- `--resume`：续跑定位结果。
- `--aggregate`：由标记生成的 `workflow-metrics.json`。

## 完成标准 (Done)
- **--mark**：标记与实际产物一致；Metrics 含 `phase_started_at` / `phase_completed_at` / `duration`（`Xh Ym Zs`）；**未**改 `workflow-metrics.json`；`--started-at` 缺失视为执行失败。
- **--resume**：能定位断点（精确到 task/step）；不因本技能调用而结束仍在进行的工作流。
- **--aggregate**：已读取全部 L1 `phaseN-complete.md` 后写入 json；不因单项缺失而阻断。
- 标记文件名符合命名正则，不符合的文件忽略并报告 WARNING。

## basic vs enhanced
- `--mark` Metrics 字段相同：`phase_started_at` / `phase_completed_at` / `duration`（`Xh Ym Zs`）。不再向标记追加 `retry_count` / `gate_result` / `issues_found` / `test_pass_rate`。

## 异常处理
- 标记与产物不一致（标记存在但产物缺失）→ 视为未完成，回退重跑该阶段。
- 标记文件名不符合命名正则 → 忽略该文件，输出 WARNING。
- WORKFLOW_DIR 不存在或无任何标记 → 报告"无可续跑工作流"，提示用户先启动工作流。
- active 目录下多个未完成工作流且未传 slug（仅 resume）→ 列出清单让用户选择，不自动推断。
- `--started-at` 缺失 → **整体失败**：不创建标记文件，返回 `STATUS: FAIL`，工作流不得推进。
- `duration` 为负数（系统时间回拨）→ 填 `"0s"`，记 WARNING，不阻断。
- `--mark` 写入了 `human_interaction` / `ai_duration` 或修改了 json → 视为执行缺陷。
- 某阶段标记缺起止时间（--aggregate）→ 该阶段 duration 填 N/A 继续，记 WARNING，不阻断交付。
