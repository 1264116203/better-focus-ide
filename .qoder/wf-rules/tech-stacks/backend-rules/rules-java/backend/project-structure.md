# Java 项目结构规范（JDK 21+ / Spring Boot 3.x）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 新功能必须按目录结构放置，不散落

---

## 1. 根目录职责

| 目录/文件 | 职责 | 禁止 |
|-----------|------|------|
| `.qoder/rules/` | AI 开发约束与规则 | 存放业务代码 |
| `src/main/java/` | Java 源代码 | 存放非 Java 文件 |
| `src/main/resources/` | 配置与资源文件 | 存放 Java 代码 |
| `src/test/java/` | 测试代码 | 存放非测试代码 |
| `pom.xml` | Maven 项目配置 | 硬编码敏感信息 |
| `.gitignore` | 排除 target/, dump.rdb, *.class | 排除 src/ |
| `README.md` | 项目说明 | 存放业务逻辑 |

---

## 2. 源码目录结构

```text
src/main/java/com/{company}/{project}/
├── controller/                    # REST 控制器（仅路由+校验+调用Service）
│   └── {Module}Controller.java    # 一个模块一个 Controller
│
├── service/                       # Service 接口 + 实现
│   ├── {Module}Service.java       # 接口定义
│   └── impl/
│       └── {Module}ServiceImpl.java  # 实现类
│
├── mapper/                        # MyBatis/MyBatis-Plus Mapper
│   └── {Module}Mapper.java
│
├── entity/                        # 数据库实体（仅数据结构）
│   └── {Module}.java
│
├── dto/                           # 数据传输对象
│   ├── request/                   # 入参 DTO（含 JSR 303 校验注解）
│   │   └── {Module}Request.java
│   ├── response/                  # 出参 DTO / VO
│   │   └── {Module}Response.java  # 或 {Module}VO.java
│
├── config/                        # Spring 配置类
│   ├── SecurityConfig.java
│   ├── RedisConfig.java
│   └── WebMvcConfig.java
│
├── exception/                     # 异常体系
│   ├── BusinessException.java     # 业务异常
│   ├── BizErrorCode.java          # 错误码枚举/sealed interface
│   └── GlobalExceptionHandler.java # 全局异常处理
│
├── filter/                        # Servlet 过滤器
│   └── JwtAuthenticationFilter.java
│
├── interceptor/                   # Spring 拦截器
│   └── RateLimitInterceptor.java
│
├── util/                          # 工具类
│   ├── JwtUtil.java
│   └── RedisUtil.java
│
├── constant/                      # 常量类
│   ├── AuthConstants.java
│   └── BizConstants.java
│
└── {ProjectApplication}.java      # Spring Boot 启动类
```

---

## 3. 资源目录结构

```text
src/main/resources/
├── application.yml                # 主配置
├── application-dev.yml            # 开发环境
├── application-test.yml           # 测试环境
├── application-prod.yml           # 生产环境（敏感信息用环境变量）
├── mapper/                        # MyBatis XML（仅 MyBatis 项目需要）
│   └── {Module}Mapper.xml
└── db/migration/                  # 数据库迁移脚本（如有）
```

---

## 4. 测试目录结构

```text
src/test/java/com/{company}/{project}/
├── controller/
│   └── {Module}ControllerTest.java
├── service/
│   └── {Module}ServiceTest.java
├── mapper/
│   └── {Module}MapperTest.java
└── integration/                   # 集成测试（如有）
    └── {Module}IntegrationTest.java
```

---

## 5. 包职责红线

| 包 | 允许存放 | 禁止存放 |
|----|---------|---------|
| `entity/` | 数据库实体类 | Service、Controller、Dao Bean |
| `dto/request/` | 入参 DTO + JSR 303 注解 | 业务逻辑方法 |
| `dto/response/` | 出参 DTO / VO | 业务逻辑方法 |
| `controller/` | REST 控制器 | Service 实现、DAO 操作 |
| `service/` | Service 接口 + 实现 | Controller、Entity |
| `mapper/` | Mapper 接口 | Service 逻辑 |
| `config/` | Spring @Configuration 类 | 业务逻辑 |
| `exception/` | 异常类 + 错误码 | Service、Controller |
| `util/` | 工具类（静态方法） | 配置类、常量数据 |
| `constant/` | 常量定义 | 函数方法 |

