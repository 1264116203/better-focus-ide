# FastAPI / Django 使用规范（Python 3.10+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 遵循项目已有封装和使用习惯

---

## 1. FastAPI 核心约定

### 1.1 应用入口

```python
# src/{project_name}/main.py
from fastapi import FastAPI
from src.core.config import settings
from src.core.exception_handlers import register_exception_handlers
from src.api.router import api_router

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
)

register_exception_handlers(app)
app.include_router(api_router, prefix="/api/v1")
```

### 1.2 路由定义

```python
# src/api/v1/auth.py
from fastapi import APIRouter, Depends
from src.schemas.auth import LoginRequest, LoginVO
from src.schemas.common import Result
from src.services.auth import AuthService
from src.api.deps import get_db

router = APIRouter()

@router.post("/login", response_model=Result[LoginVO])
async def login(request: LoginRequest, db: AsyncSession = Depends(get_db)):
    return Result.success(data=await AuthService.login(request, db))
```

**路由红线：**

| 规则 | 说明 |
|------|------|
| 返回类型统一 `Result[T]` | 禁止裸返回 dict |
| 使用依赖注入 | 禁止在路由中手写 db session 创建 |
| 参数校验用 Pydantic | 禁止在路由中手写校验逻辑 |
| 不含业务逻辑 | 路由只做参数校验 + 调用 Service |
| 路径以 `/api/v1/` 开头 | 版本化管理 |
| 一个模块一个路由文件 | 不跨模块调用无关 Service |

### 1.3 依赖注入

```python
# src/api/deps.py
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from src.core.security import get_current_user

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await verify_token(token, db)
    if not user:
        raise BusinessException(ErrorCode.USER_NOT_FOUND)
    return user
```

---

## 2. Pydantic Schema 规范

### 2.1 请求 Schema（入参校验）

```python
from pydantic import BaseModel, Field

class LoginRequest(BaseModel):
    phone: str = Field(
        ...,
        pattern=r"^1[3-9]\d{9}$",
        description="手机号",
    )
    password: str = Field(
        ...,
        min_length=6,
        max_length=20,
        description="密码",
    )
```

### 2.2 响应 Schema（返回数据）

```python
class LoginVO(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int

    # 排除敏感字段
    model_config = ConfigDict(from_attributes=True)
```

### 2.3 统一响应包装

```python
from typing import TypeVar, Generic

T = TypeVar("T")

class Result(BaseModel, Generic[T]):
    code: int = 200
    message: str = "success"
    data: T | None = None

    @classmethod
    def success(cls, data: T = None) -> "Result[T]":
        return cls(code=200, message="success", data=data)

    @classmethod
    def fail(cls, error_code: str, message: str, data: Any = None) -> "Result":
        return cls(code=int(error_code), message=message, data=data)
```

**注意：** `data` 字段必须声明为 `T | None`，错误响应时 data 可能为 None。

### 2.4 Schema 红线

| 规则 | 说明 |
|------|------|
| 请求 Schema 必须有 Field 校验 | 禁止裸 `str` 无约束 |
| 响应 Schema 排除敏感字段 | password、phone_full 禁止暴露 |
| 不在 Schema 中写业务逻辑 | Schema 仅是数据载体 |
| `from_attributes=True` | 从 ORM Model 转 Schema 时必须配置 |

---

## 3. Service 规范

### 3.1 Service 函数/类

```python
# src/services/auth.py
logger = logging.getLogger(__name__)

async def login(request: LoginRequest, db: AsyncSession) -> LoginVO:
    user = await _check_user_exists(request.phone, db)
    _check_account_not_locked(user)
    token = await _build_token(user)
    return LoginVO(access_token=token, user_id=user.id)

# 子函数拆分
async def _check_user_exists(phone: str, db: AsyncSession) -> User:
    user = await user_crud.get_by_phone(db, phone)
    if not user:
        raise BusinessException(ErrorCode.USER_NOT_FOUND)
    return user

def _check_account_not_locked(user: User) -> None:
    if user.is_locked:
        raise BusinessException(ErrorCode.ACCOUNT_LOCKED)

async def _build_token(user: User) -> str:
    return create_access_token(user.id)
```

