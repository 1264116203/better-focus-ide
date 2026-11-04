---
trigger: glob
glob: src/test/**/*.java
---

## 框架与依赖

1. 用 junit 5或者6, assertj, mockito, springboot-test 测试框架
2. 代码变更需通过 **单元测试覆盖**（测试覆盖率 ≥ 80%）
3. 用 MockMvc 测试 web 层
4. 用 @SpringBootTest 实现集成测试
5. 覆盖率阈值：新增代码 100%（强制）；整体代码 enhanced ≥70%，basic ≥关键路径覆盖。

## 测试结构与命名
- 测试类命名：被测类名 + `Test` 后缀（例如 `UserServiceTest.java`）
- 测试方法命名：
  - 采用 `{被测试方法名}_shouldSuccess[_when_条件]` 格式（例如 `saveUser_shouldSuccess_when_validIdProvided`）
  - 采用 `{被测试方法名}_should_预期结果[_when_条件]` 格式（例如 `saveUser_should_throwException_when_inValidIdProvided`）
- 结构组织：使用 `@Nested` 注解按业务场景或方法对测试用例进行分组，使用 `@DisplayName` 提供清晰的中文或英文测试描述

## 用例覆盖要求
针对每个被测方法，必须至少生成以下三类测试用例：
- **正常路径 (Happy Path)**：验证核心业务逻辑在合法输入下的正确返回
- **边界条件 (Edge Cases)**：验证空集合、零值、超长字符串、最大/最小值等临界状态。
- **异常分支 (Exception Handling)**：验证非法参数、空指针、业务规则冲突等场景下，是否正确抛出预期的自定义异常或系统异常。使用 `assertThatThrownBy` 或 `assertThrows` 进行断言。

## Spring Boot 专项约束
- 若测试涉及 Spring 容器上下文（如 Repository 层或集成测试），必须添加 `@SpringBootTest` 注解
- 若测试仅涉及纯业务逻辑，必须使用 `@ExtendWith(MockitoExtension.class)` 并配合 `@Mock` 和 `@InjectMocks`，严禁启动整个 Spring 容器以保障测试执行速度。
- 涉及数据库操作时，优先使用 H2 内存数据库，禁止连接生产或测试环境真实数据库。

### 5. 代码质量与安全
- 测试数据应独立构造，禁止依赖外部静态状态或全局变量。
- 对于时间敏感的数据，使用固定时间戳或注入 `Clock` 对象，避免测试因时间流逝而失败。


