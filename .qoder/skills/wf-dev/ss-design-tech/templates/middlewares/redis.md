# Redis 缓存设计 — {{feature_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及 Redis 缓存设计时按此结构填充 -->
<!-- 指令: 不得删除必选章节，可选章节按实际情况取舍 -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}} |
| Redis 版本 | {{redis_version}} |
| 部署模式 | {{deploy_mode}}（单机/哨兵/Cluster） |

## 2. 架构设计

<!-- 指令: 使用 PlantUML 组件图描述缓存架构，输出到 diagrams/ 目录 -->

```text
{{cache_architecture_description}}
```

## 3. Key 命名规范

<!-- 指令: 必须定义完整的 Key 命名规则 -->

| Key 模式 | 示例 | 说明 | 数据类型 |
|----------|------|------|----------|
| `{{biz}}:{{module}}:{{entity}}:{{id}}` | `order:detail:info:123456` | {{desc}} | String/Hash/Set/ZSet/List |
| `{{biz}}:{{module}}:list:{{condition}}` | `order:detail:list:userId_100` | {{desc}} | {{type}} |

**命名规则**:
- 分隔符使用 `:`
- 前缀格式：`业务域:模块:实体:标识`
- 禁止使用特殊字符（空格、换行、中文）
- Key 长度 ≤ 128 字节

## 4. TTL 策略

<!-- 指令: 必须为每种 Key 定义过期策略 -->

| Key 模式 | TTL | 策略说明 |
|----------|-----|----------|
| {{key_pattern_1}} | {{ttl_1}} | {{strategy_1}}（固定/随机偏移/永不过期+主动删除） |
| {{key_pattern_2}} | {{ttl_2}} | {{strategy_2}} |

**防雪崩策略**: TTL 基础值 + 随机偏移（±10%），避免批量同时过期。

## 5. 缓存策略

### 5.1 读写策略

<!-- 指令: 说明采用的缓存模式 -->

- 模式：{{cache_pattern}}（Cache-Aside / Read-Through / Write-Through / Write-Behind）
- 读流程：{{read_flow}}
- 写流程：{{write_flow}}

### 5.2 缓存穿透防护

<!-- 指令: 必须说明穿透防护方案 -->

- 方案：{{penetration_solution}}（布隆过滤器 / 空值缓存 / 参数校验）
- 空值 TTL：{{null_ttl}}

### 5.3 缓存击穿防护

- 方案：{{breakdown_solution}}（互斥锁 / 逻辑过期 / 热点预加载）

### 5.4 缓存雪崩防护

- 方案：{{avalanche_solution}}（TTL 随机偏移 / 多级缓存 / 限流降级）

## 6. 序列化方式

| 场景 | 序列化器 | 说明 |
|------|----------|------|
| {{scenario_1}} | {{serializer_1}}（JSON/Kryo/JDK） | {{reason}} |

## 7. 大 Key 预防

<!-- 指令: 必须说明大 Key 预防措施 -->

- 单 Key 阈值：String ≤ 10KB，Hash/Set/ZSet/List 元素数 ≤ 5000
- 拆分策略：{{big_key_split_strategy}}
- 监控手段：{{monitoring_method}}

## 8. 配置清单

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| maxmemory | {{maxmemory}} | 最大内存 |
| maxmemory-policy | {{eviction_policy}} | 淘汰策略 |
| timeout | {{timeout}} | 连接超时 |
| {{custom_config}} | {{value}} | {{desc}} |

## 9. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| Redis 不可用 | {{impact_1}} | {{fallback_1}} | {{recovery_1}} |
| 主从切换 | {{impact_2}} | {{fallback_2}} | {{recovery_2}} |
| 缓存与 DB 不一致 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |

## 10. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| 内存使用率 | > {{mem_threshold}}% | 触发扩容/淘汰 |
| 连接数 | > {{conn_threshold}} | 连接泄漏风险 |
| 命中率 | < {{hit_rate_threshold}}% | 缓存策略需优化 |
| 慢查询 | > {{slow_query_ms}}ms | 大 Key/热 Key 风险 |

## 11. 安全红线

<!-- 指令: 以下为公司 Redis 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | 存储密码、Token、身份证号等敏感数据明文 |
| 🚫 禁止 | 使用 `KEYS *` 命令（生产环境） |
| 🚫 禁止 | 单 Key 超过 10KB（String）或元素数超过 5000（Hash/Set/ZSet/List） |
| ⚠️ 需审批 | 使用 `FLUSHALL` / `FLUSHDB` |
| ⚠️ 需审批 | 关闭持久化（RDB + AOF 均关闭） |
| ✅ 允许 | 使用 `SCAN` 替代 `KEYS` 进行遍历 |
| ✅ 允许 | 使用 `SET NX EX` 实现分布式锁 |
| ✅ 允许 | 使用 Pipeline 批量操作减少 RTT |
