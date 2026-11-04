# Kafka 消息设计 — {{feature_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及 Kafka 消息设计时按此结构填充 -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}}（对比 RocketMQ：高吞吐/流处理/日志聚合） |
| Kafka 版本 | {{kafka_version}} |
| 部署模式 | {{deploy_mode}}（Broker 数量、副本因子） |

## 2. 架构设计

<!-- 指令: 使用 PlantUML 组件图描述 Kafka 架构，输出到 diagrams/ 目录 -->

```text
Producer({{producer_service}}) → Kafka Cluster → Consumer Group({{consumer_service}})
```

## 3. Topic 分区策略

<!-- 指令: 必须定义 Topic 的分区设计 -->

| Topic | 分区数 | 副本因子 | 分区键 | 说明 |
|-------|--------|----------|--------|------|
| {{topic_1}} | {{partitions_1}} | {{replication_1}} | {{partition_key_1}} | {{desc}} |
| {{topic_2}} | {{partitions_2}} | {{replication_2}} | {{partition_key_2}} | {{desc}} |

**命名规范**:
- Topic: `{{env}}.{{biz}}.{{module}}.{{event}}`（如 `prod.order.payment.created`）
- 分区数原则：≥ Consumer 实例数，按吞吐量估算（单分区 ~10MB/s）

**分区策略说明**:
- 分区键选择：{{partition_key_reason}}
- 顺序保证：{{order_guarantee}}（同分区内有序）

## 4. Consumer Group 设计

| Group ID | 订阅 Topic | 实例数 | 消费模式 | 说明 |
|----------|-----------|--------|----------|------|
| {{group_1}} | {{topic_1}} | {{instances}} | earliest/latest | {{desc}} |

**Rebalance 策略**:
- 分区分配策略：{{assignment_strategy}}（Range / RoundRobin / CooperativeSticky）
- Session Timeout：{{session_timeout}}
- Max Poll Interval：{{max_poll_interval}}

## 5. 消息体设计

<!-- 指令: 定义消息 Key 和 Value 结构 -->

### 5.1 {{message_name_1}}

**Key**: `{{message_key}}`（用于分区路由）

**Value** (JSON/Avro/Protobuf):

```json
{
  "eventId": "{{uuid}}",
  "eventType": "{{event_type}}",
  "timestamp": 1700000000000,
  "aggregateId": "{{aggregate_id}}",
  "payload": {
    "{{field_1}}": "{{value_1}}",
    "{{field_2}}": "{{value_2}}"
  }
}
```

**Schema 管理**: {{schema_registry}}（Confluent Schema Registry / 无）

## 6. Offset 管理

<!-- 指令: 必须说明 Offset 提交策略 -->

| 项目 | 配置 | 说明 |
|------|------|------|
| 提交方式 | {{commit_mode}}（自动/手动） | {{reason}} |
| 提交间隔 | {{commit_interval}} | 自动提交时 |
| 初始偏移 | {{auto_offset_reset}}（earliest/latest） | 新 Group 首次消费 |
| 重置策略 | {{offset_reset_strategy}} | 运维场景 |

## 7. 数据保留策略

| Topic | retention.ms | retention.bytes | 说明 |
|-------|-------------|-----------------|------|
| {{topic_1}} | {{retention_time}} | {{retention_size}} | {{desc}} |
| {{topic_2}} | {{retention_time}} | {{retention_size}} | {{desc}} |

**压缩策略**: {{cleanup_policy}}（delete / compact / compact+delete）

## 8. Exactly-Once 语义

<!-- 指令: 如涉及精确一次语义，说明实现方案 -->

- 是否启用幂等生产者：{{idempotent_producer}}（`enable.idempotence=true`）
- 事务性生产者：{{transactional_producer}}
- 消费端事务：{{consumer_transaction}}（read-process-write 原子性）
- 适用场景：{{exactly_once_scenario}}

## 9. 配置清单

### 9.1 Producer 配置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| acks | {{acks}} | 确认级别（0/1/all） |
| retries | {{retries}} | 重试次数 |
| batch.size | {{batch_size}} | 批量大小 |
| linger.ms | {{linger_ms}} | 等待时间 |
| compression.type | {{compression}} | 压缩算法 |

### 9.2 Consumer 配置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| max.poll.records | {{max_poll_records}} | 单次拉取条数 |
| fetch.min.bytes | {{fetch_min_bytes}} | 最小拉取字节 |
| max.partition.fetch.bytes | {{max_fetch_bytes}} | 单分区最大拉取 |
| {{custom_config}} | {{value}} | {{desc}} |

## 10. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| Broker 宕机 | {{impact_1}} | {{fallback_1}} | {{recovery_1}} |
| 消费积压 | {{impact_2}} | {{fallback_2}} | {{recovery_2}} |
| 分区 Leader 切换 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |
| 消费者 Rebalance 风暴 | {{impact_4}} | {{fallback_4}} | {{recovery_4}} |

## 11. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| Consumer Lag | > {{lag_threshold}} | 消费积压 |
| UnderReplicatedPartitions | > {{urp_threshold}} | 副本同步异常 |
| 磁盘使用率 | > {{disk_threshold}}% | 需扩容/清理 |
| 请求延迟（P99） | > {{latency_threshold}}ms | 性能下降 |
| ISR 收缩频率 | > {{isr_shrink_rate}}/min | Broker 不稳定 |

## 12. 安全红线

<!-- 指令: 以下为公司 Kafka 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | 消息体中存储密码、Token、身份证号等敏感数据明文 |
| 🚫 禁止 | 生产环境 `acks=0`（无确认，消息可能丢失） |
| 🚫 禁止 | 消费端不做幂等校验直接处理业务 |
| ⚠️ 需审批 | 单 Topic 分区数 > 128 |
| ⚠️ 需审批 | `replication.factor` < 3（生产环境） |
| ✅ 允许 | 使用 `acks=all` + `enable.idempotence=true` 保证不丢失 |
| ✅ 允许 | 使用 Schema Registry 管理消息格式演进 |
| ✅ 允许 | 使用 Compaction 保留最新状态（如配置变更场景） |
