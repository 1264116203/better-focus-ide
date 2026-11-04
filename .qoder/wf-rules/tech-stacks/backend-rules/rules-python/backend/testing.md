# Python 校验与测试规范（3.10+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 修改文件后优先做语法检查
> * 校验遵循最小必要原则，非必要不跑全量测试

---

## 1. 校验优先级

| 变更规模 | 必须校验 | 推荐校验 | 可选校验 |
|----------|---------|---------|---------|
| 小改动（≤3 文件，≤20 行） | `ruff check` 或 `python -m py_compile` | 相关单测 | 全量 pytest |
| 中改动（3-10 文件） | `ruff check` + 相关单测 | `pytest tests/services/test_{module}.py` | 全量 pytest |
| 大改动（>10 文件） | `ruff check` + `pytest` | 全量 pytest | 集成测试 |

---

## 2. 基础校验原则

### 2.1 语法检查

```bash
python -m py_compile src/{project}/services/auth.py  # 单文件编译检查
ruff check src/                                       # Lint 检查（如有 ruff）
ruff check --fix src/                                 # Lint 自动修复
```

**编译失败分类：**

| 类型 | 处理方式 |
|------|---------|
| 代码问题（语法、类型） | 修复代码 |
| 环境问题（Python 版本） | 提示开发者 |
| 工具缺失（ruff 未安装） | 提示开发者 |
| 历史遗留（其他文件报错） | 仅关注本次改动涉及的文件 |

### 2.2 单元测试

```bash
pytest tests/services/test_auth.py                    # 运行单个测试文件
pytest tests/services/test_auth.py::test_login        # 运行单个测试函数
pytest tests/                                         # 运行所有测试
pytest tests/ -k "auth"                               # 运行包含 auth 的测试
pytest tests/ --cov=src                               # 运行测试并生成覆盖率
```

---

## 3. 校验内容清单

### 3.1 Python 特定校验

| 校验项 | 检查方式 |
|--------|---------|
| 语法正确 | `python -m py_compile` 或 `ruff check` |
| 类型注解完整 | 检查公开函数是否有类型注解 |
| Pydantic 校验注解 | 检查 Schema 是否有 `Field` 校验 |
| None 安全 | 检查是否有 `| None` 返回值未处理 |
| 异常处理 | 检查 except 块是否记录完整异常 |
| 常量使用 | 检查是否有硬编码数字/字符串 |
| import 规范 | 检查是否有 `import *` |

### 3.2 FastAPI 特定校验

| 校验项 | 检查方式 |
|--------|---------|
| Result[T] 返回类型 | 检查路由是否使用 `response_model=Result[T]` |
| 依赖注入 | 检查是否使用 `Depends` 而非手动创建 session |
| Schema 排除敏感字段 | 检查响应 Schema 是否暴露 password |
| 路由注册 | 检查新路由是否在 `__init__.py` 中注册 |
| 函数长度 | 检查 Service 是否 ≤ 50 行 |

### 3.3 数据库校验

| 校验项 | 检查方式 |
|--------|---------|
| Model 字段注释 | 检查每个字段是否有 `comment` 参数 |
| 审计字段 | 检查是否有 AuditMixin |
| Decimal 使用 | 检查金额/数值是否用 Decimal |
| 禁止动态建表 | 检查是否有 `CREATE TABLE` SQL |

---

## 4. 测试编写规范

### 4.1 测试文件命名

| 测试类型 | 命名 | 示例 |
|----------|------|------|
| API 测试 | `test_{module}.py` | `test_auth.py` |
| Service 测试 | `test_{module}.py` | `test_auth.py` |
| CRUD 测试 | `test_{module}.py` | `test_user.py` |
| 集成测试 | `test_{module}_flow.py` | `test_auth_flow.py` |

### 4.2 测试函数命名

```python
# 格式：test_function_scenario_expected_result
async def test_login_valid_credentials_returns_login_vo():
    ...

async def test_login_locked_account_raises_business_exception():
    ...

async def test_get_user_nonexistent_id_raises_business_exception():
    ...
```

### 4.3 测试覆盖要求

> 下表为测试设计建议值；实际质量门禁阈值以 `.qoder/wf-dev.yaml` 的 `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`），由 ss-test-run 读取校验。

| 类型 | 最低覆盖率 | 说明 |
|------|-----------|------|
| Service 核心函数 | 80% | 登录、权限校验等关键逻辑 |
| API 路由 | 60% | 主要是参数校验和路由 |
| CRUD | 50% | 简单 CRUD 可适当降低 |
| 工具函数 | 90% | 纯逻辑，易于测试 |

### 4.4 测试 fixtures

```python
# tests/conftest.py
@pytest.fixture
async def db_session():
    async with async_session_factory() as session:
        yield session

@pytest.fixture
async def client():
    from src.main import app
    from httpx import AsyncClient
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac
```

### 4.5 Mock 使用约定

```python
from unittest.mock import AsyncMock, patch

# 推荐：Mock 外部依赖
async def test_login_external_service_failure():
    with patch("src.services.auth.external_service.call", new_callable=AsyncMock) as mock_call:
        mock_call.side_effect = ExternalServiceError("timeout")
        with pytest.raises(BusinessException) as exc_info:
            await AuthService.login(request, db)
        assert exc_info.value.error_code == ErrorCode.EXTERNAL_SERVICE_ERROR
```

**Mock 红线：**

| 规则 | 说明 |
|------|------|
| 不 Mock 被测函数本身 | Mock 依赖，不 Mock 自身 |
| 不 Mock 数据库基础操作 | 数据库测试用真实 DB 或 fixture |
| AsyncMock 用于异步函数 | FastAPI 异步场景必须用 AsyncMock |

---

## 5. 校验范围控制

| 规则 | 说明 |
|------|------|
| 仅校验与本次改动相关的文件 | 不跑无关文件的测试 |
| 优先最小范围校验 | `ruff check` > 单测 > 全量 pytest |
| 校验失败先分类 | 区分代码问题 vs 环境问题 vs 历史遗留 |
| 非必要不跑全量 pytest | 仅在 ss-test-run 质量门禁时跑全量 |

---

## 6. 推荐校验策略

| 改动类型 | 推荐校验流程 |
|----------|-------------|
| Service 函数修改 | `ruff check` → `pytest tests/services/test_{module}.py` |
| API 路由修改 | `ruff check` → `pytest tests/api/test_{module}.py` |
| Schema 修改 | `ruff check` → 检查相关 Service 单测 |
| Model 修改 | `ruff check` → `pytest tests/crud/test_{module}.py` |
| Config 修改 | `ruff check` → `pytest tests/`（影响面大） |

---

## 7. 禁止事项

| 禁止 | 原因 |
|------|------|
| 跳过语法检查直接提交 | 语法是第一道防线 |
| 空 except 块测试 | 测试必须验证异常场景 |
| Mock 被测函数自身 | 失去测试意义 |
| 仅测成功路径 | 必须覆盖异常和边界场景 |
| 全量 pytest 作为日常校验 | 耗时长，日常仅校验相关模块 |

---

## 最终回复要求

* 说明执行了哪些校验命令
* 说明校验结果（通过/失败）
* 说明失败原因及处理方式
* 如未执行校验，说明原因