### 3.2 Service 红线

| 规则 | 说明 |
|------|------|
| 函数 ≤ 50 行 | 超出拆分为子函数 |
| 不直接返回 Model | 必须转换为 Schema |
| 子函数用 `_` 前缀 | 标记为模块私有 |
| 异步函数用 `async def` | FastAPI 异步场景 |
| 所有 IO 必须处理异常 | 禁止空 try-except |

---

## 4. 数据库规范

### 4.1 SQLAlchemy Model

```python
# src/models/base.py
from sqlalchemy import Column, String, DateTime
from sqlalchemy.orm import DeclarativeBase
from datetime import datetime

class Base(DeclarativeBase):
    pass

class AuditMixin:
    creator = Column(String(255), nullable=False, default="system", comment="创建人")
    updater = Column(String(255), nullable=False, default="system", comment="更新人")
    created_at = Column(DateTime, nullable=False, default=datetime.now, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.now, onupdate=datetime.now, comment="更新时间")

# src/models/user.py
class User(Base, AuditMixin):
    __tablename__ = "user"
    __table_args__ = {"comment": "用户表"}

    id = Column(Integer, primary_key=True, comment="主键")
    phone = Column(String(11), nullable=False, unique=True, comment="手机号")
    password_hash = Column(String(255), nullable=False, comment="密码哈希")
    is_locked = Column(Boolean, nullable=False, default=False, comment="是否锁定")
```

### 4.2 CRUD 操作

```python
# src/crud/user.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

async def get_by_phone(db: AsyncSession, phone: str) -> User | None:
    result = await db.execute(select(User).where(User.phone == phone))
    return result.scalar_one_or_none()

async def create(db: AsyncSession, user: UserCreate) -> User:
    db_user = User(**user.model_dump())
    db.add(db_user)
    await db.commit()
    await db.refresh(db_user)
    return db_user
```

### 4.3 数据库红线

| 规则 | 说明 |
|------|------|
| 建表必须指定主键和字段注释 | 使用 `comment` 参数 |
| 字段默认非空 | `nullable=False` |
| 小数用 `Numeric`/`Decimal` | 禁止 `Float` |
| 统一审计字段 | `AuditMixin` |
| 禁止动态建表 | 使用 Alembic 迁移 |

---

## 5. Redis 规范

```python
# src/utils/redis.py
import redis.asyncio as aioredis

redis_client = aioredis.from_url(settings.REDIS_URL)

async def increment_login_fail_count(phone: str) -> int:
    key = f"login_fail:{phone}"
    # 正确：原子 INCR
    count = await redis_client.incr(key)
    if count == 1:
        await redis_client.expire(key, CAPTCHA_TTL_MINUTES * 60)
    return count

# 禁止：非原子 GET+SET
# count = await redis_client.get(key)
# await redis_client.set(key, str(int(count) + 1))  # ❌
```

**Redis 红线：**

| 规则 | 说明 |
|------|------|
| 普通 Key 必须设置 TTL | 固定大小 Value 可豁免 |
| 禁止 `KEYS *`, `HGETALL` | 全量获取命令 |
| 使用 `INCR` 而非 GET+SET | 原子操作 |
| `int()` 解析 Redis 值必须捕获 `ValueError` | 脏数据风险 |

---

## 6. 异常体系

### 6.1 ErrorCode + BusinessException

```python
# src/core/exceptions.py
from enum import Enum

class ErrorCode(Enum):
    USER_NOT_FOUND = ("40001", "用户不存在", 400)
    ACCOUNT_LOCKED = ("40002", "账户已锁定", 403)
    INVALID_CREDENTIALS = ("40003", "用户名或密码错误", 401)
    EXTERNAL_SERVICE_ERROR = ("50001", "外部服务调用失败", 500)

    def __init__(self, code: str, message: str, http_status: int):
        self.code = code
        self.message = message
        self.http_status = http_status

class BusinessException(Exception):
    def __init__(self, error_code: ErrorCode, data: Any = None):
        self.error_code = error_code
        self.data = data
        super().__init__(error_code.message)
```

