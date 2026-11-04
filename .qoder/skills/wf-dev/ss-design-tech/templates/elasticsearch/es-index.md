# Elasticsearch 索引设计 — {{index_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及 Elasticsearch 全文检索设计时按此结构填充 -->
<!-- 指令: 产出物文件组织（对齐公司规范）： -->
<!-- 指令:   Mapping 定义 → elasticsearch/es-{索引名}-mapping.json -->
<!-- 指令:   别名策略   → elasticsearch/es-{索引名}-alias.md（可选） -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}} |
| ES 版本 | {{es_version}} |
| 集群规模 | {{cluster_size}}（节点数、角色分配） |

## 2. 索引设计

<!-- 指令: 必须定义索引的完整设计 -->

| 项目 | 配置 | 说明 |
|------|------|------|
| 索引名 | {{index_name}} | 命名：小写 kebab-case（如 `user-service`） |
| 主分片数 | {{primary_shards}} | 【强制】[ES-002] 必须显式指定（生产建议 3-5） |
| 副本数 | {{replica_shards}} | 【强制】[ES-003] 必须 ≥ 1 |
| 刷新间隔 | {{refresh_interval}} | 近实时需求（默认 1s） |
| 别名 | {{alias_name}} | 生产读写必须通过别名访问 |

### 2.1 Mapping 定义

<!-- 指令: 【强制】[ES-004] _meta 必须包含 description/version/last_updated/owner -->
<!-- 指令: 【强制】[ES-005] dynamic 必须显式设置，推荐 strict -->

```json
{
  "settings": {
    "number_of_shards": {{primary_shards}},
    "number_of_replicas": {{replica_shards}},
    "refresh_interval": "{{refresh_interval}}",
    "analysis": {
      "analyzer": {
        "{{custom_analyzer}}": {
          "type": "custom",
          "tokenizer": "{{tokenizer}}",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "_meta": {
      "description": "{{index_description}}",
      "version": "1.0.0",
      "last_updated": "{{date}}",
      "owner": "{{owner_team}}"
    },
    "dynamic": "strict",
    "properties": {
      "{{field_1}}": {
        "type": "{{type_1}}"
      },
      "{{field_2}}": {
        "type": "text",
        "analyzer": "{{analyzer}}",
        "fields": {
          "keyword": {
            "type": "keyword"
          }
        }
      },
      "create_time": {
        "type": "date",
        "format": "strict_date_optional_time||epoch_millis"
      }
    }
  }
}
```

### 2.2 字段命名与类型规范

<!-- 指令: 以下规则来自公司 ES 规范，生成 Mapping 时逐条检查 -->

- 【强制】[ES-010] 字段名使用 snake_case，与数据库字段命名保持一致
- 【强制】[ES-011] 禁止使用 ES 保留字段名（`_id`、`_source`、`_routing` 等）
- 【强制】[ES-012] 布尔字段不要用 `is_` 开头
- 【强制】[ES-013] 日期字段使用 `_time` 或 `_date` 后缀
- 【强制】[ES-020] 精确匹配/聚合/排序用 `keyword`
- 【强制】[ES-021] 全文检索用 `text` + 显式指定 `analyzer`
- 【强制】[ES-022] 中文检索用 `ik_smart`/`ik_max_word`，禁止用默认 `standard`
- 【强制】[ES-023] 需精确+全文的字段用 `text` + `fields.keyword`
- 【强制】[ES-024] 日期字段必须显式指定 `format`
- 【强制】[ES-025] 金额用 `scaled_float`（`scaling_factor: 100`），禁止 float/double
- 【强制】[ES-026] 布尔字段必须设置 `null_value`
- 【强制】[ES-030] 数组对象必须用 `nested` 类型

## 3. 分词器选型

<!-- 指令: 必须说明分词器选择及理由 -->

| 字段 | 分词器（索引时） | 搜索分词器 | 说明 |
|------|--------|-----------|------|
| {{field_1}} | {{index_analyzer}} | {{search_analyzer}} | {{reason}} |
| {{field_2}} | {{index_analyzer}} | {{search_analyzer}} | {{reason}} |

**分析器选择策略（公司规范）**:

| 场景 | 推荐分析器 | 说明 |
|------|-----------|------|
| 中文全文检索（用户输入） | `ik_smart` | 粗粒度，适合搜索 |
| 中文全文检索（内容索引） | `ik_max_word` | 细粒度，适合索引 |
| 英文全文检索 | `standard` 或 `english` | ES 内置 |
| 精确匹配 | 不使用分析器（`keyword`） | — |

