---
name: ss-tdd-cycle
description: 红-绿-重构 TDD 循环 + 测试文档化。先写失败测试驱动实现，完成后产出 test-cases.md 规划文档。铁律：没有失败测试就不写实现代码。可独立用于任意功能点或 bug 修复。测试必须验证行为而非实现细节，覆盖正常路径、异常路径与边界条件。
allowed-tools: Read, Write, SearchReplace, Bash, Grep, Glob
---

# ss-tdd-cycle — TDD 红绿重构 + 测试文档化

**阶段**: dev/test | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 有明确功能点验收标准，或 bug 的可复现条件。
- 文档化步骤需有 design.md 或实现代码；确定 test_env（mock/real/hybrid）。
- 【执行环境】本技能由主 agent 会话内串行执行，**禁止通过 subagent（Agent 工具）代理**；工作流模式下每 task 循环结束立即由编排器写 task 完成标记，禁止批量补写。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `coverage.new_code` → 新增代码覆盖率阈值（默认 100%）
- `coverage.overall` → 整体覆盖率阈值（默认 70%）

未读取配置文件不得开始执行。

## 规则依赖（按需读取）
执行前按需 Read（路径以 `.qoder/` 为基准，缺失则跳过）：
- `wf-rules/coding-standards.md` — 通用编码规范
- `wf-rules/coding-standards-<stack>.md` — 栈扩展规范（按项目技术栈：java/python/vue）

## 输入
- `--slug <feature-slug>`（可选）
- 功能点/任务描述由用户 prompt 或编排器给出；bug 修复场景自动读取 `WORKFLOW_DIR/rootcause.md`
- 工作流模式下自动读取 `WORKFLOW_DIR/tasks.md`；骨架阶段已产出时同时读取 `WORKFLOW_DIR/scaffold-manifest.md` 及 task 涉及的目标骨架文件（见第一阶段第 0 步）

## 测试质量标准

### 好测试的特征

- **验证行为，不验证实现**：通过公开接口观测结果，代码内部重构后测试不应 break。
- **读起来像规格说明**：测试名描述"做什么"（`用户可以凭有效购物车结账`），而非"怎么做"。
- **期望值来自独立真相源**：已知正确的字面量、手工推演的示例、规格文档——不可用与实现相同的算法重新计算期望值。
- **一个测试一个逻辑断言**：每个测试只验证一个行为点。
- **存活于重构**：内部结构改变但行为不变时，测试仍绿。

### 反模式（禁止出现）

| 反模式 | 特征 | 修正 |
|---|---|---|
| **实现耦合** | mock 内部协作者、测私有方法、断言调用次数/顺序 | 改为通过公开接口验证可观测行为 |
| **同义反复** | 期望值用与代码相同逻辑计算（`expect(add(a,b)).toBe(a+b)`） | 用独立字面量或规格中的已知值 |
| **水平切片** | 一次写完所有测试再写实现 | 严格垂直切片：一个测试 → 一个实现 → 下一个测试 |
| **绕过接口验证** | 调 API 后直接查 DB 断言，而非通过接口读回 | 通过同一公开接口验证（写后读） |

### Mock 规则

**只在系统边界 mock**：
- 外部 API（支付、邮件、第三方服务）
- 时间 / 随机数
- 文件系统（必要时）

**禁止 mock**：
- 自己的类 / 模块 / 内部协作者
- 任何你控制的代码

mock 时优先使用依赖注入，使外部依赖可替换；优先 SDK 风格接口（每个外部操作一个具名函数），避免通用 fetcher 导致 mock 中写条件分支。

## 边界条件覆盖要求

每个功能点/修复，除正常路径外，**必须**覆盖以下边界类别（按适用性选取）：

| 类别 | 示例 |
|---|---|
| **空/零值** | null、空字符串、空集合、0、Optional.empty |
| **极值** | Integer.MAX_VALUE、Long.MIN_VALUE、最大长度字符串、集合容量上限 |
| **Off-by-one** | 分页首页/末页、数组首尾索引、循环边界（< vs <=） |
| **类型/格式边界** | 非法枚举值、超长字符串截断、特殊字符（Unicode/emoji/SQL注入片段） |
| **并发/时序** | 重复提交、乐观锁冲突、超时临界点 |
| **状态转换边界** | 非法状态迁移（已关闭订单再支付）、幂等重复调用 |
| **集合边界** | 单元素集合、满容量集合、含重复元素、含 null 元素 |
| **业务规则边界** | 阈值恰好等于（如金额=免运费门槛）、跨日/跨月/跨年日期、时区切换 |

**enhanced 模式**：上表所有适用类别必须有对应测试用例。
**basic 模式**：至少覆盖空/零值、极值、Off-by-one 三类。

## 执行步骤

### 第一阶段：TDD 红绿循环（驱动实现）

0. **【上下文预加载·一次性读齐】** 本 task 开始前，一次性 Read 以下全部上下文（后续红绿循环中不再重复读取）：
    - 当前 task 的验收标准（从 `tasks.md` 提取）
    - spec.md 中与本 task 相关的功能点片段
    - design.md 中与本 task 相关的 API/分层/异常处理片段
    - 若骨架已产出：读 `scaffold-manifest.md` + 当前 task 涉及的目标文件（类/接口/方法签名/XML 映射/DDL），确认已有空壳结构与签名
    - 规则依赖文件（按上方「规则依赖」章节按需读取）
    - **只读不写**：骨架文件仅读取不修改；实现必须填充在骨架已有签名内，禁止重建已存在文件/方法、禁止偏离骨架签名（否则与骨架冲突返工）。
    - 空壳方法（TODO / `UnsupportedOperationException` / 空返回）直接进入红阶段写失败测试——空壳实现的预期失败即红阶段的正确失败，**不得**因骨架已有占位而跳过测试。
