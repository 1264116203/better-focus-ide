---
trigger: glob
glob: **/*.py
---
# Python 编码规范（栈扩展）

适用 Python 3.11+、FastAPI / Django 5.x、Pydantic v2。继承 `coding-standards.md`。

## 模块与结构

- 项目结构遵循 `src/<package>/` 布局（PEP 621）；模块名 snake_case。
- 每个模块职责单一；单文件 ≤500 行（超出拆子模块）。
- 公开 API 在 `__init__.py` 显式导出（`__all__`）；内部实现以下划线前缀（`_internal.py`）。
- 类型注解强制（PEP 484）：函数签名必须有参数类型与返回类型。

## 函数与类

- 函数体 ≤50 行；参数 ≤5 个（超出用 dataclass/Pydantic model 封装）。
- 优先用 `dataclass` 或 `TypedDict` 承载结构化数据；禁裸 dict 传递业务对象。
- 类方法 ≤10 个（超出拆 mixin 或子模块）；组合优于继承。
- 异步函数仅在 IO 密集场景使用（`async def`）；CPU 密集用 `multiprocessing`。

## 异常与日志

- 自定义异常继承 `AppBaseException`；禁止裸 `except Exception`（除非最外层兜底）。
- 日志用 `structlog` 或 `logging`；关键路径 INFO，异常 ERROR（带 `exc_info=True`）。
- 禁止 `print()` 输出业务日志；禁止 `logging.warning(f"...")` 用 `%s` 占位符。

## 数据与校验

- API 入参用 Pydantic model 校验（`BaseModel`）；禁止手动 `if not x: raise`。
- 数据库操作用 SQLAlchemy 2.x（async session）或 Django ORM；禁止拼接 SQL。
- 时间统一用 `datetime.datetime.now(datetime.UTC)`（禁 `datetime.now()` 无时区）。

## 测试

- 单元测试 pytest + pytest-asyncio；Mock 用 `unittest.mock.patch`。
- API 测试用 httpx（FastAPI `TestClient`）或 Django `TestCase`。
- 性能测试用 pytest-benchmark；Fixture 用 factory-boy 或 pytest-factoryboy。
- 覆盖率阈值：新增代码 100%（强制）；整体代码 enhanced ≥70%，basic ≥关键路径覆盖。
- 命名 `test_<function>_<scenario>`（如 `test_create_user_duplicate_email`）。

## 构建命令策略

- 依赖管理：`uv sync`（推荐）或 `poetry lock && poetry install`；禁 `pip install` 直装。
- 类型检查：`mypy --strict`；Lint：`ruff check .`；格式化：`ruff format .`。
- 测试：`pytest -q`（单元）；`pytest --cov=src --cov-report=term-missing`（覆盖率）。
- 禁 `python setup.py`（已废弃）；禁 `pip install -r requirements.txt`（用 lock 文件）。
