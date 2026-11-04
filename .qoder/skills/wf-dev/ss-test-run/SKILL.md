---
name: ss-test-run
description: 运行测试并报告结果与覆盖率。执行单元/集成测试，收集通过率与覆盖率，产出 test-result.md。可独立用于任意时刻验证测试状态。
allowed-tools: Read, Write, Bash, Grep, Glob
---

# ss-test-run — 测试执行与报告

**阶段**: test | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 存在可运行的测试；构建环境可用。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `coverage.new_code` → 新增代码覆盖率阈值（默认 100%）
- `coverage.overall` → 整体覆盖率阈值（默认 70%）
- `workflow_dir.active` → 产物写入路径（`test-result.md`）

未读取配置文件不得开始执行。

## 规则依赖（按需读取）
执行前按需 Read（路径以 `.qoder/` 为基准，缺失则跳过）：
- `wf-rules/unittest-java.md` — Java 单元测试规范（项目为 Java 时，用于核对测试命名/结构合规）

## 输入
- `--scope unit|integration|all`
- `--slug <feature-slug>`（可选，用于写入 `WORKFLOW_DIR/test-result.md`）

## 执行步骤
0. **【环境预检】依赖版本可用性检查（防试错）**：执行测试命令前，先检查本地依赖缓存的可用版本（Java/Maven：`ls ~/.m2/repository/<group>/<artifact>/`，重点核对测试框架与插件版本，如 junit-jupiter / junit-platform-launcher / surefire；前端：`npm ls`）。目标版本不在缓存 → 先调整 POM/配置锁定到本地可用版本组合（含 dependencyManagement 防 BOM 覆盖），再继续。禁止不检查直接跑测试导致反复试错。
1. 运行测试：按 unit→integration 顺序执行对应测试命令（Java: 单元 `mvn -q test`，集成 `mvn -q verify`；前端: `npm test`；其他: 对应测试工具）。
2. 收集通过/失败用例、失败堆栈、覆盖率数据。
3. 写 `test-result.md`：通过率、覆盖率、失败清单（含定位线索）。

## 输出
- `test-result.md`（含真实命令输出摘要作为证据）。

## 完成标准 (Done)
- 报告基于真实执行输出；失败用例有可定位信息。

## basic vs enhanced
- basic：单元测试 + 通过率。
- enhanced：单元+集成 + 覆盖率阈值校验（按 `coverage.new_code` 和 `coverage.overall` 配置值）。

## 异常处理
- 有失败用例 → overallResult=FAIL，交由 ss-diag-rootcause / ss-tdd-cycle 修复回环，不得篡改测试掩盖。
