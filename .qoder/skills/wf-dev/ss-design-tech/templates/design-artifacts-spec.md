# 技术设计产出物规范

> 本规范定义 `ss-design-tech` 技能在技术设计阶段应产出的全部附属文档与图表，以及对应的模板约束。

## 1. 产物目录结构

所有设计产出物写入 `workflow_dir.active` 对应的 slug 目录下，按以下子目录组织（对齐公司 `global/` 目录规范）：

```text
<slug>/
├── NN-design.md                 ← 核心技术设计（NN = 当前 phase 序号）
├── NN-spec.md / NN-intake.md / ... ← 上游产物（序号由各自 phase 决定）
├── diagrams/                    ← 图表（PlantUML / Mermaid / DrawIO）
│   ├── sequence-<name>.puml     ← 时序图
│   ├── activity-<name>.puml     ← 活动图
│   └── component-<name>.puml    ← 组件图
├── openapis/                    ← RESTful API 文档
│   ├── consumer/                ← 第三方提供的 API（本系统作为调用方）
│   │   └── <thirdparty>-api.md
│   └── provider/                ← 本系统提供的 API（本系统作为提供方）
│       └── restapi-<module>.md
├── databases/                   ← 数据库文档
│   ├── {db-type}-{db-name}-ddl.sql              ← DDL 脚本
│   └── {db-type}-{db-name}-relation-{domain}.puml ← 表关联关系图
├── elasticsearch/               ← Elasticsearch 设计
│   └── es-{index}-mapping.json  ← 索引 Mapping 定义
└── middlewares/                 ← 中间件设计
    ├── redis-<name>.md          ← Redis 缓存设计
    ├── rocketmq-<name>.md       ← RocketMQ 消息设计
    ├── kafka-<name>.md          ← Kafka 消息设计
    ├── schedulerx-<name>.md     ← SchedulerX 定时任务设计
    └── oss-<name>.md            ← 阿里云 OSS 存储设计
```

> **序号前缀说明**：工作流模式下，所有产出文件均带 `NN-` 序号前缀（`NN` = 所属 phase 编号），由编排器自动分配。上图中的 `NN-design.md` 表示当前设计阶段产出的 `design.md` 加序号前缀后的实际文件名。子目录下的文件同样加前缀。详见 `orchestrator-behavior.md` → “产出物序号前缀规范”。

## 2. 图表规范（PlantUML）

### 2.1 通用约束

- 格式：PlantUML（`.puml` 后缀）
- 编码：UTF-8
- 文件头必须包含 `@startuml` / `@enduml`
- 标题使用 `title` 关键字
- 参与者/组件命名使用英文标识符 + 中文别名（`participant "用户服务" as UserService`）
- 禁止使用 `skinparam` 自定义样式（保持渲染一致性）
- 每张图必须有 `note` 说明核心业务规则或约束

### 2.2 时序图（Sequence Diagram）

- 适用场景：跨服务/跨层调用链路、异步消息交互
- 必须包含：参与者声明、同步/异步消息区分（`->` vs `->>`）、返回消息、`alt/else` 异常分支
- **必须启用分级自动编号**：使用 `autonumber X.Y.Z` 格式，每个 `==` 分隔符对应一个阶段（X），通过 `autonumber inc A` 递增阶段号，阶段内子分组用 `autonumber inc B`
- 模板：`templates/diagrams/sequence-diagram.puml`

### 2.3 活动图（Activity Diagram）

- 适用场景：业务流程、审批流、状态机转换
- 必须包含：起始/结束节点、条件分支（`if/then/else`）、泳道（`|swimlane|`）表示不同角色/系统
- 模板：`templates/diagrams/activity-diagram.puml`

### 2.4 组件图（Component Diagram）

- 适用场景：系统架构、模块依赖、部署拓扑
- 必须包含：组件声明、接口（`()` 提供 / `()--` 需求）、包/节点分组
- 模板：`templates/diagrams/component-diagram.puml`

### 2.5 ER 图（Entity Relationship Diagram）

- 适用场景：数据库表结构设计
- 范围：**仅绘制本次新增表 + 与新增表有直接关联的已有表**（非全库）
- 必须包含：表名、字段名、类型、主键/外键标识、关联关系（1:1 / 1:N / M:N）
- 已有表用 `<<existing>>`  stereotypes 标注
- 模板：`templates/diagrams/er-diagram.puml`
- ❗ **强制**：生成 ER 图前必须先使用 Read 工具读取 `templates/diagrams/er-diagram.puml` 模板，严格按模板中的 entity 结构、字段规范、关联关系语法和 note 要求填充。禁止跳过模板直接生成。

