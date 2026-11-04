# RocketMQ 消息设计 — {{feature_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及 RocketMQ 消息设计时按此结构填充 -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}}（对比 Kafka：事务消息/延迟消息/顺序消息） |
| RocketMQ 版本 | {{rocketmq_version}} |
| 部署模式 | {{deploy_mode}}（单机/主从/DLedger） |

## 2. 架构设计

<!-- 指令: 使用 PlantUML 组件图描述消息架构，输出到 diagrams/ 目录 -->

```text
Producer({{producer_service}}) → Broker → Consumer({{consumer_service}})
```

## 3. Topic/Tag 规划

<!-- 指令: 必须定义完整的 Topic 和 Tag 规划 -->

| Topic | Tag | 生产者 | 消费者 | 消息类型 | 说明 |
|-------|-----|--------|--------|----------|------|
| {{topic_1}} | {{tag_1}} | {{producer_1}} | {{consumer_1}} | 普通/顺序/延迟/事务 | {{desc}} |
| {{topic_2}} | {{tag_2}} | {{producer_2}} | {{consumer_2}} | {{msg_type}} | {{desc}} |

**命名规范**:
- Topic: `{{ENV}}_{{BIZ}}_{{MODULE}}_TOPIC`（如 `PROD_ORDER_PAYMENT_TOPIC`）
- Tag: `{{ACTION}}`（如 `CREATE`、`UPDATE`、`CANCEL`）
- ConsumerGroup: `GID_{{BIZ}}_{{MODULE}}_{{ACTION}}`

## 4. 消费组设计

| ConsumerGroup | 订阅 Topic | 消费模式 | 线程数 | 说明 |
|---------------|-----------|----------|--------|------|
| {{group_1}} | {{topic_1}} | 集群/广播 | {{thread_count}} | {{desc}} |

## 5. 消息体设计

<!-- 指令: 定义消息体 JSON 结构 -->

### 5.1 {{message_name_1}}

```json
{
  "messageId": "{{uuid}}",
  "bizType": "{{biz_type}}",
  "timestamp": 1700000000000,
  "data": {
    "{{field_1}}": "{{value_1}}",
    "{{field_2}}": "{{value_2}}"
  },
  "traceId": "{{trace_id}}"
}
```

## 6. 消息幂等设计

<!-- 指令: 必须说明消费端幂等方案 -->

| 消息类型 | 幂等键 | 去重方式 | 去重窗口 |
|----------|--------|----------|----------|
| {{msg_type_1}} | {{idempotent_key}} | Redis SET NX / DB 唯一键 / 状态机 | {{dedup_window}} |

## 7. 顺序消息设计

<!-- 指令: 如涉及顺序消息，说明分区键和顺序保证 -->

- 分区键（ShardingKey）：{{sharding_key}}
- 顺序保证范围：{{order_scope}}（全局有序 / 分区有序）
- 消费失败处理：{{order_failure_handling}}（挂起重试 / 跳过）

## 8. 延迟消息 / 事务消息

<!-- 指令: 如涉及延迟消息或事务消息 -->

### 8.1 延迟消息

| 场景 | 延迟级别 | 说明 |
|------|----------|------|
| {{delay_scenario}} | Level {{level}}（{{delay_time}}） | {{desc}} |

### 8.2 事务消息

- 半消息 Topic：{{half_topic}}
- 本地事务检查：{{local_tx_check}}
- 回查间隔：{{check_interval}}

## 9. 死信队列处理

<!-- 指令: 必须说明死信处理策略 -->

- 最大重试次数：{{max_retry}}
- 死信 Topic：`%DLQ%{{consumer_group}}`
- 死信处理：{{dlq_handling}}（人工介入 / 定时重投 / 告警）
- 告警方式：{{alert_method}}

## 10. 配置清单

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| sendMsgTimeout | {{send_timeout}}ms | 发送超时 |
| consumeThreadMin | {{min_thread}} | 最小消费线程 |
| consumeThreadMax | {{max_thread}} | 最大消费线程 |
| maxReconsumeTimes | {{max_reconsume}} | 最大重试次数 |
| {{custom_config}} | {{value}} | {{desc}} |

## 11. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| Broker 不可用 | {{impact_1}} | {{fallback_1}} | {{recovery_1}} |
| 消费积压 | {{impact_2}} | {{fallback_2}} | {{recovery_2}} |
| 消息丢失 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |

## 12. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| 消费积压量 | > {{backlog_threshold}} | 消费能力不足 |
| 发送失败率 | > {{send_fail_rate}}% | 生产者异常 |
| 死信消息数 | > {{dlq_threshold}} | 需人工介入 |
| 消费延迟 | > {{consume_delay}}ms | 消费性能下降 |

## 13. 安全红线

<!-- 指令: 以下为公司 RocketMQ 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | 消息体中存储密码、Token、身份证号等敏感数据明文 |
| 🚫 禁止 | 生产环境使用同步发送 + 不处理返回结果（必须检查 SendResult） |
| 🚫 禁止 | 消费端不做幂等校验直接处理业务 |
| ⚠️ 需审批 | 单 Topic 分区数 > 64 |
| ⚠️ 需审批 | 消息体大小 > 4MB |
| ✅ 允许 | 使用事务消息保证本地事务与消息发送一致性 |
| ✅ 允许 | 使用延迟消息实现超时取消等场景 |
| ✅ 允许 | 使用 Tag 过滤减少无效消费 |
