# 数据库 DDL 设计规范模板

<!-- 指令: 本模板为 AI 结构约束，生成 DDL 时必须遵循以下规范 -->
<!-- 指令: 产出物路径 → databases/{db-type}-{db-name}-ddl.sql -->
<!-- 指令: 关联关系图 → databases/{db-type}-{db-name}-relation-{domain}.puml -->

## 1. 文件组织规范

### 1.1 完整数据库定义由一组文件组成

每个数据库的完整定义**必须**包含以下文件（以 `mysql-user-service` 为例）：

| 文件类型 | 文件命名格式 | 示例 |
|---------|-------------|------|
| **DDL 脚本** | `{db-type}-{db-name}-ddl.sql` | `mysql-user-service-ddl.sql` |
| **关联关系图** | `{db-type}-{db-name}-relation-{domain}.puml` | `mysql-user-service-relation-account.puml` |

> 关联关系图按**业务领域**分组（如：账号、权限、订单、支付等），每个文件聚焦一个业务领域的表关联关系。

### 1.2 命名规范

- 格式：`{数据库类型}-{数据库名称}-ddl.sql`
- 示例：`mysql-user-service-ddl.sql`、`pg-order-service-ddl.sql`

## 2. 全局规范

### 2.1 命名约定

<!-- 指令: 严格遵循公司 RDS 命名规范 -->

| 对象 | 规则 | 示例 |
|------|------|------|
| 表名 | snake_case，**单数形式**，禁止 `t_` 前缀 | `order`, `order_item`, `auth_user` |
| 字段名 | snake_case，小写字母或数字，字母开头 | `create_time`, `order_status` |
| 普通索引 | `idx_<table>_<column>` | `idx_order_user_id` |
| 唯一索引 | `uk_<table>_<column>` | `uk_order_order_no` |
| 联合索引 | `idx_<table>_<col1>_<col2>` | `idx_order_status_time` |
| 主键 | `id`（统一） | `id BIGINT` |

### 2.2 字符集与引擎

```sql
-- 【强制】[RDS-005] 使用 utf8mb4_unicode_ci 字符集
ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='{{table_comment}}';
```

### 2.3 主键策略

- 默认使用雪花 ID：`id BIGINT NOT NULL COMMENT '主键(雪花ID)'`
- 特殊场景使用 UUID：`id VARCHAR(36) NOT NULL COMMENT '主键(UUID)'`
- 禁止使用自增 ID（分布式环境不适用）

### 2.4 必备审计字段

<!-- 指令: 【强制】[RDS-019][RDS-020] 每张表必须包含以下字段，置于表定义末尾 -->

