# {{module_name}} — REST API 文档

<!-- 指令: 本模板为 AI 结构约束，生成 API 文档时必须遵循以下结构 -->
<!-- 指令: 产出物路径 → openapis/consumer/（第三方提供）或 openapis/provider/（本系统提供） -->
<!-- 指令: 文件命名使用 kebab-case，如 restapi-user-service.md -->

> **一句话描述**：{{brief_description}}

---

## 基本信息

| 属性 | 说明 |
|------|------|
| **模块** | {{module_name}} |
| **负责人** | {{owner}} |
| **版本** | `v1.0` |
| **协议** | RESTful (HTTP/HTTPS) |
| **数据格式** | `application/json` |
| **认证方式** | {{auth_type}}（JWT / OAuth2 / API Key） |
| **限流策略** | {{rate_limit}} |

---

## 接口地址

| 环境 | Base URL |
|------|----------|
| **DEV** | `{{dev_base_url}}` |
| **TEST** | `{{test_base_url}}` |
| **PROD** | `{{prod_base_url}}` |

---

## 通用约定

> 以下约定适用于本文档中**所有接口**，各接口详情中不再重复说明。

### 通用请求头（Common Headers）

| Header | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `Authorization` | `string` | 是 | Bearer Token，格式：`Bearer <token>` |
| `Content-Type` | `string` | 是 | 固定值：`application/json` |
| `Accept` | `string` | 是 | 固定值：`application/json` |
| `X-Request-Id` | `string` | 否 | 请求追踪 ID（UUID v4），建议传入以便链路追踪 |
| `Accept-Language` | `string` | 否 | 期望语言，如 `zh-CN`、`en-US`，默认 `zh-CN` |

### 通用分页参数（Pagination Query）

| 参数名 | 类型 | 必填 | 默认值 | 校验规则 | 说明 |
|--------|------|------|--------|----------|------|
| `page` | `integer` | 否 | `1` | ≥ 1 | 页码，从 1 开始 |
| `pageSize` | `integer` | 否 | `20` | 1 ~ 100 | 每页条数 |
| `sort` | `string` | 否 | `create_time` | 限白名单字段 | 排序字段 |
| `order` | `string` | 否 | `desc` | `asc` / `desc` | 排序方向 |

### 通用分页响应结构（Pagination Response）

```json
{
  "success": true,
  "code": 0,
  "message": "success",
  "data": {
    "items": [],
    "pagination": {
      "page": 1,
      "pageSize": 20,
      "totalItems": 128,
      "totalPages": 7
    }
  }
}
```

### 复杂 JSON 入参、返回体字段说明规范

<!-- 指令: 当 JSON Body 包含嵌套对象或数组时，须使用点号路径逐层展开说明每个字段 -->
<!-- 指令: 对象用 `.` 分隔（如 buyer.name），数组元素用 `[]` 标记（如 items[].skuId） -->

| 字段路径 | 类型 | 必填 | 最大长度 | 校验规则 | 业务含义 |
|----------|------|------|----------|----------|----------|
| `{{field}}` | `{{type}}` | 是 | {{max_len}} | {{validation}} | {{desc}} |
| `{{parent}}.{{child}}` | `{{type}}` | 是 | {{max_len}} | {{validation}} | {{desc}} |
| `{{array}}[].{{field}}` | `{{type}}` | 是 | {{max_len}} | {{validation}} | {{desc}} |

---

## 接口列表

| # | 方法 | 路径 | 说明 |
|---|------|------|------|
| 1 | `{{METHOD}}` | `{{path}}` | {{desc}} |

---

## 接口详情

<!-- 指令: 每个接口按以下结构填写，重复此块添加更多接口 -->

### 1. {{api_name}}

> {{api_description}}

#### 请求

```
{{HTTP_METHOD}} {{api_path}}
```

**Headers**

