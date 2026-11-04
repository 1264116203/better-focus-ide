---
name: ss-design-tech
description: 技术设计。基于规格与领域模型产出分层架构、API 契约、数据库 DDL、缓存、异常/降级与安全策略，并按需生成 PlantUML 图表、RESTful API 文档、中间件设计文档等附属产出物。可独立为某需求出技术方案。
allowed-tools: Read, Write, Grep, Glob
---

# ss-design-tech — 技术设计

**阶段**: design | **独立可用**: 不推荐独立调用 | **profile**: basic/enhanced

## 前置条件
- 有 spec.md（enhanced 另需 domain.md）；按「规则依赖」读取对应栈规则。

## 配置加载
执行前**必须**使用 Read 工具读取 `.qoder/wf-dev.yaml`，提取以下字段：
- `workflow_dir.active` → 产物写入路径
- `slug.*` → slug 格式校验

未读取配置文件不得开始执行。

## 规则依赖（按需读取）
执行前按需 Read（路径以 `.qoder/` 为基准，缺失则跳过）：
- `wf-rules/tech-stacks/` — 技术栈规则目录（按项目技术栈读取对应子目录，设计分层/依赖约定以栈规则为准）

## 模板加载
执行前**必须**读取 `templates/design-artifacts-spec.md`（相对于本技能目录），了解产出物规范与按需生成规则。根据设计涉及的中间件/组件，按需读取对应模板：
- `templates/diagrams/sequence-diagram.puml` — 时序图模板（涉及跨服务调用时必读）
- `templates/diagrams/activity-diagram.puml` — 活动图模板（涉及业务流程时必读）
- `templates/diagrams/component-diagram.puml` — 组件图模板（涉及系统集成时必读）
- `templates/diagrams/relation-diagram.puml` — **关联关系图模板（涉及新增/变更表时必读，生成任何关联关系图前必须先读取此模板）**
- `templates/openapis/restapi-template.md` — 统一 REST API 文档模板
- `templates/databases/ddl-spec.md` — DDL 规范模板
- `templates/middlewares/*.md` — 中间件设计模板
- `templates/elasticsearch/es-index.md` — ES 索引设计模板

> ❗ **强制约束**：生成任何图表（`.puml`）前，必须先 Read 对应的模板文件，严格按模板结构填充。禁止凭记忆生成图表。

## 输入
- `--slug <feature-slug>`
- 工作流模式下自动读取 `WORKFLOW_DIR/spec.md`、`WORKFLOW_DIR/domain.md`；技术栈由 AI 从项目文件自动检测

## 执行步骤
0. **【引用约束】前置文档引用而非复述**：design.md 中涉及 spec 功能点/验收标准、domain 实体关系的内容，一律用相对链接引用（如 `参见 02-spec.md §功能点 F1`、`参见 03-domain.md §实体关系`），**禁止复制**前置文档内容；只新增设计层的新信息（架构、API 契约、DDL、策略）。状态机/接口契约等设计层权威定义可在 design.md 中完整给出，但不得与 spec 中已有描述重复。
   - **【视觉对齐】** 若 `01-visual-notes.md` 存在，技术时序图/架构图**必须对齐**其中 PRD 原图（技术时序图/架构图）的提取结果，不得仅凭文本凭空重画产生偏差；UI 图提取的字段/交互/校验/多端差异驱动前端设计。引用用相对链接（如 `参见 01-visual-notes.md §图1`），禁止复述。该产物不存在时正常跳过。
1. 确定 spec_strategy（A/B/C）并写入 design.md，作为后续强制约束。
2. 设计分层架构与模块交互；定义 API 契约（请求/响应/错误码）。
3. 设计 DB DDL、索引、缓存结构；异常处理、降级、幂等、并发策略。
4. 补安全设计（鉴权/越权/敏感数据）与非功能指标。
5. 写 `design.md` + `api-spec.yaml` +（如涉表）`ddl.sql`。
6. **按需生成附属产出物**（见下方「产出物生成规则」）。

