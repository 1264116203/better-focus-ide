# Java 代码风格规范（JDK 21+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 修改时优先采用最小可行改动

---

## 1. JDK 21+ 特性使用

### 1.1 必须使用的新特性

| 特性 | 说明 | 示例 |
|------|------|------|
| Record 类 | 不可变数据载体，替代 DTO 场景中的 Lombok @Data | `public record UserVO(Long id, String name)` |
| Sealed Classes | 限定子类继承，用于异常体系、状态枚举 | `sealed interface BizErrorCode permits AuthErrorCode, UserErrorCode` |
| Pattern Matching for switch | switch 类型匹配 + 模式变量 | `switch (obj) { case String s -> ...; case Integer i -> ...; }` |
| Virtual Threads (Loom) | 虚拟线程用于 I/O 密集型场景 | `Executors.newVirtualThreadPerTaskExecutor()` |
| Text Blocks | 多行字符串（SQL、JSON） | `String sql = """SELECT * FROM user WHERE id = ?"""` |
| String Templates (Preview) | 字符串模板（注意是 preview 特性） | `STR."Hello \{name}"` |

### 1.2 禁止使用的旧模式

| 禁止模式 | 替换方案 | 原因 |
|----------|----------|------|
| `instanceof` + 强制转换 | Pattern Matching for instanceof | JDK 16+ 支持，更简洁安全 |
| 传统 switch 语句（无箭头） | switch 箭头表达式 | 更清晰，避免穿透 |
| 匿名内部类（简单函数式接口） | Lambda 表达式 | 更简洁 |
| `final` 常量类模拟枚举 | `enum` 或 `sealed interface` | 语义更明确 |
| Lombok @Data/@Setter 用于 DTO | Record 或手写不可变 DTO | JDK 21 Record 更安全，无隐式 setter |
| `Executors.newFixedThreadPool()` 等 | 手动构建 `ThreadPoolExecutor` 或虚拟线程 | 项目规范：禁止 JDK 默认线程池 |

---

## 2. 命名规范

### 2.1 统一规则

| 类型 | 风格 | 示例 |
|------|------|------|
| 类名 | PascalCase | `UserService`, `AuthController` |
| 方法名 | camelCase | `findByName`, `checkAccountNotLocked` |
| 变量名 | camelCase | `loginFailCount`, `userToken` |
| 常量名 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT`, `CAPTCHA_TTL_MINUTES` |
| 包名 | 全小写，无下划线 | `com.lingyue.auth.service` |
| 枚举值 | UPPER_SNAKE_CASE | `BizErrorCode.USER_NOT_FOUND` |

**禁止混用驼峰与下划线命名。** 命名需见名知意，禁止 `a`, `b`, `temp`, `data1` 等无意义命名。

### 2.2 方法命名语义约定

| 操作 | 前缀 | 示例 |
|------|------|------|
| 查询单个 | `get` / `find` / `query` | `getUserById`, `findByPhone` |
| 查询列表 | `list` / `query` | `listUsers`, `queryOrders` |
| 查询数量 | `count` | `countByStatus` |
| 新增 | `create` / `save` / `add` | `createUser`, `saveOrder` |
| 修改 | `update` / `modify` | `updateUserStatus` |
| 删除 | `delete` / `remove` | `deleteById` |
| 判断 | `check` / `is` / `has` | `checkAccountNotLocked`, `isActive` |
| 构建 | `build` / `convert` | `buildTokenVO`, `convertToDTO` |

---

## 3. 代码结构

### 3.1 方法长度限制

| 类型 | 上限 | 超出处理 |
|------|------|----------|
| Service 方法 | 30 行 | 拆分为子方法 |
| Controller 方法 | 15 行 | 拆分校验逻辑到 Service |
| 通用方法 | 100 行 | 拆分为子方法 |

### 3.2 import 顺序

```java
// 1. java.* / jakarta.*
import java.util.List;
import jakarta.validation.Valid;

// 2. 第三方库
import org.springframework.web.bind.annotation.*;
import com.baomidou.mybatisplus.core.conditions.*;

// 3. 项目内部
import com.lingyue.auth.dto.request.LoginRequest;
import com.lingyue.auth.service.UserService;

// 4. static import（最后）
import static com.lingyue.auth.constant.AuthConstants.*;
```

### 3.3 类成员排列顺序

```java
public class XxxServiceImpl implements XxxService {
    // 1. 常量（static final）
    // 2. 静态变量
    // 3. 实例变量（注入的 Bean）
    // 4. 构造方法
    // 5. 公有方法（接口定义的方法）
    // 6. 保护/私有方法（子方法、内部方法）
    // 7. 内部类/Record
}
```

---

## 4. 常量管理

### 4.1 分类存放

| 常量类型 | 存放位置 | 示例 |
|----------|----------|------|
| 模块私有常量 | 当前类内部声明 | `private static final int MAX_SIZE = 100;` |
| 跨模块公共常量 | 公共常量类 | `AuthConstants.CAPTCHA_TTL_MINUTES` |
| 业务错误码 | 枚举或 sealed interface | `BizErrorCode.USER_NOT_FOUND` |
| 配置参数 | `application.yml` | `spring.datasource.url` |

**禁止魔术字符**：代码中禁止临时直接使用的硬编码数字/字符串，必须提取为常量或枚举。

---

## 5. 异常处理

### 5.1 统一异常体系

```java
// 业务异常 — 抛出，由 GlobalExceptionHandler 处理
throw new BusinessException(BizErrorCode.USER_NOT_FOUND);