### 6.2 全局异常处理器

```python
# src/core/exception_handlers.py
from fastapi import Request
from fastapi.responses import JSONResponse

async def business_exception_handler(request: Request, exc: BusinessException):
    return JSONResponse(
        status_code=exc.error_code.http_status,
        content=Result.fail(exc.error_code.code, exc.error_code.message, exc.data).model_dump(),
    )

async def validation_exception_handler(request: Request, exc: RequestValidationError):
    message = "; ".join(
        f"{err['loc'][-1]}: {err['msg']}" for err in exc.errors()
    )
    return JSONResponse(
        status_code=400,
        content=Result.fail("40000", message).model_dump(),
    )

async def unknown_exception_handler(request: Request, exc: Exception):
    logger.error("Unexpected error: %s", exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content=Result.fail("50000", "Internal server error").model_dump(),  # 不暴露堆栈
    )

def register_exception_handlers(app: FastAPI):
    app.add_exception_handler(BusinessException, business_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unknown_exception_handler)
```

---

## 7. 安全规范

| 规则 | 说明 |
|------|------|
| JWT Secret ≥ 256 位 | 32 字节随机密钥，`os.urandom(32).hex()` |
| 密码使用 bcrypt/argon2 | 禁止明文、MD5 |
| 敏感配置使用环境变量 | `settings.JWT_SECRET` 从 `.env` 读取 |
| CORS 配置 | 生产环境限制 origin |
| SQL 注入防护 | 使用 SQLAlchemy 参数化查询，禁止拼接 SQL |

---

## 8. Django REST Framework 版（如有）

### 8.1 对应约定

| FastAPI | Django DRF | 说明 |
|---------|------------|------|
| `APIRouter` | `ViewSet` / `APIView` | 路由定义 |
| `Pydantic BaseModel` | `Serializer` | 数据校验与序列化 |
| `Depends(get_db)` | ORM 默认注入 | 数据库 session |
| `Result[T]` | 自定义 Response | 统一响应包装 |
| `async def` | `def` (同步) 或 `async def` | Django 4+ 支持异步 |

### 8.2 Django 特有红线

| 规则 | 说明 |
|------|------|
| Serializer 不写业务逻辑 | 业务逻辑放 Service |
| ViewSet/APIView 不直接操作 Model | 经过 Service 层 |
| Django ORM 不用 `raw()` 拼接 SQL | 使用参数化查询 |
| `SECRET_KEY` 从环境变量读取 | 禁止硬编码 |

---

## 9. 已知陷阱（必须避免）

| # | 陷阱 | 解决方案 |
|---|------|----------|
| 1 | Pydantic v1 和 v2 API 不兼容 | 使用 v2 (`BaseModel`, `Field`, `model_dump`) |
| 2 | `int()` 解析 Redis 值无捕获 | 必须捕获 `ValueError` |
| 3 | Redis GET+SET 非原子 | 使用 `INCR` 原子命令 |
| 4 | `Optional[X]` 过时 | 使用 `X | None`（3.10+） |
| 5 | `Union[X, Y]` 过时 | 使用 `X | Y`（3.10+） |
| 6 | `.env` 文件提交到 git | `.gitignore` 必须排除 `.env` |
| 7 | 密码明文存储 | 使用 bcrypt/argon2 |
| 8 | 硬编码 localhost 数据库 | 使用 `settings.DATABASE_URL` 环境变量 |

---

## 最终回复要求

* 说明使用了哪些框架特性
* 说明是否符合 API/Service/Schema 规范
* 说明是否对照已知陷阱做了检查
* 说明风险点或后续建议