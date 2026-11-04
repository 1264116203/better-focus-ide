# Spring Boot 使用规范（3.x / JDK 17+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 遵循项目已有封装和使用习惯

---

## 1. Spring Boot 核心约定

### 1.1 启动类

```java
@SpringBootApplication(exclude = {DataSourceAutoConfiguration.class})  // 按需排除
public class AuthApplication {
    public static void main(String[] args) {
        SpringApplication.run(AuthApplication.class, args);
    }
}
```

- 启动类放在根包下，`@SpringBootApplication` 自动扫描同包及子包
- 不要在启动类中写业务逻辑

### 1.2 配置文件

```yaml
# application.yml — 公共配置
server:
  port: 8080

# application-dev.yml — 开发环境（本地数据库等）
# application-prod.yml — 生产环境（敏感信息用环境变量 ${DB_PASSWORD}）
```

- **禁止硬编码敏感信息**：数据库密码、JWT Secret 使用 `${ENV_VAR}` 或配置中心
- **禁止硬编码 localhost**：生产配置使用环境变量
- 配置优先级：环境变量 > profile yml > 默认 yml

---

## 2. Controller 规范

### 2.1 基本结构

```java
@RestController
@RequestMapping("/api/auth")
@Validated
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    public Result<LoginVO> login(@Valid @RequestBody LoginRequest request) {
        return Result.success(authService.login(request));
    }

    @GetMapping("/user-info")
    public Result<UserInfoVO> getUserInfo(@PathVariable Long userId) {
        return Result.success(authService.getUserInfo(userId));
    }
}
```

### 2.2 Controller 红线

| 规则 | 说明 |
|------|------|
| 返回类型统一 `Result<T>` | 禁止 `ResponseEntity<T>` |
| 使用构造器注入 | 禁止 `@Autowired` 字段注入 |
| 参数校验用 `@Valid` | 禁止在 Controller 中手写校验逻辑 |
| 不含业务逻辑 | Controller 只做路由+校验+调用Service |
| 路径以 `/api/` 开头 | RESTful 风格 |
| 一个模块一个 Controller | 不跨模块调用无关 Service |

---

## 3. Service 规范

### 3.1 接口与实现分离

```java
// 接口
public interface AuthService {
    LoginVO login(LoginRequest request);
    UserInfoVO getUserInfo(Long userId);
}

// 实现
@Service
@Slf4j
public class AuthServiceImpl implements AuthService {

    private final UserMapper userMapper;
    private final RedisTemplate<String, String> redisTemplate;

    public AuthServiceImpl(UserMapper userMapper, RedisTemplate<String, String> redisTemplate) {
        this.userMapper = userMapper;
        this.redisTemplate = redisTemplate;
    }

    @Override
    public LoginVO login(LoginRequest request) {
        User user = checkUserExists(request.phone());
        checkAccountNotLocked(user);
        LoginVO vo = buildTokenVO(user);
        return vo;
    }

    // 子方法拆分
    private User checkUserExists(String phone) { ... }
    private void checkAccountNotLocked(User user) { ... }
    private LoginVO buildTokenVO(User user) { ... }
}
```

### 3.2 Service 红线

| 规则 | 说明 |
|------|------|
| 方法 ≤ 30 行 | 超出拆分为子方法 |
| 跨服务调用禁止 `@Transactional` | 通过消息队列等方式保证一致性 |
| 不直接返回 Entity | 必须转换为 DTO/VO |
| 构造器注入 | 禁止 `@Autowired` 字段注入 |
| 事务方法尽量简短 | 不包含复杂长流程业务代码 |

---

## 4. Spring Security 规范

### 4.1 SecurityConfig

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                // ❌ 禁止通配符匹配需认证的子路径
                // .requestMatchers("/api/auth/**").permitAll()
                // ✅ 逐个声明
                .requestMatchers("/api/auth/captcha", "/api/auth/login", "/api/auth/register").permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(jwtAuthenticationFilter(), UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
}
```

**核心红线:** `requestMatchers("/api/auth/**").permitAll()` 会匹配所有子路径包括 `/api/auth/user-info`、`/api/auth/logout` 等需认证的接口。必须逐个声明 permitAll 路径。

### 4.2 JWT 过滤器

```java
@Component
@Slf4j
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String token = extractToken(request);
        if (token != null && jwtUtil.validateToken(token)) {
            SecurityContextHolder.getContext().setAuthentication(buildAuthentication(token));
        }
        filterChain.doFilter(request, response);
    }
}
```

- JWT Secret ≥ 256 位（32 字节随机密钥 Base64），用 `openssl rand -base64 32` 生成
- Token 过期/无效时不清除 SecurityContext，让后续 401 处理接管

---

## 5. 数据访问规范

### 5.1 MyBatis-Plus

```java
@Mapper
public interface UserMapper extends BaseMapper<User> {
    // 自定义查询仅在 BaseMapper 方法不够用时添加
}
```

- Entity 使用 `@TableName`, `@TableId`, `@TableField` 注解
- 自动填充审计字段：`MyMetaObjectHandler` 处理 `create_time`, `update_time`, `creator`, `updater`
- 详细数据库规范见 database.md

### 5.2 MyBatis（XML 映射）

```xml
<!-- UserMapper.xml — 仅在复杂 SQL 时使用 -->
<select id="findByPhoneWithRoles" resultType="com.lingyue.auth.entity.User">
    SELECT u.*, r.name as role_name FROM user u LEFT JOIN role r ON u.role_id = r.id
    WHERE u.phone = #{phone}
