# 数据库使用规范（MySQL）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循

---

## 1. 建表规范

| 规则 | 说明 |
|------|------|
| 建表必须指定主键 | 每个表必须有主键 |
| 每个字段必须添加注释 | 明确字段含义，`COMMENT '字段说明'` |
| 字段默认设置为非空 | 除非业务允许为空，否则 `NOT NULL` |
| text/json 字段需评估必要性 | 优先使用 `varchar`，text 仅在长文本场景使用 |
| 字符串长度建议不超过 512 | 按需拆分字段，避免过长 varchar |
| 单表字段数量控制在 20-30 个 | 超出考虑拆表 |
| 单表数据量建议控制在 2000 万以内 | 超量需冷备或分表 |
| 小数类型必须使用 `decimal` | 禁止使用 `float/double` 避免精度丢失 |
| 禁止在代码中动态创建表或更新表结构 | 需通过迁移脚本管理 |

---

## 2. 索引规范

| 规则 | 说明 |
|------|------|
| 按业务场景创建联合索引 | 大数据量表必须建索引 |
| 使用 `EXPLAIN` 校验索引命中 | 确保查询走预期索引 |
| 单表索引数量控制在 4-6 个 | 过多索引影响写入性能 |

---

## 3. 查询限制

| 场景 | 单次查询上限 |
|------|-------------|
| TO B | ≤ 100 条 |
| TO C | ≤ 20 条 |
| Portal 列表 | ≤ 50 条 |

---

## 4. 审计字段规范

所有业务表必须包含以下审计字段：

```sql
`creator` VARCHAR(255) NOT NULL DEFAULT 'system' COMMENT '创建人',
`updater` VARCHAR(255) NOT NULL DEFAULT 'system' COMMENT '最后更新人',
`create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
`update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
```

---

## 5. 更新安全

- 更新数据时，更新 SQL 与备份 SQL 的 WHERE 条件必须一致

---

## 6. 参考规范

- 数据库设计规范.pdf

---

## 最终回复要求

* 说明建表/索引是否符合规范
* 说明是否使用 EXPLAIN 校验索引
* 说明查询数量是否在限制范围内