1. **确认 seam**：明确被测公开接口，写下本次循环要验证的行为清单（正常 + 异常 + 边界）。
2. **红**：写一个表达期望行为的测试（含边界场景），运行并确认它失败（失败原因正确，非编译错误）。
3. **绿**：写最小实现让测试通过，不多写、不预判下一个测试。
4. **重构**：在测试保护下清理代码（去重、命名、结构），保持全绿。重构是独立阶段，不在红绿循环内穿插。
5. 重复 2-4（垂直切片，一次一个行为），直至行为清单全部覆盖。
6. 运行对应测试命令确认全绿（Java: `mvn -q test`，前端: `npm run test:unit`，Python: `pytest -q`）。
7. 检查覆盖率：新增代码达 `coverage.new_code` 阈值，整体达 `coverage.overall` 阈值。

### 第二阶段：测试文档化（验收归档）

8. 从验收标准/实现中抽取测试点，写 `test-cases.md`（含用例 ID、类型、优先级、前置、步骤、预期）。
9. 核对已有测试代码与 test-cases.md 的覆盖完整性；补充遗漏的集成/契约层测试（按项目技术栈选择对应测试组件，见下方映射表）。
10. 编译/运行全部测试代码通过。

## 技术栈 → 测试组件映射

### Java / Spring Boot

| 组件 | 用途 |
|------|------|
| **JUnit 5** | 单元测试框架（`@Test`、`@ParameterizedTest`、`@Nested`） |
| **Mockito** | Mock 框架（`@Mock`、`@InjectMocks`、`when/verify`） |
| **AssertJ** | 流式断言库（`assertThat(x).isNotNull().isEqualTo(...)`） |
| **MockMvc** | Controller 层测试（`MockMvcBuilders.standaloneSetup`、`perform(get/post)`） |
| **SpringBootTest** | 集成测试（`@SpringBootTest` 加载完整上下文） |

### Vue / 前端

| 组件 | 用途 |
|------|------|
| **Vitest** | 单元/组件测试框架（`describe`、`it`、`expect`） |
| **Vue Test Utils** | Vue 组件挂载与交互（`mount`、`shallowMount`、`trigger`） |
| **Testing Library** | 用户视角组件测试（`render`、`screen.getByRole`） |
| **Playwright** | E2E 测试（浏览器自动化、多浏览器支持） |
| **MSW (Mock Service Worker)** | API Mock（拦截 fetch/XHR，定义 mock handler） |

### Python

| 组件 | 用途 |
|------|------|
| **pytest** | 测试框架（`def test_xxx`、fixture、parametrize） |
| **pytest-asyncio** | 异步测试支持（`@pytest.mark.asyncio`） |
| **unittest.mock** | Mock 框架（`patch`、`MagicMock`、`AsyncMock`） |
| **httpx** | API 测试客户端（FastAPI `TestClient`、异步请求） |
| **factory-boy** | 测试数据工厂（替代手写 fixture，生成模型实例） |

## 集成测试指引

本技能（ss-tdd-cycle）聚焦**单元测试**（单类/单方法级别）。集成测试在 Phase 9（ss-test-run）统一执行，不在 Phase 8 逐 task 执行。以下场景须在 `test-cases.md` 中标记为「集成测试」，由 Phase 9 统一覆盖：

- **跨服务调用**：HTTP 客户端调用外部 API / 微服务
- **数据库交互**：涉及真实 DB 的 CRUD（非 Mock）
- **消息队列**：发送/消费消息的端到端流程
- **缓存交互**：Redis/本地缓存的读写一致性
- **文件 I/O**：文件上传/下载/解析

集成测试组件见上方映射表（SpringBootTest / Testcontainers / Playwright 等）。

## 输出
- 通过的测试 + 实现代码。
- `test-cases.md`（用例 ID/类型/优先级/前置/步骤/预期）。
- 边界条件测试清单（标注覆盖了哪些类别）。

## 完成标准 (Done)
- 每段实现均有先行失败测试；最终测试全绿（附输出证据）。
- 边界条件覆盖满足当前 profile 要求（见上表）。
- 无实现耦合 / 同义反复 / 水平切片反模式。
- 新增代码覆盖率达阈值（附覆盖率报告证据）。
- `test-cases.md` 覆盖全部验收标准；正常/异常/边界齐全。

## basic vs enhanced
- basic：核心路径 + 空/零值/极值/Off-by-one 边界 TDD；新增代码覆盖率达阈值；test-cases.md 覆盖核心用例。
- enhanced：正常 + 异常 + 全部适用边界类别均先写测试；新增代码达 `coverage.new_code` 阈值，整体达 `coverage.overall` 阈值；测试命名与结构须符合上述质量标准；test-cases.md 两级评审（覆盖度→质量）+ 单元/集成/契约分层。

## 异常处理
- 无法写出失败测试 → 说明需求不清，回退 ss-analysis-spec / ss-diag-rootcause。
- 铁律：绝不为让测试变绿而删断言或加 mock 掩盖真实失败。
- 测试依赖内部实现导致重构后 break → 该测试为反模式，重写为行为级测试。
- 边界条件测试暴露未定义行为 → 暂停，回退 ss-analysis-spec 补充规格后再继续。
