# Python 代码风格规范（3.10+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 修改时优先采用最小可行改动

---

## 1. Python 3.10+ 特性使用

### 1.1 必须使用的新特性

| 特性 | 说明 | 示例 |
|------|------|------|
| 类型注解 | 所有公开函数必须有类型注解 | `def login(phone: str, password: str) -> LoginVO` |
| match-case | 结构化模式匹配（替代复杂 if-elif） | `match status: case "active": ...` |
| Union 语法 `X \| Y` | 替代 `Union[X, Y]`（3.10+） | `def get(id: int) -> User \| None` |
| Pydantic v2 | 数据校验与序列化（替代手写校验） | `class LoginRequest(BaseModel): ...` |
| dataclass | 不可变数据结构 | `@dataclass(frozen=True) class Config: ...` |
| f-string | 字符串格式化（替代 % 和 .format） | `f"User {user.name} logged in"` |
| `async/await` | 异步 IO（FastAPI 场景） | `async def get_user(user_id: int) -> UserVO` |

### 1.2 禁止使用的旧模式

| 禁止模式 | 替换方案 | 原因 |
|----------|----------|------|
| `%s` / `.format()` 字符串格式化 | f-string | 可读性更好 |
| `Union[X, Y]` | `X | Y` 语法 | 3.10+ 更简洁 |
| `Optional[X]` | `X | None` | 3.10+ 更简洁 |
| `dict` 作为 API 入参/返回值 | Pydantic Model | 类型安全 + 自动校验 |
| 手写参数校验逻辑 | Pydantic `BaseModel` + `Field` | 声明式校验更可靠 |
| `import *` | 明确导入 | 避免命名空间污染 |
| 裸 `except:` | `except Exception as e:` | 必须捕获具体异常 |
| `print()` 输出日志 | `logger.info/error` | 必须使用标准日志框架 |

---

## 2. 命名规范

### 2.1 统一规则

| 类型 | 风格 | 示例 |
|------|------|------|
| 类名 | PascalCase | `UserService`, `AuthController` |
| 函数/方法名 | snake_case | `find_by_phone`, `check_account_not_locked` |
| 变量名 | snake_case | `login_fail_count`, `user_token` |
| 常量名 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT`, `CAPTCHA_TTL_MINUTES` |
| 模块/文件名 | snake_case | `user_service.py`, `auth_routes.py` |
| Pydantic Model | PascalCase | `LoginRequest`, `UserVO` |
| 枚举值 | UPPER_SNAKE_CASE | `ErrorCode.USER_NOT_FOUND` |

**禁止混用 snake_case 与 PascalCase 命名。** 命名需见名知意。

### 2.2 函数命名语义约定

| 操作 | 前缀 | 示例 |
|------|------|------|
| 查询 | `get` / `find` / `query` | `get_user_by_id`, `find_by_phone` |
| 列表 | `list` / `query` | `list_users`, `query_orders` |
| 数量 | `count` | `count_by_status` |
| 新增 | `create` / `add` | `create_user`, `add_order` |
| 修改 | `update` / `modify` | `update_user_status` |
| 删除 | `delete` / `remove` | `delete_by_id` |
| 判断 | `check` / `is` / `has` | `check_account_not_locked`, `is_active` |
| 构建 | `build` / `convert` | `build_token_vo`, `convert_to_schema` |

---

## 3. 代码结构

### 3.1 函数长度限制

| 类型 | 上限 | 超出处理 |
|------|------|----------|
| Service 函数 | 50 行 | 拆分为子函数 |
| API 路由函数 | 20 行 | 拆分校验逻辑到 Service |
| 通用函数 | 80 行 | 拆分为子函数 |

### 3.2 import 顺序（PEP 8 / isort）

```python
# 1. 标准库
import os
import logging
from typing import Optional

# 2. 第三方库
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import Column, String

# 3. 项目内部
from src.core.config import settings
from src.core.exceptions import BusinessException
from src.services.user import UserService
```

### 3.3 模块内部排列顺序

```python
"""模块文档字符串"""

# 1. 标准库 import
# 2. 第三方 import
# 3. 项目内部 import

# 4. 常量
MAX_LOGIN_RETRY = 3

# 5. 公开类/函数
class UserService:
    ...

# 6. 私有函数
def _check_account_not_locked(user: User) -> None:
    ...