---

## 6. 新功能放置规则

### 6.1 新增模块

按完整分层添加：
```
controller/{Module}Controller.java
service/{Module}Service.java
service/impl/{Module}ServiceImpl.java
mapper/{Module}Mapper.java
entity/{Module}.java
dto/request/{Module}Request.java
dto/response/{Module}Response.java
```

### 6.2 新增接口（已有模块）

在现有 Controller/Service 中添加方法，不新建类：
```java
// UserController.java 新增方法
@GetMapping("/profile")
public Result<UserProfileVO> getProfile(@PathVariable Long userId) { ... }

// UserService.java 新增方法声明
UserProfileVO getProfile(Long userId);

// UserServiceImpl.java 新增方法实现
```

### 6.3 新增公共能力

项目内复用 ≥ 3 次的逻辑，提取到 `util/` 或独立 Service：
```
util/ → 工具类（纯逻辑，无状态）
service/ → 跨模块共享业务逻辑
```

---

## 7. 类命名约定

| 类型 | 命名模式 | 示例 |
|------|---------|------|
| Controller | `{Module}Controller` | `AuthController` |
| Service 接口 | `{Module}Service` | `UserService` |
| Service 实现 | `{Module}ServiceImpl` | `UserServiceImpl` |
| Mapper | `{Module}Mapper` | `UserMapper` |
| Entity | `{Module}` 或 `{Module}Entity` | `User` |
| Request DTO | `{Module}Request` 或 `{Action}Request` | `LoginRequest` |
| Response DTO / VO | `{Module}Response` 或 `{Module}VO` | `LoginVO` |
| Config | `{Feature}Config` | `SecurityConfig` |
| 常量类 | `{Module}Constants` | `AuthConstants` |
| 工具类 | `{Feature}Util` | `JwtUtil` |
| 错误码 | `{Module}ErrorCode` 或 `BizErrorCode` | `AuthErrorCode` |
| 异常 | `BusinessException` | 项目级统一 |

---

## 8. 文件创建/修改要求

| 操作 | 要求 |
|------|------|
| 新建类 | 必须放在正确的包中，包名见名知意 |
| 新建接口 | 必须有对应实现类 |
| 新建 DTO | Request DTO 必须带 JSR 303 校验注解 |
| 新建 Entity | 必须有表注释、字段注释、审计字段 |
| 新建 Config | 必须使用 `@Configuration`，方法命名清晰 |
| 修改类 | 不修改与本次任务无关的方法 |
| 删除类 | 必须确认无引用后再删，不遗漏 import |

---

## 9. 禁止事项

| 禁止 | 原因 |
|------|------|
| `org.example` 包名 | 无效包名，必须使用规范业务包名 |
| Entity 包中放 Service/Controller | 违反分层原则 |
| DTO 中放业务逻辑方法 | DTO 仅是数据载体 |
| 散落的工具方法（多个类重复实现） | 提取到 util/ |
| Controller 直接操作 Mapper | 必须经过 Service 层 |
| Service 直接返回 Entity | 必须转换为 DTO/VO |
| `Map` 作为方法入参/返回值 | 使用明确的 DTO/VO |

---

## 自检清单

- [ ] 新类是否放在了正确的包中？
- [ ] 新类命名是否符合约定？
- [ ] 新 Request DTO 是否包含 JSR 303 校验注解？
- [ ] Entity 是否包含字段注释和审计字段？
- [ ] 是否遵循了分层依赖方向（Controller → Service → Mapper）？
- [ ] 是否没有跨层调用（Controller → Mapper）？
- [ ] 修改是否仅限于本次任务相关的方法？

---

## 最终回复要求

* 说明新增/修改了哪些文件及其所在包
* 说明文件放置是否符合目录结构规范
* 说明是否存在需要后续处理的架构问题