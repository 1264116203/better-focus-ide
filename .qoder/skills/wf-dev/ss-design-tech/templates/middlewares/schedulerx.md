# SchedulerX 定时任务设计 — {{feature_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及 SchedulerX 定时任务设计时按此结构填充 -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}}（对比 XXL-Job/Quartz：阿里云托管/可视化/DAG） |
| SchedulerX 版本 | {{schedulerx_version}} |
| 命名空间 | {{namespace}} |
| 应用分组 | {{app_group}} |

## 2. 架构设计

<!-- 指令: 使用 PlantUML 组件图描述任务调度架构，输出到 diagrams/ 目录 -->

```text
SchedulerX Console → SchedulerX Server → Worker({{service_name}}) → DB/MQ/Redis
```

## 3. 任务清单

<!-- 指令: 必须列出所有定时任务的完整定义 -->

| 任务名 | JobProcessor | 调度类型 | Cron/频率 | 超时(s) | 说明 |
|--------|-------------|----------|-----------|---------|------|
| {{job_1_name}} | {{processor_1}} | Cron | {{cron_1}} | {{timeout_1}} | {{desc_1}} |
| {{job_2_name}} | {{processor_2}} | 固定频率 | {{interval_2}} | {{timeout_2}} | {{desc_2}} |
| {{job_3_name}} | {{processor_3}} | 一次性 | {{trigger_time_3}} | {{timeout_3}} | {{desc_3}} |

**Cron 表达式说明**:

| 表达式 | 含义 |
|--------|------|
| {{cron_1}} | {{cron_1_meaning}} |
| {{cron_2}} | {{cron_2_meaning}} |

## 4. 分片策略

<!-- 指令: 如涉及分片任务，说明分片设计 -->

| 任务名 | 分片模型 | 分片数 | 分片参数 | 说明 |
|--------|----------|--------|----------|------|
| {{job_1_name}} | {{sharding_model}}（静态/动态） | {{shard_count}} | {{shard_param}} | {{desc}} |

**分片逻辑**:
```text
{{sharding_logic_description}}
```

## 5. 任务依赖 DAG

<!-- 指令: 如涉及多任务编排，使用 PlantUML 活动图描述 DAG -->

```text
{{job_dag_description}}
JobA → JobB → JobD
JobA → JobC → JobD
```

**DAG 规则**:
- 上游失败策略：{{upstream_failure_policy}}（阻塞下游 / 跳过继续）
- 自跳过策略：{{self_skip_policy}}

## 6. 失败重试策略

<!-- 指令: 必须定义每个任务的重试策略 -->

| 任务名 | 最大重试次数 | 重试间隔 | 失败告警 | 说明 |
|--------|-------------|----------|----------|------|
| {{job_1_name}} | {{retry_count_1}} | {{retry_interval_1}} | {{alert_1}} | {{desc}} |
| {{job_2_name}} | {{retry_count_2}} | {{retry_interval_2}} | {{alert_2}} | {{desc}} |

**失败处理流程**:
1. 重试 N 次
2. 仍失败 → 标记 FAILED + 告警
3. {{manual_intervention_condition}} → 人工介入

## 7. 幂等设计

<!-- 指令: 必须说明任务幂等保证 -->

| 任务名 | 幂等键 | 去重方式 | 说明 |
|--------|--------|----------|------|
| {{job_1_name}} | {{idempotent_key_1}} | {{dedup_method_1}} | {{desc}} |

## 8. 配置清单

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| groupId | {{group_id}} | 应用分组 |
| namespace | {{namespace}} | 命名空间 |
| appKey | {{app_key}} | 应用密钥（加密存储） |
| {{custom_config}} | {{value}} | {{desc}} |

## 9. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| SchedulerX Server 不可用 | {{impact_1}} | {{fallback_1}} | {{recovery_1}} |
| Worker 宕机 | {{impact_2}} | {{fallback_2}} | {{recovery_2}} |
| 任务执行超时 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |
| 分片不均匀 | {{impact_4}} | {{fallback_4}} | {{recovery_4}} |

## 10. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| 任务执行失败 | 连续 {{fail_threshold}} 次 | 需排查 |
| 任务执行超时 | > {{timeout_threshold}}s | 性能退化 |
| 调度延迟 | > {{schedule_delay}}s | Server 压力大 |
| 任务未触发 | 超过预期 {{miss_threshold}} 分钟 | 调度异常 |

## 11. 安全红线

<!-- 指令: 以下为公司 SchedulerX 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | 任务中硬编码密码、AK/SK 等敏感信息（必须使用配置中心加密存储） |
| 🚫 禁止 | 任务不做幂等校验直接执行业务逻辑 |
| 🚫 禁止 | 分片任务不处理分片失败场景（必须有容错） |
| ⚠️ 需审批 | 任务执行超时 > 30 分钟 |
| ⚠️ 需审批 | 分片数 > 100 |
| ✅ 允许 | 使用 DAG 编排多任务依赖 |
| ✅ 允许 | 使用失败重试 + 告警机制 |
| ✅ 允许 | 使用 MapReduce 模型处理大数据量任务 |
