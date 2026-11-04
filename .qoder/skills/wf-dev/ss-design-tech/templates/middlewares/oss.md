# 阿里云 OSS 存储设计 — {{feature_name}}

<!-- 指令: 本模板为 AI 结构约束，涉及阿里云 OSS 文件存储设计时按此结构填充 -->

## 1. 概述

| 项目 | 说明 |
|------|------|
| 使用场景 | {{usage_scenario}} |
| 选型理由 | {{selection_reason}} |
| OSS Region | {{region}} |
| 存储类型 | {{storage_class}}（标准/低频/归档/冷归档） |

## 2. 架构设计

<!-- 指令: 使用 PlantUML 组件图描述存储架构，输出到 diagrams/ 目录 -->

```text
Client → STS/签名URL → OSS Bucket → CDN（可选）
Service → OSS SDK → OSS Bucket
```

## 3. Bucket 规划

<!-- 指令: 必须定义 Bucket 规划 -->

| Bucket 名称 | 用途 | 存储类型 | 读写权限 | Region |
|-------------|------|----------|----------|--------|
| {{bucket_1}} | {{purpose_1}} | {{class_1}} | {{acl_1}}（私有/公共读） | {{region}} |
| {{bucket_2}} | {{purpose_2}} | {{class_2}} | {{acl_2}} | {{region}} |

**命名规范**: `{{company}}-{{env}}-{{biz}}-{{module}}`（如 `lingyue-prod-order-attachment`）

## 4. 目录结构

<!-- 指令: 必须定义 Object Key 的目录结构规范 -->

```text
{{bucket_name}}/
├── {{module_1}}/
│   ├── {{yyyy}}/{{MM}}/{{dd}}/
│   │   ├── {{uuid}}.{{ext}}
│   │   └── {{uuid}}_thumbnail.{{ext}}
│   └── temp/                    ← 临时文件（生命周期自动清理）
├── {{module_2}}/
│   └── ...
└── public/                      ← 公共可访问资源
    └── ...
```

**Object Key 规则**:
- 格式：`{{module}}/{{yyyy}}/{{MM}}/{{dd}}/{{uuid}}.{{ext}}`
- 禁止使用中文/特殊字符
- 按日期分目录，避免单目录文件过多
- 文件名使用 UUID，防止冲突和猜测

## 5. 访问控制

<!-- 指令: 必须说明访问控制方案 -->

### 5.1 访问方式

| 场景 | 方式 | 有效期 | 说明 |
|------|------|--------|------|
| 前端上传 | {{upload_method}}（STS 临时凭证 / 签名 URL / 服务端代理） | {{upload_ttl}} | {{desc}} |
| 前端下载/预览 | {{download_method}}（签名 URL / CDN） | {{download_ttl}} | {{desc}} |
| 服务端访问 | {{server_method}}（SDK + AK/SK） | 永久 | {{desc}} |

### 5.2 STS 策略

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["oss:PutObject", "oss:GetObject"],
      "Resource": ["acs:oss:*:*:{{bucket}}/{{prefix}}/*"]
    }
  ]
}
```

### 5.3 防盗链

- Referer 白名单：{{referer_whitelist}}
- 是否允许空 Referer：{{allow_empty_referer}}

## 6. 生命周期规则

<!-- 指令: 必须定义文件生命周期 -->

| 前缀/标签 | 规则 | 转换/过期 | 说明 |
|-----------|------|-----------|------|
| `*/temp/*` | 过期删除 | {{temp_expire_days}} 天后删除 | 临时文件 |
| `{{module}}/*` | 存储降冷 | {{cold_days}} 天后转低频 | 历史文件 |
| `{{module}}/*` | 归档 | {{archive_days}} 天后转归档 | 合规保留 |

## 7. CDN 加速配置

<!-- 指令: 如涉及 CDN 加速 -->

| 项目 | 配置 | 说明 |
|------|------|------|
| 加速域名 | {{cdn_domain}} | CNAME 解析 |
| 回源地址 | {{origin_address}} | OSS Bucket 域名 |
| 缓存规则 | {{cache_rule}} | 按文件类型/目录 |
| HTTPS | {{https_config}} | 证书配置 |
| 防盗链 | {{cdn_referer}} | 与 OSS 一致 |

## 8. 文件处理

<!-- 指令: 如涉及图片/视频处理 -->

| 处理类型 | 方式 | 参数 | 说明 |
|----------|------|------|------|
| 图片缩放 | OSS 图片处理 | {{img_resize_params}} | 缩略图 |
| 图片水印 | OSS 图片处理 | {{watermark_params}} | 版权保护 |
| 格式转换 | OSS 图片处理 | {{format_convert}} | WebP 适配 |
| {{custom_process}} | {{method}} | {{params}} | {{desc}} |

## 9. 配置清单

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| endpoint | {{endpoint}} | 内网/外网 |
| connectionTimeout | {{conn_timeout}}ms | 连接超时 |
| socketTimeout | {{socket_timeout}}ms | 读写超时 |
| maxConnections | {{max_connections}} | 最大连接数 |
| multipartThreshold | {{multipart_threshold}}MB | 分片上传阈值 |
| partSize | {{part_size}}MB | 分片大小 |

## 10. 容错设计

| 故障场景 | 影响 | 降级策略 | 恢复方式 |
|----------|------|----------|----------|
| OSS 不可用 | {{impact_1}} | {{fallback_1}} | {{recovery_1}} |
| 上传失败 | {{impact_2}} | {{fallback_2}}（断点续传） | {{recovery_2}} |
| CDN 回源失败 | {{impact_3}} | {{fallback_3}} | {{recovery_3}} |
| 文件误删 | {{impact_4}} | {{fallback_4}}（版本控制） | {{recovery_4}} |

## 11. 监控告警

| 指标 | 告警阈值 | 说明 |
|------|----------|------|
| 存储用量 | > {{storage_threshold}}% 预算 | 需清理/扩容 |
| 请求错误率 | > {{error_rate_threshold}}% | 服务异常 |
| 带宽峰值 | > {{bandwidth_threshold}}Mbps | 费用预警 |
| 4xx 比例 | > {{client_error_threshold}}% | 权限/路径问题 |

## 12. 安全红线

<!-- 指令: 以下为公司 OSS 安全红线，生成设计时必须遵守 -->

| 级别 | 规则 |
|------|------|
| 🚫 禁止 | Bucket 设置为公共读写（生产环境必须私有） |
| 🚫 禁止 | 在前端代码中硬编码 AK/SK（必须使用 STS 临时凭证） |
| 🚫 禁止 | 存储密码、身份证等敏感文件未加密 |
| ⚠️ 需审批 | 开启 Bucket 公共读（仅 CDN 静态资源场景） |
| ⚠️ 需审批 | 关闭版本控制（删除后不可恢复） |
| ✅ 允许 | 使用签名 URL 临时授权访问（有效期 ≤ 1h） |
| ✅ 允许 | 使用 STS 临时凭证授权前端上传 |
| ✅ 允许 | 使用生命周期规则自动清理临时文件 |
