# 项目协作规范（Java 版 — JDK 17+）

> **入口文件**：本文件是 wf-dev 技术栈规则（Java 17）的入口，由编码类技能（ss-tdd-cycle）按 SKILL.md「规则依赖」读取。详细编码/结构/测试规范按需读取下方索引文件，不在本文件重复维护。

## 语言

* 默认使用中文交流、解释、总结和变更说明。
* 代码中的命名、文件名、类名、方法名保持英文规范。
* 除非我明确要求，否则不要切换其它语言回复。

## 项目目标

* 这是一个 Java 后端项目，必须完全遵循现有技术栈、目录结构。
* 如业务需要其他技术栈，需要经过我的允许，由我来决定。
* 修改时优先采用最小可行改动，不做无关重构。

## 修改原则

* 遇到不确定逻辑时，先查看调用链、Controller 入口、Service 依赖、数据库表结构，再修改。
* 先理解上下文，再改代码；避免未经确认的大范围重构。
* 修改时尽量复用现有 Service 方法、工具类、常量定义和约定。
* 优先做最小可行修改，保持现有行为兼容。
* 不要顺手修改与当前任务无关的逻辑；发现潜在问题可在最终总结中提示，不擅自扩大改动范围。
* 不要为了"更优雅"而改变已有稳定行为。
* 修改公共 Service/工具类时，检查受影响调用方。

## 技术栈

* JDK 17（禁止使用 JDK 21+ 专属特性）/ Spring Boot 3.x / Maven
* MyBatis-Plus 或 MyBatis / MySQL 8.x
* Redis（Spring Data Redis + Lettuce）/ JWT（jjwt 0.12.x）
* SLF4J + Logback

## JDK 17+ 特性边界

**可使用（JDK 16+ / 17 已标准化的特性）：**
- Record 类（JDK 16+ 标准）
- Sealed Classes（JDK 17 标准）
- Pattern Matching for instanceof（JDK 16+ 标准）
- Text Blocks（JDK 15+ 标准）
- switch 箭头表达式（JDK 14+ 标准）

**禁止使用（JDK 21+ 专属，JDK 17 项目不可用）：**
- Pattern Matching for switch → 替代：传统 switch + instanceof
- Virtual Threads → 替代：手动 ThreadPoolExecutor
- String Templates → 替代：String.format() 或拼接

详细说明见 `backend/code-style.md` Section 1

## 统一响应格式

所有 API 必须使用 `Result<T>` 统一包装返回数据：

```json
{
  "code": 200,
  "message": "success",
  "data": T | null
}
```

* 成功响应：`Result.success(data)` 或 `Result.success()`，HTTP 200
* 业务错误：抛出 `BusinessException`，由 `GlobalExceptionHandler` 自动包装，HTTP 状态码由 `BizErrorCode.httpStatus` 决定
* 需携带额外信息的错误：通过 `BusinessException(data)` + `Result.fail(errorCode, message, data)` 传递结构化数据
* 验证错误（JSR 303）：`GlobalExceptionHandler` 处理，HTTP 400，message 包含字段名+错误信息
* 未知异常：HTTP 500，message="Internal server error"，不暴露堆栈

## 规则文件索引（路径以 `.qoder/wf-rules/tech-stacks/` 为基准）

| 文件 | 内容 | 按需读取时机 |
|------|------|-------------|
| `backend-rules/rules-java-17/backend/code-style.md` | 编码风格（JDK 17+ 版本） | 编码与代码审查 |
| `backend-rules/rules-java-17/backend/project-structure.md` | 项目目录结构与职责（JDK 17+ 版本） | 编码与结构评审 |
| `backend-rules/rules-java-17/backend/spring-boot.md` | Spring Boot 规范：Controller/Service/安全/Redis/异常 | 编码与审查 |
| `backend-rules/rules-java-17/backend/database.md` | 数据库使用规范（MySQL） | 涉及建表/SQL 时 |
| `backend-rules/rules-java-17/backend/testing.md` | 测试规范（test_env 模式选择） | ss-tdd-cycle / ss-test-run |
| `backend-rules/rules-java-17/backend/backend-versions-template.md` | 后端依赖版本清单+验证指南（单一真实来源） | 涉及依赖版本时 |
| `backend-rules/rules-java-17/backend/sonarqube.md` | SonarQube 质量门禁（JDK 17+ 版本） | ss-test-run |

**共享文件（与 rules-java 相同，引用 `backend-rules/rules-java/backend/` 下的同名文件，不重复维护）：**
- `logging.md`（日志输出规范）/ `monitoring.md`（监控预警响应规范）/ `mq.md`（消息队列使用规范）/ `clickhouse.md`（ClickHouse 使用规范）/ `test-profile-templates.md`（测试配置模板）/ `phase4-6-backend-dependencies.md`（验证依赖安装指引）

## 加载协议

* **编码类技能**（ss-tdd-cycle）：读本文件 + `code-style.md` + `project-structure.md` + `spring-boot.md`。
* **验证类技能**（ss-tdd-cycle / ss-test-run）：读 `testing.md` / `test-profile-templates.md` / `phase4-6-backend-dependencies.md` / `sonarqube.md`。覆盖率由 `ss-test-run` 按 yaml 校验。
* 覆盖率阈值以 `.qoder/wf-dev.yaml` 的 `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`），不在规则文件中硬编码。

## 校验原则

* 修改文件后，优先做语法检查或编译检查。
* 如果项目已有 test / build 命令，优先执行与当前改动最相关、最小范围的校验。
* 校验失败时，要区分代码问题、环境问题、工具缺失还是历史遗留问题。
* 非必要不跑全量 `mvn clean package`。

## 文件编辑方式

* 创建或修改 Java、YAML、XML 配置内容时，优先直接编辑文件。
* 尽量不要使用 bash 的 echo/printf 内联大段代码写文件。
* 避免执行带大量引号和花括号的单行 shell 命令，减少权限与安全拦截。

## 最终回复格式

* 说明改了哪些文件
* 说明核心改动点
* 说明是否执行了校验
* 说明风险点或后续建议
