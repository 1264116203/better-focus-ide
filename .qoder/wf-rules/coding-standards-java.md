---
trigger: glob
glob: src/**/*.java
---
# Java / Spring Boot 编码规范（栈扩展）

适用 JDK 、Spring Boot 、MyBatis-Plus / JPA。继承 `coding-standards.md`。

## 分层与结构

- 分层：Controller → Service(接口+实现) → Repository/Mapper → Entity；DTO/VO 与 Entity 分离，用 MapStruct 映射。
- Controller 不实现业务；不直接依赖 Mapper。Service 方法体建议 ≤30 行。
- 构造器注入（禁字段 `@Autowired`）。
- 跨服务调用用 Feign，导入统一 `CommonFeignConfiguration`。

## 返回与校验

- 统一返回体 `Result<T>` / `Response<T>`（禁裸 `ResponseEntity` 作为业务返回）。
- 入参用 JSR-303（`@Valid` + `@NotNull/@Size/...`），自定义约束注解封装复杂校验。
- 金额用 `BigDecimal`；时间用 `java.time`。

## 数据库

- 主键 UUID 或雪花；表含 `create_time`/`update_time`；软删除 `delete_flag`；不使用物理外键（应用层维护关系）。
- 迁移脚本走 Liquibase；DDL 变更需评审。

## 文档与注释

- 请求入口方法、跨层 API 方法必须有参数+返回 Javadoc；类/组件字段需 Javadoc。
- 敏感配置用 Jasypt 加密。

## 构建命令策略

- 改代码后 `mvn -q compile` 验证；测试 `mvn -q test`（单元）/`mvn -q verify`（集成）。
- 禁 `mvn install` 污染本地仓库

## 必须用的组件

- lombok
- Jasypt
- google guava

