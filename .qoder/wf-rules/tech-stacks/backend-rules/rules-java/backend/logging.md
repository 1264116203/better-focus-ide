# 日志输出规范

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循

---

## 1. 日志框架

- 使用 SLF4J + Logback，禁止直接使用 `System.out`（详见 code-style.md Section 9）

---

## 2. 日志内容要求

| 规则 | 说明 |
|------|------|
| 减少无用日志 | 不记录方法开始/结束、无意义耗时日志 |
| 日志必须包含关键字段 | 支持上下文关联追踪：userId、orderId、requestId、traceId 等 |
| 异常日志必须带堆栈 | `log.error("XXX failed: {}", e.getMessage(), e)` — 保留完整堆栈 |
| 日志中禁止打印敏感信息 | 不打印密码、token、完整手机号 |

**关键字段日志示例：**

```java
log.info("User login: userId={}, phone={}", userId, PhoneMaskUtil.mask(phone));
log.error("External service call failed: service={}, error={}", serviceName, e.getMessage(), e);
```

---

## 3. 日志级别使用

| 级别 | 使用场景 |
|------|---------|
| ERROR | 系统异常、外部调用失败、需立即关注的问题 |
| WARN | 业务异常、非预期但可控的情况 |
| INFO | 关键业务操作（登录、下单、状态变更） |
| DEBUG | 开发调试信息，生产环境默认关闭 |

---

## 4. 参考规范

- 日志标准及研发中问题的系统解决方案.pdf

---

## 最终回复要求

* 说明日志是否包含关键追踪字段
* 说明是否减少了无用日志
* 说明异常日志是否带完整堆栈