## 产出物生成规则

根据 design.md 中涉及的技术组件，按 `templates/design-artifacts-spec.md` 第 7 节的条件表按需生成：

| 条件 | 产出物 | 输出路径 |
|------|--------|----------|
| 涉及跨服务/跨层调用 | 时序图 | `diagrams/sequence-<name>.puml` |
| 涉及业务流程/状态转换 | 活动图 | `diagrams/activity-<name>.puml` |
| 涉及新模块/系统集成 | 组件图 | `diagrams/component-<name>.puml` |
| 涉及新增 REST API | API 文档 | `openapis/provider/restapi-<module>.md`；若调用三方则加 `openapis/consumer/<name>-api.md` |
| 涉及新增/变更表 | DDL + 关联图 | `databases/{db-type}-{db-name}-ddl.sql` + `databases/*-relation-{domain}.puml`（**必须先读取 `templates/diagrams/relation-diagram.puml` 模板**） |
| 涉及 Redis 缓存 | Redis 设计文档 | `middlewares/redis-<name>.md` |
| 涉及 RocketMQ | RocketMQ 设计文档 | `middlewares/rocketmq-<name>.md` |
| 涉及 Kafka | Kafka 设计文档 | `middlewares/kafka-<name>.md` |
| 涉及定时任务 | SchedulerX 设计文档 | `middlewares/schedulerx-<name>.md` |
| 涉及文件存储 | OSS 设计文档 | `middlewares/oss-<name>.md` |
| 涉及全文检索 | ES 设计文档 | `elasticsearch/es-<index>-mapping.json` |

生成时**必须**读取对应模板文件，按模板章节结构填充实际设计内容。

### 模板强制协议（不可跳过）

对每个按需产出物，执行以下 **3 步闭环**：

1. **加载**：使用 Read 工具读取对应模板文件全文。未 Read 则禁止开始写该产出物。
2. **填充**：严格按模板的 `##` 级章节顺序逐节填充，不得省略任何必选章节、不得合并章节、不得用 bullet 代替表格。模板中 `{{placeholder}}` 替换为实际值，`<!-- 指令 -->` 为行为约束须遵守。
3. **校验**：写完后，将产出物的一级/二级标题列表与模板的标题列表逐条对照。若缺少任何必选章节，**立即补全后再进入下一个产出物**。

> 特别强调 `openapis/` 文档：模板 `restapi-template.md` 中「接口详情」章节要求**每个接口**均展开完整的 Path/Query/Body 参数表 + curl 示例 + 响应体 + data 字段表 + 错误响应。接口数量多时不得以「详见 api-spec.yaml」替代，必须逐个展开。若单文件超过 1000 行，可按模块拆分为多个文件（如 `restapi-order-core.md`、`restapi-order-payment.md`）。

## 输出
- `design.md`、`api-spec.yaml`、`databases/{db-type}-{db-name}-ddl.sql`
- 按需：`diagrams/*.puml`、`openapis/consumer/*.md`、`openapis/provider/*.md`、`databases/*-relation-*.puml`、`middlewares/*.md`、`elasticsearch/es-*-mapping.json`

## 完成标准 (Done)
- 覆盖 spec 全部功能点；架构符合 rules；API/DB 可直接指导编码。
- 按需产出物齐全（对照条件表无遗漏）；图表/文档符合模板结构约束。
- **每个产出物的章节标题必须与对应模板的章节标题一一对应**（允许新增子章节，禁止缺少模板必选章节）。

## basic vs enhanced
- basic：单文件轻量设计 + 按需产出物（可合并为 design.md 附录）。
- enhanced：完整设计 + 独立 API 契约 + 安全/降级章节 + 全部按需产出物独立文件。

## 异常处理
- 发现 spec 缺口 → 回退 ss-analysis-spec 补充，不自行臆测。