## 3. API 文档规范

### 3.1 目录组织（对齐公司规范）

API 文档按调用方向分为两个子目录：

- `openapis/consumer/` — 第三方提供的 API（本系统作为调用方）
- `openapis/provider/` — 本系统对外提供的 API（本系统作为提供方）

文件命名使用 kebab-case，如 `restapi-user-service.md`、`payment-gateway-api.md`。

### 3.2 统一文档结构（公司规范）

所有 API 文档使用统一模板 `templates/openapis/restapi-template.md`，包含以下 **10 个必选章节（缺一即不合格）**：

| # | 必选章节 | 必含要素 | 常见违规 |
|---|----------|----------|----------|
| 1 | 基本信息 | 模块、负责人、版本、协议、数据格式、认证方式、限流策略（7 字段表格） | 缺字段/用 bullet 代替表格 |
| 2 | 接口地址 | DEV/TEST/PROD 三行表格 | — |
| 3 | 通用约定 | ① 通用请求头表格(5行) ② 分页参数表格(4行含校验规则) ③ 分页响应 JSON 示例 ④ 复杂 JSON 字段说明规范(点号路径表) | 用一行 bullet 概括 |
| 4 | 接口列表 | 序号 + 方法 + 路径 + 说明（表格） | 缺序号列 |
| 5 | **接口详情** | **每个接口**均须展开：请求(Method+Path) → Headers → Path Params表 → Query Params表 → Request Body(JSON示例+字段路径表) → curl示例 → 响应200(JSON示例+data字段表) → 错误响应(JSON) | ❗ 最常见违规：仅列接口名不展开 |
| 6 | 统一响应结构 | JSON 示例 + 4 字段说明表 + success/code 语义一致性说明 | 仅 bullet 提及 |
| 7 | HTTP 状态码说明 | 7 行表格(200/400/401/403/404/429/500) | 完全缺失 |
| 8 | 业务错误码 | 4 列表格(错误码/说明/HTTP状态码/**建议处理方式**) | 缺第 4 列 |
| 9 | 安全要求 | 6 维度表格(传输加密/认证方式/权限模型/限流/敏感数据/幂等性) | 用 bullet 代替 |
| 10 | 变更记录 | 4 列表格(版本/日期/变更内容/**作者**) | 缺作者列 |

> **强制规则**：生成 API 文档前必须先 Read 模板文件，生成后逐节对照上表校验。接口数量 > 8 个时允许拆分为多个文件（按业务子模块），但每个文件均须包含完整的 10 个章节（通用约定可引用主文件）。

### 3.3 不可变约定（公司强制）

- **统一响应体**：`{"success": boolean, "code": integer, "message": string, "data": T}`
- **分页参数**：`page`/`pageSize`/`sort`/`order`
- **分页响应**：`data.items[]` + `data.pagination{page, pageSize, totalItems, totalPages}`
- **通用请求头**：`Authorization`、`Content-Type`、`Accept`、`X-Request-Id`、`Accept-Language`
- **复杂 JSON 字段说明**：使用点号路径展开（`buyer.address.city`、`items[].skuId`）

### 3.4 模板

- 统一模板：`templates/openapis/restapi-template.md`

## 4. 数据库文档规范（对齐公司规范）

### 4.1 文件组织

每个数据库的完整定义由一组文件组成：

| 文件类型 | 命名格式 | 示例 |
|---------|----------|------|
| DDL 脚本 | `{db-type}-{db-name}-ddl.sql` | `mysql-user-service-ddl.sql` |
| 关联关系图 | `{db-type}-{db-name}-relation-{domain}.puml` | `mysql-user-service-relation-account.puml` |

### 4.2 DDL 脚本规范

- 字符集：`utf8mb4`，排序规则：`utf8mb4_unicode_ci`（公司强制 [RDS-005]）
- 存储引擎：`InnoDB`
- 表名：**单数形式**，snake_case，禁止 `t_` 前缀（[RDS-002]）
- 必备审计字段：`create_time`、`update_time`、`created_by`、`updated_by`、`delete_flag`（[RDS-019][RDS-020]）
- 主键策略：雪花 ID（`BIGINT`）或 UUID（`VARCHAR(36)`）
- 索引命名：`idx_<table>_<column>`（普通）、`uk_<table>_<column>`（唯一）
- 禁止外键与级联（[RDS-014]），关联关系由应用层保证
- 模板：`templates/databases/ddl-spec.md`

### 4.3 关联关系图

- 使用 PlantUML `entity` 语法
- **仅展示关联字段**（外键引用字段），不包含业务字段
- 按**业务领域**分组（如账号、订单、支付）
- 新增表标注 `<<new>>`，已有表标注 `<<existing>>`
- 关联关系用 `||--o{`（1:N）、`||--||`（1:1）、`}o--o{`（M:N）
- 模板：`templates/diagrams/er-diagram.puml`
- ❗ **强制**：生成关联关系图前必须先 Read `templates/diagrams/er-diagram.puml`，按模板结构生成

## 5. 中间件文档规范

每种中间件的设计文档必须包含以下通用章节：

1. **概述**：使用场景、选型理由
2. **架构设计**：拓扑图（PlantUML 组件图）
3. **配置清单**：关键配置项及推荐值
4. **容错设计**：故障场景 + 降级/重试/幂等策略
5. **监控告警**：关键指标 + 告警阈值
6. **安全红线**：🚫 禁止 / ⚠️ 需审批 / ✅ 允许 操作清单（公司规范必含）

### 5.1 Redis（`templates/middlewares/redis.md`）

额外必含：Key 命名规范、TTL 策略、缓存穿透/击穿/雪崩方案、序列化方式、大 Key 预防

### 5.2 RocketMQ（`templates/middlewares/rocketmq.md`）

额外必含：Topic/Tag 规划、消费组设计、消息幂等、顺序消息、死信队列处理

### 5.3 Kafka（`templates/middlewares/kafka.md`）

额外必含：Topic 分区策略、Consumer Group 设计、Offset 管理、数据保留策略、Exactly-Once 语义

### 5.4 SchedulerX（`templates/middlewares/schedulerx.md`）

额外必含：任务清单（Cron/固定频率）、分片策略、失败重试、任务依赖 DAG、超时告警

### 5.5 阿里云 OSS（`templates/middlewares/oss.md`）

额外必含：Bucket 规划、目录结构、访问控制（STS/签名 URL）、生命周期规则、CDN 加速配置

## 6. Elasticsearch 文档规范（对齐公司规范）

模板：`templates/elasticsearch/es-index.md`

### 6.1 文件组织

| 文件类型 | 命名格式 | 示例 |
|---------|----------|------|
| Mapping 定义 | `es-{索引名}-mapping.json` | `es-user-service-mapping.json` |
| 别名策略 | `es-{索引名}-alias.md`（可选） | `es-user-service-alias.md` |

### 6.2 必含章节

1. 索引设计（索引名、分片数、副本数、Mapping）
2. 字段命名与类型规范（公司 ES-010~ES-030 规则）
3. 分词器选型
4. 查询 DSL 示例
5. 数据同步方案（Canal/Logstash/MQ）
6. 索引生命周期（ILM）
7. 性能优化（routing、filter cache、bulk 批量）
8. 安全红线（公司规范必含）
9. 变更日志规范

### 6.3 公司强制规则

- 【强制】`_meta` 必含 `description`/`version`/`last_updated`/`owner`
- 【强制】`dynamic` 必须显式设置，推荐 `strict`
- 【强制】生产环境读写必须通过别名（alias）访问
- 【强制】中文检索禁止用默认 `standard` 分析器

## 7. 产出物生成规则

### 7.1 按需生成

并非每次设计都需要全部产出物。生成规则：

| 条件 | 必须产出 |
|------|--------|
| 涉及跨服务/跨层调用 | 时序图 |
| 涉及业务流程/状态转换 | 活动图 |
| 涉及新模块/系统集成 | 组件图 |
| 涉及新增 REST API | API 文档（provider/；若调用三方则加 consumer/） |
| 涉及新增/变更表 | DDL + 关联关系图（**必须先 Read `templates/diagrams/er-diagram.puml`**） |
| 涉及 Redis 缓存 | Redis 设计文档 |
| 涉及消息队列 | RocketMQ/Kafka 设计文档 |
| 涉及定时任务 | SchedulerX 设计文档 |
| 涉及文件存储 | OSS 设计文档 |
| 涉及全文检索 | Elasticsearch 设计文档（mapping.json） |

### 7.2 工作流适配

- **wf-feature-large / wf-feature-small**（默认 enhanced）：按上表全量生成，产出物独立成文件
- **--profile basic 覆盖时**：按上表生成，但可合并为单文件（如多个中间件合入 `NN-design.md` 的附录章节）

### 7.3 模板使用方式

模板为 **AI 结构约束**（Role Constraint Template）：
- AI 读取模板后，按模板定义的章节结构填充实际设计内容
- 模板中 `{{placeholder}}` 为占位符，`<!-- 指令: ... -->` 为 AI 行为指令
- 条件块 `{{#if condition}}...{{/if}}` 表示按需包含
- AI 不得删除模板中的必选章节，可选章节按实际情况取舍
