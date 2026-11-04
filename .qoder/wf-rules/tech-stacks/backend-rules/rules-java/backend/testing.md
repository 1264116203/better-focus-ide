# Java 校验与测试规范（JDK 21+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 修改文件后优先做语法检查
> * 校验遵循最小必要原则，非必要不跑全量测试

---

## 1. 校验优先级

| 变更规模 | 必须校验 | 推荐校验 | 可选校验 |
|----------|---------|---------|---------|
| 小改动（≤3 文件，≤20 行） | `mvn compile` | 相关单测 | 全量测试 |
| 中改动（3-10 文件） | `mvn compile` + 相关单测 | `mvn test -Dtest=ClassName` | 全量 `mvn test` |
| 大改动（>10 文件） | `mvn compile` + `mvn test` | 全量 `mvn test` | 集成测试 |

---

## 2. 基础校验原则

### 2.1 编译检查

```bash
mvn compile                           # 必须通过，类型安全第一
mvn compile -pl {module}              # 单模块编译（多模块项目）
```

**编译失败分类：**

| 类型 | 处理方式 |
|------|---------|
| 代码问题（语法、类型） | 修复代码 |
| 环境问题（JDK 版本） | 提示开发者 |
| 工具缺失（Maven 插件） | 提示开发者 |
| 历史遗留（其他模块报错） | 仅关注本次改动涉及的模块 |

### 2.2 单元测试

```bash
mvn test -Dtest=AuthServiceTest       # 运行单个测试类
mvn test -Dtest=AuthServiceTest#login  # 运行单个测试方法
mvn test                               # 运行所有测试
```

---

## 3. 校验内容清单

### 3.1 Java 特定校验

| 校验项 | 检查方式 |
|--------|---------|
| 类型安全 | `mvn compile` 编译通过 |
| JSR 303 校验注解 | 检查 Request DTO 是否有 `@Valid` + 校验注解 |
| null 安全 | 检查方法是否处理了可能的 null 返回值 |
| 异常处理 | 检查 catch 块是否记录完整异常信息 |
| 常量使用 | 检查是否有硬编码数字/字符串（魔术字符） |

### 3.2 Spring Boot 特定校验

| 校验项 | 检查方式 |
|--------|---------|
| SecurityConfig permitAll | 检查是否逐个声明路径，而非通配符 |
| JWT Secret 长度 | 检查是否 ≥ 256 位 |
| @ToString 排除 | 检查是否排除所有敏感字段 |
| Service 方法长度 | 检查是否 ≤ 30 行 |
| Redis 原子操作 | 检查是否有非原子 GET+SET |
| Result<T> 返回类型 | 检查 Controller 是否使用 Result<T> 而非 ResponseEntity |

### 3.3 数据库校验

| 校验项 | 检查方式 |
|--------|---------|
| Entity 字段注释 | 检查每个字段是否有注释 |
| 审计字段 | 检查是否有 creator/updater/create_time/update_time |
| BigDecimal 使用 | 检查金额/数值是否用 BigDecimal 而非 double |
| 索引合理性 | 大数据量表必须有索引 |

---

## 4. 测试编写规范

### 4.1 测试类命名

| 测试类型 | 命名 | 示例 |
|----------|------|------|
| 单元测试 | `{Class}Test` | `AuthServiceTest` |
| Controller 测试 | `{Controller}Test` | `AuthControllerTest` |
| Mapper 测试 | `{Mapper}Test` | `UserMapperTest` |
| 集成测试 | `{Module}IntegrationTest` | `AuthIntegrationTest` |

### 4.2 测试方法命名

```java
// 格式：method_scenario_expectedResult
@Test
void login_validCredentials_returnsLoginVO() { ... }

@Test
void login_lockedAccount_throwsBusinessException() { ... }

@Test
void getUserInfo_nonExistentUserId_throwsBusinessException() { ... }
```

### 4.3 测试覆盖要求

> 下表为测试设计建议值；实际质量门禁阈值以 `.qoder/wf-dev.yaml` 的 `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`），验证时读取校验。

| 类型 | 最低覆盖率 | 说明 |
|------|-----------|------|
| Service 核心方法 | 80% | 登录、权限校验等关键逻辑 |
| Controller | 60% | 主要是参数校验和路由 |
| Mapper/DAO | 50% | 简单 CRUD 可适当降低 |
| 工具类 | 90% | 纯逻辑，易于测试 |

### 4.4 Mock 使用约定

```java
// 推荐：Mockito + Spring Boot Test
@ExtendWith(MockitoExtension.class)
class AuthServiceTest {
    @Mock
    private UserMapper userMapper;
    @Mock
    private StringRedisTemplate redisTemplate;

    @InjectMocks
    private AuthServiceImpl authService;

    @Test
    void login_validCredentials_returnsLoginVO() {
        when(userMapper.findByPhone("13800138000")).thenReturn(mockUser);
        // ...
    }
}
```

**Mockito 红线：**

| 规则 | 说明 |
|------|------|
| `eq()` 参数类型必须匹配 | Redis TTL 为 `long`，必须用 `eq((long) value)` |
| 不 Mock 被测类本身 | Mock 依赖，不 Mock Service 自身方法 |
| 不 Mock 数据库验证逻辑 | 数据库相关测试优先使用真实 DB 或 @DataJpaTest |

