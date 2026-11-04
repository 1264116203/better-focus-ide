# Python 项目结构规范（3.10+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 新功能必须按目录结构放置，不散落

---

## 1. 根目录职责

| 目录/文件 | 职责 | 禁止 |
|-----------|------|------|
| `.qoder/rules/` | AI 开发约束与规则 | 存放业务代码 |
| `src/{project_name}/` | Python 源代码 | 存放非 Python 文件 |
| `tests/` | 测试代码 | 存放非测试代码 |
| `alembic/` | 数据库迁移脚本 | 手动修改表结构 |
| `pyproject.toml` | 项目配置（依赖、工具） | 硬编码敏感信息 |
| `.env` | 环境变量（不提交 git） | 硬编码在代码中 |
| `.gitignore` | 排除 `__pycache__/`, `.venv/`, `*.pyc`, `.env` | 排除 src/ |
| `README.md` | 项目说明 | 存放业务逻辑 |

---

## 2. 源码目录结构

```text
src/{project_name}/
├── api/                                # API 层（路由 + 依赖注入）
│   ├── v1/                             # API 版本化
│   │   ├── __init__.py                 # 路由注册汇总
│   │   ├── auth.py                     # 认证相关路由
│   │   └── user.py                     # 用户相关路由
│   ├── deps.py                         # 依赖注入（get_db, get_current_user 等）
│   └── router.py                       # 主路由注册
│
├── schemas/                            # Pydantic 数据模型
│   ├── __init__.py
│   ├── auth.py                         # 认证请求/响应 Schema
│   ├── user.py                         # 用户请求/响应 Schema
│   └── common.py                       # 公共 Schema（Result, PageRequest 等）
│
├── services/                           # 业务逻辑层
│   ├── __init__.py
│   ├── auth.py                         # 认证业务逻辑
│   └── user.py                         # 用户业务逻辑
│
├── models/                             # 数据库模型（仅数据结构）
│   ├── __init__.py
│   ├── user.py                         # 用户表模型
│   └── base.py                         # 基础模型（审计字段等）
│
├── crud/                               # 数据库 CRUD 操作
│   ├── __init__.py
│   ├── user.py                         # 用户 CRUD
│   └── base.py                         # 基础 CRUD 类（可选）
│
├── core/                               # 核心配置与基础设施
│   ├── __init__.py
│   ├── config.py                       # 项目配置（Pydantic BaseSettings）
│   ├── security.py                     # JWT/密码处理
│   ├── exceptions.py                   # 异常体系（BusinessException, ErrorCode）
│   ├── exception_handlers.py           # 全局异常处理器
│   └── logging.py                      # 日志配置
│
├── utils/                              # 工具函数
│   ├── __init__.py
│   ├── redis.py                        # Redis 工具
│   └── date.py                         # 日期工具
│
├── constants/                          # 常量定义
│   ├── __init__.py
│   ├── auth.py                         # 认证相关常量
│   └── biz.py                          # 业务常量
│
└── main.py                             # 应用入口（FastAPI app 创建）
```

---

## 3. 测试目录结构

```text
tests/
├── conftest.py                         # 测试配置与 fixtures（db session, client 等）
├── api/                                # API 测试
│   ├── v1/
│   │   ├── test_auth.py
│   │   └── test_user.py
├── services/                           # Service 测试
│   ├── test_auth.py
│   ├── test_user.py
├── crud/                               # CRUD 测试
│   ├── test_user.py
└── integration/                        # 集成测试（如有）
    └── test_auth_flow.py
```

---

## 4. 模块职责红线

| 包 | 允许存放 | 禁止存放 |
|----|---------|---------|
| `models/` | 数据库模型类 | Service 逻辑、API 路由 |
| `schemas/` | Pydantic Model（请求/响应） | 业务逻辑函数 |
| `api/` | 路由函数 + 依赖注入 | Service 实现、直接数据库操作 |
| `services/` | 业务逻辑函数/类 | API 路由定义 |
| `crud/` | 数据库 CRUD 操作 | 业务逻辑判断 |
| `core/` | 配置、异常、安全、日志 | 业务代码 |
| `utils/` | 纯工具函数（无状态） | 配置常量、业务逻辑 |
| `constants/` | 常量定义 | 函数方法 |