// 需携带额外数据的异常
throw new BusinessException(BizErrorCode.ACCOUNT_LOCKED, remainingMinutes);

// IO/外部调用异常 — 记录日志，不吞掉
try {
    externalService.call();
} catch (Exception e) {
    log.error("External service call failed: {}", e.getMessage(), e);
    throw new BusinessException(BizErrorCode.EXTERNAL_SERVICE_ERROR, e);
}
```

### 5.2 禁止行为

| 禁止 | 原因 |
|------|------|
| `catch (Exception e) {}` 空 catch | 吞掉异常，隐藏问题 |
| `catch (Exception e) { log.error(e.getMessage()); }` | 丢失堆栈信息 |
| `throw new RuntimeException("msg")` | 语义不明，应使用 BusinessException |
| catch 块仅打印不处理 | 必须处理或向上抛出 |

**正确方式：** `log.error("Operation failed: {}", e.getMessage(), e);` — 保留完整堆栈。

---

## 6. 并发与线程

### 6.1 线程池规范

```java
// 禁止：使用 JDK 默认线程池
Executors.newFixedThreadPool(10);  // ❌

// 正确：手动构建 ThreadPoolExecutor
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    corePoolSize, maxPoolSize, keepAliveTime, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(queueCapacity),
    new ThreadFactoryBuilder().setNameFormat("biz-pool-%d").build(),
    new ThreadPoolExecutor.CallerRunsPolicy()  // 队列满时处理策略
);

// JDK 21+ 虚拟线程（适用于 I/O 密集型）
ExecutorService vtExecutor = Executors.newVirtualThreadPerTaskExecutor();
```

### 6.2 Redis 原子操作

```java
// 禁止：非原子 GET+SET
String count = redisTemplate.opsForValue().get(key);
redisTemplate.opsForValue().set(key, String.valueOf(Integer.parseInt(count) + 1));  // ❌

// 正确：使用 INCR 原子命令
Long newCount = redisTemplate.opsForValue().increment(key);  // ✅
```

---

## 7. 数值处理

| 规则 | 说明 |
|------|------|
| 禁止 `double/float` 比大小 | 精度丢失风险，使用 `BigDecimal` |
| `BigDecimal` 比较 | 使用 `compareTo()`，不用 `equals()`（equals 比较 scale） |
| `Integer.parseInt()` 解析外部值 | 必须捕获 `NumberFormatException` |
| Redis TTL 参数 | `StringRedisTemplate.opsForValue().set()` timeout 为 `long`，Mockito `eq()` 必须用 `eq((long) value)` |

---

## 8. 注解使用

### 8.1 JSR 303 校验注解

```java
public record LoginRequest(
    @NotBlank(message = "手机号不能为空")
    @Pattern(regexp = "^1[3-9]\\d{9}$", message = "手机号格式不正确")
    String phone,

    @NotBlank(message = "密码不能为空")
    @Size(min = 6, max = 20, message = "密码长度6-20位")
    String password
) {}
```

Controller 必须使用 `@Valid` 或 `@Validated` 触发校验：

```java
@PostMapping("/login")
public Result<LoginVO> login(@Valid @RequestBody LoginRequest request) { ... }
```

### 8.2 Record vs Lombok

| 场景 | 推荐 | 原因 |
|------|------|------|
| 请求/响应 DTO | Record | 不可变，自带 toString/equals/hashCode，JDK 21+ |
| Entity（需 MyBatis-Plus setter） | 手写或 Lombok @Data | MyBatis-Plus 需 setter，Record 不适用 |
| 敏感字段 toString | `@ToString.Exclude`（Lombok）或手写 | 必须排除 password、phone 等所有敏感字段 |

---

## 9. 日志规范

| 规则 | 说明 |
|------|------|
| 日志框架 | SLF4J + Logback，禁止直接使用 `System.out` |
| 必须包含关键字段 | `log.info("User login: userId={}", userId)` — 支持上下文追踪 |
| 减少无用日志 | 不记录方法开始/结束、无意义耗时 |
| 异常日志 | `log.error("XXX failed: {}", e.getMessage(), e)` — 必须带堆栈 |
| 敏感信息 | 日志中禁止打印密码、token、完整手机号 |

---

## 10. 禁止事项汇总

| 禁止 | 替换 |
|------|------|
| 魔术字符/数字 | 常量或枚举 |
| JDK 默认线程池 | 手动 ThreadPoolExecutor 或虚拟线程 |
| `double/float` 比大小 | `BigDecimal.compareTo()` |
| 空 catch 块 | 记录日志 + 处理/抛出 |
| `Map` 作为方法入参/返回值 | 明确的 DTO/VO |
| `ResponseEntity<T>` 返回类型 | `Result<T>` |
| 通配符 permitAll | 逐个声明路径 |
| 短字符串 JWT Secret | 32字节随机 Base64 |
| `org.example` 包名 | 规范业务包名 |
| Entity 包中放 Service/Controller | 分包存放 |

---

## 最终回复要求

* 说明修改了哪些文件
* 说明核心改动点
* 说明是否执行了校验（`mvn compile` / `mvn test`）
* 说明风险点或后续建议