> 参见 [通用请求头](#通用请求头common-headers){{extra_headers_note}}

**Path Parameters**

| 参数名 | 类型 | 必填 | 最大长度 | 说明 |
|--------|------|------|----------|------|
| `{{path_param}}` | `{{type}}` | 是 | {{max_len}} | {{desc}} |

**Query Parameters**

| 参数名 | 类型 | 必填 | 最大长度 | 说明 |
|--------|------|------|----------|------|
| `{{query_param}}` | `{{type}}` | 否 | {{max_len}} | {{desc}} |

**Request Body**

```json
{{request_body_example}}
```

| 字段路径 | 类型 | 必填 | 最大长度 | 校验规则 | 业务含义 |
|----------|------|------|----------|----------|----------|
| `{{field}}` | `{{type}}` | 是 | {{max_len}} | {{validation}} | {{desc}} |

**请求示例**

```bash
curl -X {{METHOD}} {{base_url}}{{path}} \
  -H "Authorization: Bearer {{token}}" \
  -H "Content-Type: application/json" \
  -d '{{request_json}}'
```

#### 响应 `200`

**成功响应体**

```json
{
  "success": true,
  "code": 0,
  "message": "success",
  "data": {{response_data_example}}
}
```

**`data` 字段说明**

| 字段路径 | 类型 | 必返回 | 最大长度 | 业务含义 |
|----------|------|--------|----------|----------|
| `{{field}}` | `{{type}}` | 是 | {{max_len}} | {{desc}} |

**错误响应**

```json
{
  "success": false,
  "code": {{biz_error_code}},
  "message": "{{error_message}}",
  "data": null
}
```

---

## 统一响应结构

<!-- 指令: 所有接口遵循以下统一响应格式，不可修改 -->

```json
{
  "success": true,
  "code": 0,
  "message": "success",
  "data": {}
}
```

| 字段 | 类型 | 必返回 | 说明 |
|------|------|--------|------|
| `success` | `boolean` | 是 | 业务是否成功 |
| `code` | `integer` | 是 | 业务状态码，`0` 表示成功，非 0 表示业务错误 |
| `message` | `string` | 是 | 状态描述信息 |
| `data` | `T` | 是 | 业务数据（泛型），错误时为 `null` |

> `success` 与 `code` 应保持语义一致——`code == 0` 时 `success` 为 `true`，`code != 0` 时 `success` 为 `false`。

---

## HTTP 状态码说明

| 状态码 | 含义 | 说明 |
|--------|------|------|
| `200` | OK | 请求成功 |
| `400` | Bad Request | 请求参数校验失败 |
| `401` | Unauthorized | 未认证或 Token 已过期 |
| `403` | Forbidden | 已认证但无权限执行该操作 |
| `404` | Not Found | 请求的资源不存在 |
| `429` | Too Many Requests | 请求频率超限 |
| `500` | Internal Server Error | 服务内部错误 |

---

## 业务错误码

<!-- 指令: 业务错误 HTTP 状态码统一返回 200，通过 code 字段区分 -->

| 错误码 | 说明 | HTTP 状态码 | 建议处理方式 |
|--------|------|-------------|-------------|
| `0` | 成功 | 200 | — |
| `{{biz_code_1}}` | {{biz_error_1}} | 200 | {{biz_fix_1}} |
| `{{biz_code_2}}` | {{biz_error_2}} | 200 | {{biz_fix_2}} |

---

## 安全要求

| 要求 | 说明 |
|------|------|
| **传输加密** | 所有接口必须使用 HTTPS（TLS 1.2+） |
| **认证方式** | {{auth_detail}} |
| **权限模型** | {{permission_model}}（RBAC / ABAC） |
| **限流** | {{rate_limit_detail}} |
| **敏感数据** | 密码、手机号等敏感字段在响应中脱敏处理 |
| **幂等性** | {{idempotency_requirement}} |

---

## 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| `v1.0` | {{date}} | 初始版本 | {{author}} |
