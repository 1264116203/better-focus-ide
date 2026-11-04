# Spring Boot Test Profile Templates (JDK 17+/21+)

本文档提供 `real` 和 `hybrid` 测试环境模式的 Spring Boot YAML 配置模板。项目使用时复制到 `src/test/resources/` 目录。

---

## application-realtest.yml（真实环境测试）

```yaml
# 使用方式：@ActiveProfiles("realtest") 或 mvn test -Dspring.profiles.active=realtest
spring:
  datasource:
    url: jdbc:mysql://${MYSQL_HOST:rm-2zey6p56uzsayo499.mysql.rds.aliyuncs.com}:${MYSQL_PORT:3306}/${MYSQL_DB:arthur_test}?useSSL=false&allowPublicKeyRetrieval=true&characterEncoding=UTF-8&serverTimezone=Asia/Shanghai
    username: ${MYSQL_USERNAME:arthur_test}
    password: ${MYSQL_PASSWORD:mep1GwXJkcRXRsmY}
    driver-class-name: com.mysql.cj.jdbc.Driver
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
  jpa:
    hibernate:
      ddl-auto: none  # 不自动建表，使用真实 schema
    show-sql: true
  sql:
    init:
      mode: never  # 不跑 schema.sql
jwt:
  secret: ${JWT_SECRET:}  # 必须通过环境变量注入，禁止硬编码
logging:
  level:
    org.springframework: INFO
```

**使用前提：**
- MySQL 必须可连接（RDS 或本地实例）
- Redis 必须运行（本地或远程）
- `JWT_SECRET` 环境变量必须设置（≥256-bit Base64）
- 数据库 schema 已初始化（不依赖 auto-init）

---

## application-hybridtest.yml（混合环境测试）

```yaml
# 使用方式：@ActiveProfiles("hybridtest") 或 mvn test -Dspring.profiles.active=hybridtest
spring:
  datasource:
    url: jdbc:mysql://${MYSQL_HOST:rm-2zey6p56uzsayo499.mysql.rds.aliyuncs.com}:${MYSQL_PORT:3306}/${MYSQL_DB:arthur_test}?useSSL=false&allowPublicKeyRetrieval=true&characterEncoding=UTF-8&serverTimezone=Asia/Shanghai
    username: ${MYSQL_USERNAME:arthur_test}
    password: ${MYSQL_PASSWORD:mep1GwXJkcRXRsmY}
    driver-class-name: com.mysql.cj.jdbc.Driver
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
  jpa:
    hibernate:
      ddl-auto: none
    show-sql: true
  sql:
    init:
      mode: never
jwt:
  secret: ${JWT_SECRET:}
logging:
  level:
    org.springframework: INFO
```

**与 realtest 的区别：**
- 配置内容相同（真实 MySQL + 真实 Redis 连接参数）
- 区别在测试代码层面：hybrid 模式在测试类中用 `@MockBean` 选择性替换部分 Redis 操作
- Redis 连接参数仍然配置（供 `@Autowired` 注入的真实 Redis 读取使用），但写操作被 `@MockBean` Mock

**hybrid 模式典型用法：**

```java
@SpringBootTest
@ActiveProfiles("hybridtest")
class AuthIntegrationHybridTest {
    @Autowired private AuthService authService;

    // 选择性 Mock：Redis 写操作（如验证码存储、登录计数）用 Mock
    // Redis 读操作（如查询缓存数据）仍用真实 Redis
    @MockBean private StringRedisTemplate redisTemplate;
}
```

---

## pom.xml 说明

`mysql-connector-j` 当前为 `runtime` scope。Spring Boot parent POM (`spring-boot-starter-parent 3.3.8`) 配置的 `maven-surefire-plugin` 已包含 runtime scope 依赖在测试 classpath 中，因此 **无需修改 pom.xml scope**。

如遇测试 classpath 找不到 MySQL driver 的问题（非 Spring Boot parent 项目），可添加：

```xml
<!-- 仅在非 Spring Boot parent 项目中需要 -->
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
    <scope>test</scope>
</dependency>
```

---

## 快速参考

| Profile | 命令 | 数据库 | Redis | 配置文件 |
|---------|------|--------|-------|---------|
| mock（默认） | `mvn test` | H2 | @Mock | `application.yml`（已有） |
| real | `mvn test -Dspring.profiles.active=realtest` | MySQL | 真实 | `application-realtest.yml` |
| hybrid | `mvn test -Dspring.profiles.active=hybridtest` | MySQL | 选择性 @MockBean | `application-hybridtest.yml` |