> **重要**：建议索引使用 `ik_max_word`（细粒度），搜索使用 `ik_smart`（粗粒度），提升召回率。

## 4. 查询 DSL 示例

<!-- 指令: 必须提供核心查询场景的 DSL 示例 -->

### 4.1 {{query_scenario_1}}

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "{{field}}": "{{keyword}}" } }
      ],
      "filter": [
        { "term": { "delete_flag": 0 } },
        { "range": { "create_time": { "gte": "{{start}}", "lte": "{{end}}" } } }
      ]
    }
  },
  "sort": [{ "create_time": "desc" }],
  "from": 0,
  "size": 10,
  "_source": ["{{return_fields}}"]
}
```

### 4.2 {{query_scenario_2}}

```json
{{dsl_example_2}}
```

## 5. 数据同步方案

<!-- 指令: 必须说明数据从 MySQL 同步到 ES 的方案 -->

| 项目 | 方案 | 说明 |
|------|------|------|
| 同步方式 | {{sync_method}}（Canal / Logstash JDBC / MQ 消费 / 应用双写） | {{reason}} |
| 同步延迟 | {{sync_delay}} | 近实时/准实时 |
| 全量初始化 | {{full_sync_method}} | 首次/重建 |
| 增量同步 | {{incremental_sync_method}} | 日常 |
| 数据一致性 | {{consistency_strategy}} | 补偿/对账 |

**同步链路**:

```text
MySQL → {{sync_tool}} → ES
{{sync_detail}}
```

## 6. 索引生命周期（ILM）

<!-- 指令: 必须定义索引生命周期策略 -->

| 阶段 | 条件 | 动作 | 说明 |
|------|------|------|------|
| Hot | 索引创建 | 写入 + 查询 | 最新数据 |
| Warm | {{warm_condition}}（天数/大小） | 缩减副本 + 强制合并 | 历史查询 |
| Cold | {{cold_condition}} | 只读 + 冻结 | 低频访问 |
| Delete | {{delete_condition}} | 删除索引 | 过期清理 |

**滚动策略**:
- 滚动条件：{{rollover_condition}}（大小/天数/文档数）
- 索引模板：`{{index_name}}-{{YYYY.MM.dd}}-{{seq}}`

## 7. 性能优化

<!-- 指令: 必须说明性能优化措施 -->

| 优化项 | 方案 | 说明 |
|--------|------|------|
| Routing | {{routing_strategy}} | 减少分片扫描 |
| Filter Cache | {{filter_cache_usage}} | 利用 bitset 缓存 |
| Bulk 批量 | {{bulk_size}} 条/批 | 批量写入 |
| 预排序 | {{index_sort}} | 加速范围查询 |
| _source 裁剪 | {{source_filtering}} | 减少网络传输 |
| 深分页 | {{deep_paging_solution}}（search_after / scroll） | 避免 from+size |

## 8. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| ES 集群不可用 | {{impact_1}} | {{fallback_1}}（降级到 DB 查询） | {{recovery_1}} |
| 分片未分配 | {{impact_2}} | {{fallback_2}} | {{recovery_2}} |
| 同步延迟过大 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |
| 索引损坏 | {{impact_4}} | {{fallback_4}}（别名切换） | {{recovery_4}} |

## 9. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| 集群状态 | {{cluster_status_threshold}}（Yellow/Red） | 分片异常 |
| JVM 堆使用率 | > {{heap_threshold}}% | GC 压力 |
| 索引速率 | < {{index_rate_threshold}}/s | 写入瓶颈 |
| 查询延迟（P99） | > {{query_latency_threshold}}ms | 性能退化 |
| 磁盘使用率 | > {{disk_threshold}}% | 需扩容 |
| 同步延迟 | > {{sync_delay_threshold}}s | 数据不一致风险 |

## 10. 安全红线

<!-- 指令: 以下为公司 ES 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | 索引中存储密码哈希、Token、身份证号等敏感字段 |
| 🚫 禁止 | 手机号、邮箱使用 `text` 类型并配置分词器 |
| 🚫 禁止 | 生产环境关闭副本（`number_of_replicas: 0`） |
| ⚠️ 需审批 | 使用 `dynamic: true`（允许动态映射） |
| ⚠️ 需审批 | 单索引 shard 数 > 10 |
| ⚠️ 需审批 | 使用 `nested` 字段超过 3 层深度 |
| ✅ 允许 | 手机号、邮箱使用 `keyword` 类型 |
| ✅ 允许 | 用户昵称、商品名称使用 `text` + `ik` 分词器 |
| ✅ 允许 | 金额使用 `scaled_float` |
