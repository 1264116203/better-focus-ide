---
name: ss-review-security
description: 安全扫描。对业务代码进行安全审查，检查注入/越权/硬编码密钥/敏感日志等安全问题。仅独立调用，未编入任何 wf-* 步骤。
allowed-tools: Read, Bash, Grep, Glob, Write
---

# ss-review-security — 安全扫描

**阶段**: review/security | **独立可用**: 是（未编入 wf-*） | **profile**: enhanced（basic 轻扫或跳过）

## 前置条件
- 功能测试已通过（先功能后安全）。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → 产物写入路径（`security-scan.md`）。本技能未注册 `hard_gates`，不作为工作流门禁。

未读取配置文件不得开始执行。

## 输入

[//]: # ( TODO completed-files.md没有产出位置，需要修正！！！)
- `--slug <feature-slug>`（可选）
- 扫描范围由 AI 从 `completed-files.md` 自动推导或用户 prompt 指定

## 执行步骤
1. 确定扫描范围（从 `completed-files.md` 推导或用户 prompt 指定的目录/文件）。
2. 对业务代码进行安全审查，逐文件检查以下安全维度：
   - **注入风险**：SQL 拼接、命令注入、XSS、LDAP 注入
   - **越权风险**：未校验权限的水平/垂直越权
   - **敏感数据泄露**：硬编码密钥/口令、敏感信息日志输出
   - **不安全反序列化**、**不安全随机数**、**路径遍历**
   - **安全配置**：CORS 过宽、Cookie 未设 HttpOnly/Secure
3. 汇总问题按严重度分级（Critical/High/Medium/Low），写 `security-scan.md` 与门禁判定。

## 输出
- `security-scan.md`（漏洞清单 + PASS/FAIL）。

## 完成标准 (Done)
- Critical/High/Medium 问题全部清零方可 PASS；Medium 同样必须修复，不得记 WARNING 放行；仅 Low 可记 WARNING 不阻断。

## basic vs enhanced
- basic：轻量扫描或跳过（记 N/A）。
- enhanced：完整业务代码安全审查，强门禁。

## 异常处理
- 发现 Critical/High/Medium → 转 ss-diag-rootcause + ss-tdd-cycle 修复回环，全部清零后重扫方可 PASS。