---

## 5. 校验范围控制

| 规则 | 说明 |
|------|------|
| 仅校验与本次改动相关的模块 | 不跑无关模块的测试 |
| 优先最小范围校验 | `mvn compile` > 单测 > 全量测试 |
| 校验失败先分类 | 区分代码问题 vs 环境问题 vs 历史遗留 |
| 非必要不跑全量 build | 仅在质量门禁时跑全量 |

---

## 6. 推荐校验策略

| 改动类型 | 推荐校验流程 |
|----------|-------------|
| Service 方法修改 | `mvn compile` → `mvn test -Dtest={Service}Test` |
| Controller 修改 | `mvn compile` → `mvn test -Dtest={Controller}Test` |
| Entity/DTO 修改 | `mvn compile` → 检查相关 Service 单测 |
| Config/Security 修改 | `mvn compile` → `mvn test`（影响面大） |
| Mapper/SQL 修改 | `mvn compile` → `mvn test -Dtest={Mapper}Test` |

---

## 7. 禁止事项

| 禁止 | 原因 |
|------|------|
| 跳过编译直接提交 | 类型安全是第一道防线 |
| 空 catch 块测试 | 测试必须验证异常场景 |
| Mock 被测类自身 | 失去测试意义 |
| 仅测成功路径 | 必须覆盖异常和边界场景 |
| 全量 build 作为日常校验 | 耗时长，日常仅校验相关模块 |

---

## 8. 测试环境模式 (test_env)

工作流支持三种测试环境模式（mock / real / hybrid），由 AI 按场景确定（见 ss-tdd-cycle 前置条件 test_env）。模式决定测试代码的注解方式、数据库连接和缓存策略。

| 模式 | 数据库 | Redis | Spring 上下文 | 适用场景 |
|------|--------|-------|--------------|---------|
| **mock**（默认） | H2 内存库 | Mockito @Mock | 局部（@WebMvcTest 等） | 日常开发迭代 |
| **real** | MySQL（RDS） | 本地 Redis | 全量（@SpringBootTest + realtest profile） | 发布前验证 |
| **hybrid** | MySQL（RDS） | @MockBean（选择性） | 全量（@SpringBootTest + hybridtest profile） | 定向集成测试 |

### 8.1 mock 模式

当前默认模式，所有测试使用 H2 内存数据库和 Mockito Mock：

```java
@ExtendWith(MockitoExtension.class)
class AuthServiceTest {
    @Mock private UserMapper userMapper;
    @Mock private StringRedisTemplate redisTemplate;
    @InjectMocks private AuthServiceImpl authService;
}
```

测试命令：`mvn test`（使用默认 `src/test/resources/application.yml`，H2 配置）

### 8.2 real 模式

使用真实 MySQL 和 Redis，验证生产环境兼容性：

```java
@SpringBootTest
@ActiveProfiles("realtest")
class AuthIntegrationRealTest {
    @Autowired private AuthService authService;
    @Autowired private StringRedisTemplate redisTemplate;
}
```

测试命令：`mvn test -Dspring.profiles.active=realtest`

**real 模式注意事项：**
- 必须创建 `src/test/resources/application-realtest.yml`（模板见 `{COJOY_HARNESS_SHARED_BASE}/rules/backend-rules/rules-java/backend/test-profile-templates.md`）
- MySQL 和 Redis 必须可连接（环境变量或 application-realtest.yml 配置）
- 必须包含数据库连通性验证 TC 和 Redis 连通性验证 TC
- `mysql-connector-j` runtime scope 在 Spring Boot parent POM 下已包含在测试 classpath，无需修改 pom.xml scope

### 8.3 hybrid 模式

真实 MySQL + 选择性 Mock Redis（适合需要验证数据库逻辑但 Mock 缓存写入的场景）：

```java
@SpringBootTest
@ActiveProfiles("hybridtest")
class AuthIntegrationHybridTest {
    @Autowired private AuthService authService;
    @MockBean private StringRedisTemplate redisTemplate; // 选择性 Mock Redis 写操作
}
```

测试命令：`mvn test -Dspring.profiles.active=hybridtest`

**hybrid 模式注意事项：**
- 必须创建 `src/test/resources/application-hybridtest.yml`（模板见 `{COJOY_HARNESS_SHARED_BASE}/rules/backend-rules/rules-java/backend/test-profile-templates.md`）
- 单元测试 TC 仍使用 `@ExtendWith(MockitoExtension.class)`；集成测试 TC 使用 `@SpringBootTest+@ActiveProfiles("hybridtest")`
- 每个 TC 必须标注使用哪种注解方式

### 8.4 模式选择原则

- `mock`：日常开发，快速迭代，CI 无外部依赖
- `real`：发布前验证，捕获生产环境配置/连接/schema 问题
- `hybrid`：定向验证（如验证数据库逻辑但 Mock 缓存），平衡速度与真实性
- 默认 `mock`（AI 未指定时）
- `real`/`hybrid` 模式需要 MySQL 和 Redis 基础设施可用

---

## 最终回复要求

* 说明执行了哪些校验命令
* 说明校验结果（通过/失败）
* 说明失败原因及处理方式
* 如未执行校验，说明原因