</select>
```

- 禁止 `select *`，必须指定字段
- Mapper XML 文件放在 `resources/mapper/` 下

---

## 6. Redis 规范

### 6.1 使用方式

```java
@Service
public class AuthServiceImpl implements AuthService {
    private final StringRedisTemplate redisTemplate;

    // 正确：原子操作
    public Long incrementLoginFailCount(String phone) {
        String key = LOGIN_FAIL_COUNT_PREFIX + phone;
        Long count = redisTemplate.opsForValue().increment(key);
        if (count != null && count == 1) {
            redisTemplate.expire(key, LOGIN_FAIL_TTL_MINUTES, TimeUnit.MINUTES);
        }
        return count;
    }

    // 禁止：非原子 GET+SET
    // String count = redisTemplate.opsForValue().get(key);
    // redisTemplate.opsForValue().set(key, String.valueOf(Integer.parseInt(count) + 1));  // ❌
}
```

### 6.2 Redis 红线

| 规则 | 说明 |
|------|------|
| 普通 Key 必须设置 TTL | 固定大小 Value 可豁免，但需登记 |
| 无法设置有效期的场景 | 需更换实现方案，禁止无限增长 Key 无 TTL |
| 禁止耗时 > 20ms 操作 | 大 Value/大集合禁用 `hgetall`, `keys *` |
| 禁止 Redis 交集/并集等复杂计算 | 计算逻辑应在应用层处理，不应由 Redis 承担 |
| `opsForValue().set()` timeout 为 `long` | Mockito `eq()` 必须用 `eq((long) value)` |
| 禁止非原子 GET+SET | 使用 `INCR` 等原子命令 |
| `Integer.parseInt()` 解析 Redis 值 | 必须捕获 `NumberFormatException` |

---

## 7. 异常体系

### 7.1 BizErrorCode（JDK 17+ sealed interface 或 enum）

```java
// 推荐：sealed interface（语义更精确，JDK 17 标准特性）
public sealed interface BizErrorCode permits AuthErrorCode, UserErrorCode {
    String code();
    String message();
    int httpStatus();
}

public final class AuthErrorCode implements BizErrorCode {
    public static final AuthErrorCode USER_NOT_FOUND = new AuthErrorCode("40001", "用户不存在", 400);
    public static final AuthErrorCode ACCOUNT_LOCKED = new AuthErrorCode("40002", "账户已锁定", 403);

    private final String code;
    private final String message;
    private final int httpStatus;
    // constructor, getters...
}

// 或传统 enum（更简单）
public enum BizErrorCode {
    USER_NOT_FOUND("40001", "用户不存在", 400),
    ACCOUNT_LOCKED("40002", "账户已锁定", 403);
}
```

**红线:** 错误码必须语义准确。按 `userId` 查不到用户不应使用 `PHONE_NOT_REGISTERED`，需定义 `USER_NOT_FOUND`。

**补充红线:** 业务校验错误码和下游调用错误码必须区分定义。例如：用户输入校验失败（40001-40012）与外部服务调用失败（50001-50012）应使用不同范围的状态码，并在设计文档中明确分类。

### 7.2 GlobalExceptionHandler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public Result<Object> handleBusinessException(BusinessException e) {
        log.warn("Business error: code={}, message={}", e.getErrorCode().code(), e.getMessage());
        return Result.fail(e.getErrorCode(), e.getMessage(), e.getData());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<Object> handleValidationException(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldErrors().stream()
            .map(f -> f.getField() + ": " + f.getDefaultMessage())
            .collect(Collectors.joining("; "));
        return Result.fail("40000", message, null);
    }

    @ExceptionHandler(Exception.class)
    public Result<Object> handleUnknownException(Exception e) {
        log.error("Unexpected error: {}", e.getMessage(), e);
        return Result.fail("50000", "Internal server error", null);  // 不暴露堆栈
    }
}
```

---

## 8. 已知陷阱（必须避免）

| # | 陷阱 | 解决方案 |
|---|------|----------|
| 1 | Kaptcha 2.3.3 在阿里云镜像不可用 | 必须用 2.3.2，`new DefaultKaptcha()` + `setConfig(config)` |
| 2 | MySQL JDBC `characterEncoding=utf8mb4` 抛异常 | 必须用 `UTF-8`（Java charset 名） |
| 3 | Redis TTL 参数类型为 `long`，Mockito `eq(int)` 类型不匹配 | 使用 `eq((long) value)` |
| 4 | `requestMatchers("/api/auth/**").permitAll()` 匹配所有子路径 | 逐个声明 permitAll 路径 |
| 5 | JWT Secret 用短字符串 | 必须 ≥ 256 位，用 `openssl rand -base64 32` |
| 6 | `@ToString` 只排除 password | 必须排除所有敏感字段（password + phone） |
| 7 | `BizErrorCode` 语义不准 | 不同错误对应不同状态码 |
| 8 | Service 方法超过 30 行 | 拆分为子方法 |
| 9 | Redis GET+SET 非原子操作 | 使用 INCR 原子命令 |
| 10 | `Integer.parseInt()` 解析 Redis 值无捕获 | 必须捕获 `NumberFormatException` |
| 11 | 缺少 .gitignore + 硬编码敏感配置 | .gitignore 必须排除 target/、dump.rdb；敏感配置使用环境变量或配置中心 |

---

## 9. 日志规范

- 详细日志规范见 logging.md

---

## 10. 监控规范

- 详细监控规范见 monitoring.md

---

## 最终回复要求

* 说明使用了哪些 Spring Boot 特性
* 说明是否符合 Controller/Service/Security 规范
* 说明是否对照已知陷阱做了检查
* 说明风险点或后续建议