```sql
`create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
`update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
`created_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '创建人',
`updated_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '更新人',
`delete_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '逻辑删除标识: 0-未删除, 1-已删除',
```

### 2.5 字段命名强制规则

<!-- 指令: 以下规则来自公司规范，生成 DDL 时逐条检查 -->

- 【强制】[RDS-001] 下划线命名法，禁止驼峰，只允许英文字母、数字、下划线，必须字母开头
- 【强制】[RDS-002] 表名使用单数（`auth_user` 而非 `auth_users`）
- 【强制】[RDS-003] 禁止使用数据库关键字（select/order/group 等）
- 【强制】[RDS-004] 建表必须提供表注释
- 【强制】[RDS-006] 尽量用占用空间少的数据类型
- 【强制】[RDS-007] Boolean 字段定义成 tinyint(1)，1=是，0=否
- 【强制】[RDS-008] `YYYY-MM-dd` 类型字段使用 `_date` 后缀
- 【强制】[RDS-009] `YYYY-MM-dd HH:mm:ss` 类型字段使用 `_time` 后缀
- 【强制】[RDS-010] 计数类字段使用 `_num` 后缀
- 【强制】[RDS-012] 字段都必须提供注释
- 【强制】[RDS-013] enum 类字段注释中必须列出所有 enum 值及含义
- 【强制】[RDS-014] 不得使用外键与级联，外键概念在应用层解决
- 【强制】[RDS-015] 小数类型用 decimal，禁止 float/double，需指定总位数和小数位
- 【强制】[RDS-016] 不要用 `is_` 开头
- 【强制】[RDS-018] 禁用保留字（desc、range、match、delayed 等）
- 【强制】[RDS-020] 禁止物理删除，使用 delete_flag 逻辑删除
- 【强制】🆕 来自其他系统的字段，注释末尾标识 `,[来自：]xxx系统的yyy`

## 3. DDL 文件结构

<!-- 指令: 生成的 ddl.sql 必须按以下结构组织 -->

```sql
-- ============================================
-- 说明: {{数据库用途说明}}
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci
-- 需求来源: {{spec_reference}}
-- 创建日期: {{create_date}}
-- ============================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- 表: {{table_name}}
-- 用途: {{table_purpose}}
-- 关联: {{related_tables}}
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `{{table_name}}` (
    `id` BIGINT NOT NULL COMMENT '主键(雪花ID)',
    -- 业务字段
    `{{column_1}}` {{TYPE}} {{NOT_NULL}} COMMENT '{{comment}}',
    `{{column_2}}` {{TYPE}} {{NOT_NULL}} DEFAULT {{default}} COMMENT '{{comment}}',
    -- 审计字段
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `created_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '创建人',
    `updated_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '更新人',
    `delete_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '逻辑删除标识: 0-未删除, 1-已删除',
    PRIMARY KEY (`id`),
    {{INDEX_DEFINITIONS}}
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='{{table_comment}}';

SET FOREIGN_KEY_CHECKS = 1;
```

## 4. 字段类型选择指南

<!-- 指令: AI 生成 DDL 时按以下规则选择字段类型 -->

| 业务场景 | 推荐类型 | 说明 |
|----------|----------|------|
| ID/外键 | BIGINT | 雪花 ID |
| 短文本（≤50） | VARCHAR(N) | 明确长度 |
| 中文本（≤500） | VARCHAR(N) | 明确长度 |
| 长文本（>500） | TEXT | 不频繁查询 |
| 金额 | DECIMAL(M,D) | 禁止 FLOAT/DOUBLE [RDS-015] |
| 整数/计数 | INT / BIGINT | 按范围选择，计数用 `_num` 后缀 |
| 布尔/状态 | TINYINT(1) | 0/1 [RDS-007] |
| 日期（YYYY-MM-dd） | DATE | 字段用 `_date` 后缀 |
| 日期时间 | DATETIME | 字段用 `_time` 后缀 [RDS-022] |
| 时间戳 | BIGINT(13) | 毫秒级时间戳 |
| JSON 结构 | JSON | MySQL 5.7+ |
| 枚举 | VARCHAR(32) | 禁止 ENUM 类型，注释列出所有值 |

## 5. 索引设计原则

<!-- 指令: 生成索引时遵循以下原则 -->

- 单表索引数 ≤ 5 个（含主键）
- 联合索引字段数 ≤ 5
- 遵循最左前缀原则
- 区分度低的字段（如 `delete_flag`）不单独建索引
- 频繁查询的 WHERE/ORDER BY/JOIN 字段建索引
- 覆盖索引优先（避免回表）

## 6. 关联关系图规范

<!-- 指令: DDL 生成后必须同步生成 PlantUML 关联关系图 -->
<!-- 指令: 使用 templates/diagrams/relation-diagram.puml 模板 -->

**文件命名**：`{db-type}-{db-name}-relation-{domain}.puml`

**核心规则**：
- **仅展示关联字段**（外键引用字段），不包含业务字段
- 业务字段请参考 `*-ddl.sql` 文件
- 本系统**不使用数据库级别的外键约束**，关联关系由应用层保证
- 按**业务领域**分组，每个文件聚焦一个业务领域

**PlantUML 文件规则**：

***PlantUML 文件头**：
```plantuml
' ============================================
' 说明: {{db_name}} - {{domain}}领域关联关系
'       主题: {{domain_topic}}
' ============================================
'
' 【规范说明】
' 1. 本图仅展示表之间的关联关系,只包含关联字段(外键引用字段)
' 2. 不包含业务字段,业务字段请参考 {{db-type}}-{{db-name}}-ddl.sql
' 3. 本系统不使用数据库级别的外键约束,关联关系由应用层保证
' 4. 每个实体中列出的字段均为关联字段(如 user_id, role_id 等)

```
- `templates/diagrams/relation-diagram.puml`  关联关系图模板
- 新增表标注 `<<新增>>`
- 已有关联表标注 `<<已有>>`，仅展示关联字段 + 主键
- 关联关系必须标注（1:1 / 1:N / M:N）
