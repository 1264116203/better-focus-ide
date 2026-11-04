# Java SonarQube 规范（JDK 21+）

## 重要原则

> * 本文件为技术栈规则，执行时严格遵循
> * 新代码优先治理，历史代码逐步改善
> * SonarQube 是质量门禁，不可绕过

---

## 1. 目标定位

SonarQube 在本项目中定位为**质量门禁工具**，而非全面治理工具。重点关注：

- **新增代码零阻断问题**
- **核心模块高覆盖率**
- **安全漏洞零容忍**

---

## 2. 与其他规范的关系

| 规范 | SonarQube 职责 |
|------|---------------|
| code-style.md | SonarQube 检查代码风格违规 |
| testing.md | SonarQube 验证覆盖率达标 |
| project-structure.md | SonarQube 不检查目录结构（由人工审查） |
| 变更安全/命令约束（orchestrator-behavior.md） | SonarQube 不检查（由人工审查） |

---

## 3. 治理策略

### 3.1 优先级

| 优先级 | 目标 | 说明 |
|--------|------|------|
| P0 | 新代码零 Blocker/Critical | 每次提交必须通过 |
| P1 | 覆盖率达标（阈值见 wf-dev.yaml `coverage.*`） | 新代码必须达标 |
| P2 | 历史代码 Major 问题 | 按模块逐步改善 |
| P3 | 历史代码 Minor/Info | 低优先级，有空再处理 |

### 3.2 Quality Gate 配置

| 指标 | 阈值 |
|------|------|
| 新代码 Blocker | 0 |
| 新代码 Critical | 0 |
| 新代码 Security Hotspot | 0 确认 |
| 新代码覆盖率 | 以 wf-dev.yaml `coverage.new_code` 为准（默认 100%） |
| 新代码重复率 | ≤ 3% |

---

## 4. Java 特定 SonarQube 规则

### 4.1 安全相关（Blocker/Critical）

| 规则 ID | 规则 | 说明 |
|---------|------|------|
| S2068 | 硬编码密码 | 禁止在源码中硬编码密码/JWT Secret |
| S2078 | SQL 注入 | 禁止拼接 SQL，使用参数化查询 |
| S2095 | 资源未关闭 | IO 流、Connection 必须关闭 |
| S5332 | SSL/TLS 配置 | 不使用不安全的 SSL 配置 |
| S6289 | Log 注入 | 日志中不拼接未校验的用户输入 |

### 4.2 代码质量（Critical/Major）

| 规则 ID | 规则 | 说明 |
|---------|------|------|
| S1181 | 空 catch 块 | 禁止 `catch (Exception e) {}` |
| S1148 | 使用 System.out | 必须使用 SLF4J |
| S1165 | 异常中丢失原始信息 | catch 后 rethrow 必须携带原始异常 |
| S2221 | 直接抛 RuntimeException | 使用 BusinessException |
| S1182 | toString 返回敏感信息 | Entity/DTO @ToString 必须排除敏感字段 |
| S1135 | TODO/FIXME 遗留 | 不允许遗留未处理的 TODO |
| S1066 | 合并相同 if | 逻辑简化 |
| S131 | switch 缺 default | 必须有 default 分支 |
| S1155 | 空集合判断 | 使用 `isEmpty()` 而非 `size() == 0` |

### 4.3 重复与复杂度

| 规则 ID | 规则 | 说明 |
|---------|------|------|
| S104 | 类行数过多 | 单文件不超过 500 行 |
| S138 | 方法行数过多 | 方法不超过 100 行 |
| S114 | Cognitive Complexity 过高 | 核心方法不超过 15 |
| S125 | 注释中的代码 | 删除注释中的废弃代码 |
| S1192 | 魔术字符串 | 提取为常量 |

---

## 5. JDK 21+ 特定检查

| 规则 | 说明 |
|------|------|
| 使用 Pattern Matching instanceof | 替代传统 instanceof + cast |
| 使用 switch 箭头表达式 | 替代传统穿透 switch |
| Record 用于不可变 DTO | 替代 Lombok @Data |
| Sealed interface 用于错误码 | 替代 enum（可选） |
| Text Blocks 用于多行字符串 | 替代字符串拼接 |
| Virtual Threads 用于 I/O 密集型 | 替代线程池（可选） |

---

## 6. 修复要求

| 问题级别 | 处理方式 | 时间要求 |
|----------|---------|---------|
| Blocker | 必须立即修复 | 当前提交 |
| Critical | 必须修复 | 当前提交 |
| Major | 优先修复 | 本次迭代 |
| Minor | 建议修复 | 后续迭代 |
| Info | 记录 | 有空再处理 |

---

## 7. 扫描范围建议

| 场景 | 扫描范围 |
|------|---------|
| 日常开发 | 仅扫描本次改动的文件 |
| PR Review | 扫描 PR 涉及的所有文件 |
| 质量门禁 | 扫描全部新增代码 |
| CICD | 全量扫描 |

---

## 8. AI 约束

- AI 生成代码必须符合 SonarQube 新代码零 Blocker/Critical 标准
- AI 不修复与本次任务无关的历史 SonarQube 问题
- AI 可在总结中提示发现的历史问题，但不擅自扩大改动范围

---

## 最终回复要求

* 说明是否有 SonarQube 阻断问题
* 说明覆盖率是否达标
* 说明发现的历史问题（如有，仅提示不修复）