```

---

## 4. 常量管理

### 4.1 分类存放

| 常量类型 | 存放位置 | 示例 |
|----------|----------|------|
| 模块私有常量 | 当前模块内部 | `MAX_RETRY_COUNT = 3` |
| 跨模块公共常量 | `constants/` 模块 | `from src.constants.auth import CAPTCHA_TTL_MINUTES` |
| 业务错误码 | 枚举类 | `ErrorCode.USER_NOT_FOUND` |
| 配置参数 | `core/config.py` (BaseSettings) | `settings.JWT_SECRET` |

**禁止魔术字符**：代码中禁止临时直接使用的硬编码数字/字符串。

---

## 5. 异常处理

### 5.1 统一异常体系

```python
# 业务异常 — 抛出，由全局异常处理器处理
raise BusinessException(ErrorCode.USER_NOT_FOUND)

# 需携带额外数据的异常
raise BusinessException(ErrorCode.ACCOUNT_LOCKED, data={"remaining_minutes": 5})

# IO/外部调用异常 — 记录日志，不吞掉
try:
    external_service.call()
except ExternalServiceError as e:
    logger.error("External service call failed: %s", e, exc_info=True)
    raise BusinessException(ErrorCode.EXTERNAL_SERVICE_ERROR) from e
```

### 5.2 禁止行为

| 禁止 | 原因 |
|------|------|
| `except:` 裸捕获 | 捕获所有异常包括 SystemExit |
| `except Exception: pass` | 吞掉异常，隐藏问题 |
| `except Exception as e: logger.error(str(e))` | 丢失堆栈信息，必须用 `exc_info=True` |
| 裸 `raise` 在非 except 块中 | 语义不明 |

**正确方式：** `logger.error("Operation failed: %s", e, exc_info=True)` — 保留完整堆栈。

---

## 6. 数值处理

| 规则 | 说明 |
|------|------|
| 禁止 `float` 比大小 | 精度丢失风险，使用 `Decimal` |
| `Decimal` 比较 | 使用 `==` 或 `<`/`>`（Python Decimal 比较可靠） |
| `int()` 解析外部值 | 必须捕获 `ValueError` |
| Redis 数值操作 | 使用 `INCR` 原子命令，而非 GET+SET |

---

## 7. 类型注解

### 7.1 必须注解的函数

```python
# 所有公开函数必须有类型注解
def login(phone: str, password: str) -> LoginVO:
    ...

# 返回值可能为 None 时，必须标注
def get_user_by_id(user_id: int) -> User | None:
    ...

# Pydantic Model 自动注解
class LoginRequest(BaseModel):
    phone: str = Field(..., pattern=r"^1[3-9]\d{9}$", description="手机号")
    password: str = Field(..., min_length=6, max_length=20, description="密码")
```

### 7.2 禁止

| 禁止 | 说明 |
|------|------|
| `dict` 作为 API 入参/返回值类型 | 使用 Pydantic Model |
| `Any` 作为返回值类型 | 必须标注具体类型或 `X | None` |
| `Optional[X]` | 使用 `X | None`（3.10+） |

---

## 8. 日志规范

| 规则 | 说明 |
|------|------|
| 日志框架 | `logging` 标准库，禁止 `print()` |
| 必须包含关键字段 | `logger.info("User login: user_id=%s", user_id)` |
| 减少无用日志 | 不记录函数开始/结束 |
| 异常日志 | `logger.error("XXX failed: %s", e, exc_info=True)` — 必须带堆栈 |
| 敏感信息 | 日志中禁止打印密码、token、完整手机号 |

---

## 9. 禁止事项汇总

| 禁止 | 替换 |
|------|------|
| 魔术字符/数字 | 常量或枚举 |
| `float` 比大小 | `Decimal` |
| 空 except 块 | 记录日志 + 处理/抛出 |
| `dict` 作为方法入参/返回值 | Pydantic Model |
| `print()` | `logger.info/error` |
| `import *` | 明确导入 |
| 裸 `except:` | `except Exception as e:` |
| `%s` / `.format()` | f-string |
| `Optional[X]` | `X | None` |
| 动态建表 | Alembic 迁移 |

---

## 最终回复要求

* 说明修改了哪些文件
* 说明核心改动点
* 说明是否执行了校验（`ruff check` / `pytest`）
* 说明风险点或后续建议