---

## 5. 新功能放置规则

### 5.1 新增模块

按完整分层添加：
```
api/v1/{module}.py          # 路由
schemas/{module}.py         # 请求/响应 Schema
services/{module}.py        # 业务逻辑
models/{module}.py          # 数据库模型（如需新表）
crud/{module}.py            # CRUD 操作（如需新表）
constants/{module}.py       # 常量（如有）
```

### 5.2 新增接口（已有模块）

在现有路由/Service 中添加函数，不新建文件：
```python
# api/v1/user.py 新增路由
@router.get("/profile", response_model=Result[UserProfileVO])
async def get_profile(user_id: int, db: AsyncSession = Depends(get_db)): ...

# services/user.py 新增函数
async def get_profile(user_id: int, db: AsyncSession) -> UserProfileVO: ...
```

### 5.3 新增公共能力

项目内复用 ≥ 3 次的逻辑，提取到 `utils/` 或独立 Service：
```
utils/ → 纯工具函数（无状态，无 DB 依赖）
services/ → 跨模块共享业务逻辑
```

---

## 6. 文件/类命名约定

| 类型 | 命名模式 | 示例 |
|------|---------|------|
| 路由文件 | `{module}.py` | `auth.py`, `user.py` |
| Schema 文件 | `{module}.py` | `auth.py` (含 LoginRequest, LoginVO) |
| Service 文件 | `{module}.py` | `auth.py` (含 auth_service 函数/类) |
| Model 文件 | `{module}.py` | `user.py` (含 User Model) |
| CRUD 文件 | `{module}.py` | `user.py` (含 user CRUD 函数) |
| 常量文件 | `{module}.py` | `auth.py` (含 CAPTCHA_TTL_MINUTES) |
| Schema 类 | PascalCase | `LoginRequest`, `UserVO` |
| Model 类 | PascalCase | `User`, `Base` |
| 枚举类 | PascalCase | `ErrorCode` |
| 配置类 | PascalCase | `Settings` |

---

## 7. 文件创建/修改要求

| 操作 | 要求 |
|------|------|
| 新建模块 | 必须放在正确的包中，包含 `__init__.py` |
| 新建 Schema | 必须有 Pydantic `Field` 校验注解 |
| 新建 Model | 必须有表注释、字段注释、审计字段 |
| 新建路由 | 必须在 `api/v1/__init__.py` 中注册 |
| 修改文件 | 不修改与本次任务无关的函数 |
| 删除文件 | 必须确认无 import 引用后再删 |

---

## 8. 禁止事项

| 禁止 | 原因 |
|------|------|
| `dict` 作为 API 入参/返回值 | 使用 Pydantic Model |
| Schema 中写业务逻辑 | Schema 仅是数据载体 |
| Model 中写 Service 逻辑 | Model 仅是数据结构 |
| API 路由中直接操作数据库 | 必须经过 Service → CRUD |
| Service 直接返回 Model | 必须转换为 Schema |
| 散落的工具函数（多文件重复实现） | 提取到 utils/ |
| 动态建表/修改表结构 | 使用 Alembic 迁移 |
| 模块文件名驼峰命名 | 必须用 snake_case |

---

## 自检清单

- [ ] 新文件是否放在了正确的包中？
- [ ] 新文件命名是否符合 snake_case 约定？
- [ ] 新 Schema 是否包含 Pydantic Field 校验？
- [ ] 新 Model 是否包含审计字段？
- [ ] 是否遵循了分层依赖方向（API → Service → CRUD → Model）？
- [ ] 是否没有跨层调用（API → Model 直接查询）？
- [ ] 修改是否仅限于本次任务相关的函数？

---

## 最终回复要求

* 说明新增/修改了哪些文件及其所在包
* 说明文件放置是否符合目录结构规范
* 说明是否存在需要后续处理的架构问题