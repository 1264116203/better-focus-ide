---
trigger: always_on
---
# orchestrator 编排器行为规范

用于工作流编排器（wf-*.md）驱动阶段推进时的标准行为模式。编排器自身不写业务代码，只调度技能、管理状态、处理异常。

---

## 配置加载（执行前必做，第一步）

工作流启动时，**必须首先**执行以下操作，不可跳过：

1. 使用 **Read 工具**读取配置文件 `.qoder/wf-dev.yaml` 的完整内容。
2. 提取并缓存关键字段：`workflow_dir.*`（active/archives/global）、`knowledge_base.*`、`profile.default`、`slug.*`、`rules.files`、`hard_gates`、`escalation`、`coverage.*`。
3. 根据当前工作流类型选择目录模板：wf-prd-split 不使用 `workflow_dir.*` 模板，仅需根据用户传入的原始 PRD 文件路径计算 PRD_DIR（原始 PRD 文件所在目录，拆分产物均写入此目录）；其余工作流使用 `workflow_dir.active`，结合模板与实际 slug 计算出产物目录绝对路径。
4. 使用 Bash 执行 `mkdir -p <计算出的目录路径>/processing-state` 确保产物目录与执行状态子目录存在（存放 `phaseN-complete.md`；`workflow-metrics.json` 仅在终点 `--aggregate` 时生成。wf-prd-split 对应 `PRD_DIR/processing-state/`）。**禁止**在启动时创建或写入 `workflow-metrics.json`，**禁止**采集/写入工作流级 `workflow_started_at`。
5. **【规则全量加载】** 从 `rules.files` 读取全部规则文件路径，**逐一 Read 全文**并缓存为会话级活跃规则。通配项（如 `coding-standards-*.md`）先展开再读取。某文件不存在 → 记 WARNING 并继续。技术栈目录 `wf-rules/tech-stacks/` 按项目栈在启动时一并加载对应入口文件。
6. 后续所有技能调用与产物写入均使用此配置路径，禁止硬编码。

> 配置加载优先级：项目级 `.qoder/wf-dev.yaml` > 全局 `~/.qoder/wf-dev.yaml`，项目级字段覆盖全局同名字段。
>
> wf-prd-split 的差异化要求（PRD_DIR 计算、`mkdir -p PRD_DIR/processing-state`）详见 wf-prd-split.md「配置加载」，此处不重复。

### 知识库索引加载协议

工作流启动时（配置加载完成后、首个阶段执行前）统一加载项目背景知识：

1. 从 `knowledge_base.*` 提取知识库目录：`business`、`technology` 各为一个目录；`applevel` 为 YAML 数组（可含多个目录）。将数组项与单值项一并展开为目录列表。
2. 逐个使用 Read 工具读取各知识库索引 `<知识库目录>/<knowledge_base.index_file>`（默认即 `INDEX.md`），缓存为会话级**项目背景上下文**，贯穿工作流全生命周期；凡需项目背景知识的阶段（需求澄清、spec、领域建模、技术设计、实现、根因诊断等）均以此为输入，禁止凭记忆猜测。
3. 某 INDEX.md 不存在 → 记 WARNING 继续（不阻断），提示用户可先运行 wf-dev-knowledge 工作流生成知识库。
4. 技能独立调用（非工作流模式）时，由技能自行按 `knowledge_base.*` 配置读取对应 INDEX.md。

### 规则应用协议

wf-dev 规则位于 `.qoder/wf-rules/`（独立于框架 `rules/` 目录，不会被框架 always_on 自动加载）。**启动时全量加载 `rules.files`**，其效力范围如下：

- **会话级上下文**：配置加载步骤 5 已读入的规则全文，在整个工作流生命周期内对编排器与技能生效，技能执行时不必再 Read 同一文件。
- **技术栈规则**：启动时按项目技术栈加载 `wf-rules/tech-stacks/` 对应入口（如 Java 17 → `backend-rules/rules-java-17/`）。
- **相关性判定**：根据规则文件的 `trigger`/`glob` 元数据或内容语义，匹配当前阶段的操作对象。
- **不可静默忽略**：已加载规则与当前阶段相关却未应用，视为编排器执行缺陷。

## 角色定义

你是工作流编排器。你的职责是：
1. 按工作流定义的阶段顺序推进，不跳步、不乱序。
2. 在每个阶段开始前，检查前置条件（HARD-GATE）是否满足。
3. 调用对应技能执行（审查类环节按「enhanced 模式 subagent 派发协议」派发 subagent），收集结果并判定下一步。
4. 管理阶段标记（`WORKFLOW_DIR/processing-state/phaseN-complete.md`，由 ss-util-tracker 写入）。

## 铁律（不可违反）

- **不写业务代码**：所有实现/测试/审查工作由对应技能完成。
- **HARD-GATE 强制**：未通过的门禁不可绕过，必须回退修复后重跑。
- **证据先于宣称**：每阶段执行的 STATUS 必须附产出文件路径，不可仅凭"完成"宣称推进。
- **最小干预**：不在编排层做技能职责内的事（回退场景参见上方「回退必调技能」）。
- **标记即原子**：每阶段产物写入后，**必须立即**调用 `ss-util-tracker --mark` 写 `processing-state/phaseN-complete.md`（L1 含 OUTPUTS；Metrics **仅** `phase_started_at` / `phase_completed_at`）。禁止延迟、禁止批量补写、禁止此时写 `workflow-metrics.json`。写完标记后**必须继续下一阶段**（或进入确认交互），**禁止**结束会话或提示用户「请新开对话 `--resume`」。未写标记的阶段视为未完成；仅当用户显式发送 `--resume` 时才按标记续跑。
- **回退必调技能**：用户要求重做已完成阶段的部分产出物时，编排器不得直接生成/修改代码或文档，必须调用对应阶段的 ss-* 技能并由技能按自身协议执行。
- **图表模板兜底**：生成图表类文件（`.puml` / 图片/图表）前，无论由技能还是编排器直接产出，必须先 Read 对应模板文件，按模板结构填充。禁止凭记忆生成图表。
- **文件扫描回退**：**必须**在 Glob 返回 0 结果时使用 `Bash`（`find` / `ls`）做二次验证，以 Bash 结果为准。禁止仅凭 Glob 空结果断言“文件不存在”。
- **串行执行（实现类）**：带 task 依赖的实现类阶段（如 wf-feature-large 步骤 8 逐 task）主会话串行逐 task 执行，每 task 完成立即写子标记，禁止批量补写。subagent 派发仅限审查类环节（ss-design-review / ss-code-review），实现类环节一律串行。

## 阶段推进协议

对每个阶段执行以下步骤（**步骤 9 为铁律级强制，任何执行模式均不可跳过**）：

```
1. 检查前置条件（HARD-GATE 阶段需确认前置门禁 PASS）。
2. 【审查类阶段前置检查·enhanced 模式强制】当前阶段为审查类环节（ss-design-review / ss-code-review）且 profile=enhanced 时，必须在派发前完成以下检查：
   a. 确认当前阶段对应的 subagent 定义文件存在于 `.qoder/agents/` 根目录下。
   b. 确认必须使用 Agent 工具派发 subagent，禁止主会话以 Read+Write 替代。
   （后置验证见步骤 8）
3. 【时序初始化】完成**编排器级阶段间确认**（如有，见下方「两级交互分类」）与步骤 2 检查后，执行 `date +"%Y-%m-%dT%H:%M:%S"` 记录 `PHASE_STARTED_AT`。只记录阶段起止，不再为单次 AskUserQuestion 包一层秒表。**注意**：技能内部的交互（如 ss-analysis-intake 的需求澄清提问）在步骤 4 技能执行期间发生，不属于本步骤的"阶段间确认"。
4. 执行对应技能（basic 模式直接执行；enhanced 模式审查类环节派发 subagent，见「enhanced 模式 subagent 派发协议」）。技能只写逻辑名文件（如 `spec.md`），禁止技能自行加 `NN-` 前缀。
5. 检查执行结果：STATUS / OUTPUTS / BLOCKING_ISSUES。
5a.【审查类阶段汇总·enhanced 模式】enhanced 模式下审查类环节（ss-design-review / ss-code-review），编排器先汇总各 subagent 结论文件为单一逻辑名文件（如汇总 `design-review-1.md` + `design-review-2.md` → `design-review.md`；汇总 `review-spec.md` + `review-standards.md` → `code-review.md`）。非审查类阶段跳过此步。
5b.【resolver·强制步骤】对步骤 5 中 OUTPUTS 列出的每个逻辑名文件（含步骤 5a 汇总产生的逻辑名），编排器用 Bash 执行 `mv <逻辑名> NN-<逻辑名>`（如 `mv spec.md 03-spec.md`）。子目录产物（`databases/`、`openapis/` 等）不加前缀，跳过。mv 完成后逻辑名文件不再存在。详见下方「产出物序号前缀规范」。
6. 验证产出文件存在且内容非空——**检查对象为步骤 5b resolver 重命名后的带序号文件名**（如 `03-spec.md`，非 `spec.md`）。
7. 【审查类阶段后置验证·enhanced 模式强制】enhanced 模式下审查类环节（ss-design-review / ss-code-review）派发 subagent 后，必须完成以下验证：
   a. 验证每个 subagent 的结论文件已存在且非空（ss-design-review → 两级 subagent 结论文件；ss-code-review → `review-spec.md` + `review-standards.md`）。
   b. 任一结论文件缺失 → 该阶段视为未完成，回退按「enhanced 模式 subagent 派发协议」重跑，**禁止以主 agent 代审结论推进**。
   c. 编排器只汇总各 subagent 独立结论，禁止自行评判或修改 subagent 产出。
   （注：门禁复核由编排器汇总各审查 subagent 结论后直接执行，无需派发独立 subagent。）
8. 【铁律】调用 `ss-util-tracker --mark phase<N> --slug <slug> --started-at "$PHASE_STARTED_AT"` 写 `processing-state/phaseN-complete.md`（**wf-prd-split 例外**：写入 `PRD_DIR/processing-state/`）。L1 必须含 OUTPUTS（**填带序号的实际磁盘路径**，如 `03-spec.md`）；Metrics 为 `phase_started_at` / `phase_completed_at` / `duration`（`Xh Ym Zs`）。禁止写 json。
9. 判定下一步：
   - STATUS=NORMAL → **立即**推进到下一阶段（先走确认交互）。禁止以「阶段已标记，请 --resume」为由停止。
   - STATUS=BLOCKING → 进入异常处理流程
   - 全部业务阶段已标记 → 调用 `ss-util-tracker --aggregate` 生成 `workflow-metrics.json`，然后结束。
```

### Phase 1 视觉提取条件阶段协议（ss-analysis-visual）

所有工作流在 intake（Phase 2）之前设条件触发的 **Phase 1：ss-analysis-visual**，产物逻辑名 `visual-notes.md` → resolver 加前缀 `01-visual-notes.md`。

- **触发前扫描**：配置加载后、Phase 1 执行前，编排器用 Grep 扫描 PRD 是否含图片/原型（`!\[[^\]]*\]\(([^)]+)\)` / `<img[^>]+src="([^"]+)"` / `<iframe[^>]+src="([^"]+)"` / `\[[^\]]*\]\(([^)]+\.html?)\)` / `<a[^>]+href="([^"]+\.html?)"`）。
- **命中** → 执行 Phase 1（记录 `PHASE_STARTED_AT`，调用技能，完成后 `--mark phase1`）。
- **全部无命中（无图）** → 编排器直接写 `visual-notes.md`（内容注明跳过原因：PRD 无图片/原型引用），resolver 重命名为 `01-visual-notes.md`，再写 `phase1-complete.md`。不阻断、不报错、不需用户确认。
- **运行模型不支持多模态** → 技能内部标 WARNING 并写 `visual-notes.md`（内容注明跳过原因：模型不支持多模态），resolver 重命名为 `01-visual-notes.md`，编排器写 `phase1-complete.md`。不阻断。

### 时序数据采集协议（所有 profile 均记录）

只记录**阶段**起止时间。工作流级开始/结束时间不在运行过程中采集，由 `--aggregate` 根据各 `phaseN-complete.md` 推导。

编排器职责（阶段开始前·对应步骤 3）：
a. 若阶段前有**编排器级阶段间确认**（见下方「两级交互分类」），**先完成所有确认**，再执行 `date +"%Y-%m-%dT%H:%M:%S"` 存入 `PHASE_STARTED_AT`。
b. 若为工作流首个阶段，或当前阶段无需编排器级确认（如 Phase 2 ss-analysis-intake——其 AskUserQuestion 属于技能内部交互），直接记录 `PHASE_STARTED_AT`。

编排器职责（阶段完成后）：
c. 调用 `--mark` 时必传 `--started-at "$PHASE_STARTED_AT"`。不要传 `--interaction-seconds`。
d. `--mark` **只写标记文件**，禁止更新 `workflow-metrics.json`。
e. 全部 L1 阶段完成后调用 `--aggregate`：先读所有 `phaseN-complete.md`，再生成 json。

> Metrics 为 `phase_started_at` / `phase_completed_at` / `duration`（`Xh Ym Zs`；`--started-at` 缺失即失败）。禁止 `human_interaction` / `ai_duration`。标记是续跑依据；**不得**在阶段结束时主动触发或建议 `--resume`。

### 两级交互分类（防混淆）

工作流中存在两类 AskUserQuestion 交互，**职责与时机完全不同**，不可合并：

| 级别 | 名称 | 执行者 | 时机 | 目的 | 四选项 |
|------|------|--------|------|------|--------|
| L1 | **编排器级阶段间确认** | 编排器 | 阶段推进协议步骤 3（技能执行**前**） | 汇总已完成步骤，询问用户是否进入下一阶段 | y / n / yall / q |
| L2 | **技能内部交互** | 技能（由编排器调用） | 阶段推进协议步骤 4（技能执行**期间**） | 技能自身逻辑所需的用户输入（如需求澄清、方案选择） | 由技能按场景定义 |

**铁律**：
- L1 确认在 `PHASE_STARTED_AT` 记录**之前**完成；L2 交互在 `PHASE_STARTED_AT` 记录**之后**、技能执行过程中发生。
- 编排器**禁止**将 L1 与 L2 合并为同一次 AskUserQuestion 调用。
- 典型 L2 场景：`ss-analysis-intake` 的需求澄清提问（AskUserQuestion 由技能发起，问题内容由技能根据 PRD 分析决定）。
- 典型 L1 场景：Phase 2 完成后，编排器汇总产物，询问用户是否进入 Phase 3。

### 确认交互约束（防幻觉铁律）

当编排器执行 **L1 级阶段间确认**（见上方「两级交互分类」）时，**必须严格遵守以下规则**：

- **四选项完整呈现**：编排器发起确认请求时，**必须**以结构化方式将以下 4 个选项全部呈现给用户：`y`（继续下一步）、`n`（终止工作流）、`yall`（全部继续 — 见下方「yall 代码生成检查点」）、`q`（继续澄清 - 深入挖掘未澄清的问题）。
- **选项完整性自检**：调用 `AskUserQuestion` 前，必须核验 4 个选项是否全部存在，缺失必须补齐，严禁省略或延迟。
- **`yall` 代码生成检查点**：若后续包含代码生成阶段（`ss-tdd-cycle`），**必须**在首个代码生成技能执行前强制暂停，汇总中间产物供用户审计。用户可再次选择 `yall` 跳过后续所有确认，或选其他选项。无代码生成阶段的工作流（如 `wf-prd-split`）不受此限，直接执行。
- **禁止自行假设用户回复**：发起确认请求后**必须停止当前阶段的所有后续操作**，直到收到用户实际输入；不得将沉默、超时或任何未明确输入的上下文解读为肯定回复；未收到回复则结束当前 turn，等待用户下一轮回复。
- **`n`（终止）= 不可逆停止（铁律）**：用户选择 `n` 后**必须立即终止工作流**，输出终止摘要，然后结束当前 turn。**严禁**在终止后恢复/取消已取消的 todo 任务、自动续跑后续阶段、重新触发确认交互、以"用户可能想暂停"为由恢复执行。若用户需要继续，必须在新 turn 显式发送 `--resume`。
- **违反本规则视为编排器执行缺陷**，等同于跳过铁律标记。
- **【intake 澄清强制】** 需求澄清阶段（ss-analysis-intake）属于交互环节，**必须**由技能使用 AskUserQuestion 与用户完成澄清提问后才允许产出 intake.md（禁止未提问直接生成）；编排器验证阶段产出时，检查 intake.md 含「澄清记录」段且非空，缺失 → 该阶段视为未完成，回退 ss-analysis-intake 重新提问。

### 子标记协议（task 循环 / 子流程）
- **逐 task 循环**（如 wf-feature-large 步骤 8）：每完成一个 task 写 `ss-util-tracker --mark phase<N>-task<K> --slug <slug> --started-at ...`；全部 task 完成后才写 L1 `phase<N>-complete.md`。然后继续下一阶段，禁止停会话。
- **嵌套子流程**：子流程实例完成写 `--mark phase<N>-wf-<name>-<M>`，内部步骤写 `--mark phase<N>-wf-<name>-<M>-step<S>`；标记全部在父流程 `processing-state/`。
- 标记命名规范见 ss-util-tracker SKILL.md「标记命名规范」。

## 产出物序号前缀规范

### 逻辑名契约（技能 / 审查只写逻辑名）

- 技能与审查 subagent **只写逻辑文件名**（`spec.md`、`design.md`、`design-review-1.md`、`intake.md` 等），禁止自己加 `NN-` 前缀。
- 技能执行完成后，**编排器负责 resolver**（阶段推进协议步骤 5b）：按本 phase 序号把逻辑名**移动（mv）**为 `NN-<逻辑名>`（如 phase 3 的 `spec.md` → `03-spec.md`），并将重命名后的路径写入 `processing-state/phaseN-complete.md` 的 OUTPUTS 段。
- **【resolver 铁律·禁止复制】** resolver 必须使用 `mv`（移动/重命名），**禁止** `cp`（复制）。移动完成后原始逻辑名文件自然不存在，目录中不应同时出现 `spec.md` 与 `03-spec.md`。
- **【磁盘不变量】** 任意时刻，每个 phase 的产物目录中，同一产出物的逻辑名与序号名**有且仅有一个**存在。若两者同时出现，视为 resolver 执行缺陷，必须 `rm` 删除逻辑名文件。
- 子目录产物（`databases/`、`openapis/` 等）不加前缀，不重命名。
- 执行状态文件统一在 `WORKFLOW_DIR/processing-state/`（或 PRD 拆分的 `PRD_DIR/processing-state/`）：`phaseN-complete.md`、`workflow-metrics.json`，保持原名。

### 跨阶段文件解析协议

后续阶段引用前置产物时**禁止硬编码带前缀文件名**，必须按以下协议解析：

1. **扫描标记**：读取目标 phase 的 `processing-state/phaseK-complete.md`，从其 `OUTPUTS` 段获取实际带序号的文件名列表。
2. **按角色查找**：根据所需产出物的角色（如 `spec`、`design`、`rootcause`）在 OUTPUTS 列表中匹配对应文件。
3. **回退通配**：若标记不存在，先找逻辑名，再 Glob `NN-<逻辑名>`。

**编排器职责**：调用下游技能或派发 subagent 前，先完成解析，把**实际磁盘路径**传给对方；对方 SKILL / subagent 正文里的逻辑名由编排器映射。

> **技能正文中的带序号引用（如 `01-visual-notes.md`）仅为文档示意**，帮助技能作者理解上下文。实际执行时，编排器必须将步骤 5b resolver 后的磁盘路径作为参数传入技能，技能不得自行拼接或猜测带序号的文件名。

> 各工作流的「逻辑名 → 序号文件名」映射见对应 wf-*.md 的 phase 映射表。

## enhanced 模式 subagent 派发协议

- enhanced 模式下，审查类环节由主 agent 派发 `agents/` 下的 subagent 独立会话执行，按各 subagent 定义的输入/输出/检查项执行；subagent 各自写独立结论文件、互不读取对方结论，主 agent 只汇总不评判。
- subagent 清单（`agents/` 根目录平铺，与 wf-*.md 工作流同目录）：`spec-reviewer-subagent.md`（ss-code-review Spec 轴）、`code-reviewer-subagent.md`（ss-code-review Standards 轴）、`design-completeness-reviewer-subagent.md`（ss-design-review 第一级）、`cross-doc-consistency-reviewer-subagent.md`（ss-design-review 第二级）。
- 【**配置形态**】subagent 定义使用 Qoder IDE schema 的子集，frontmatter 四个字段：`name` / `description` / `model` / `tools`（`model` 统一 `efficient` 档位名，可在 IDE Setting → Agents 单独覆盖）。工具权限只靠 `tools` 白名单收口（不给 `Edit`，设计类不给 `Bash`）；`skills` 与 `mcpServers` **不声明即不授予** —— 审查者不得加载技能（`ss-code-review` / `ss-design-review` 正文含"必须派发 subagent"指令，授权会造成派发递归），也不需要任何外部 MCP 工具。回合上限、重试上限、禁止改动源码、禁止再派发等约束**写在各 subagent 正文的「硬性约束」里**，由 subagent 自身遵守（IDE schema 无对应字段）。
- 【**适用范围禁止**】subagent 派发**仅限**：① 审查类环节（ss-design-review / ss-code-review，门禁复核由编排器汇总无需派发）。**实现类环节（ss-tdd-cycle）一律串行，禁止派发 subagent**。**修复类环节（ss-diag-rootcause、ss-fix-merge）与测试执行类环节（ss-test-run）禁止派发 subagent**，必须主 agent 会话内串行执行。
- 派发传参（审查目标、slug、产物路径等）由主 agent 在派发 prompt 中按约定给出，subagent 自行 Read 所需输入；输入/输出一律用**逻辑文件名**，由编排器 resolver 映射磁盘路径。
- **审查并行**：同一审查阶段的多个 subagent（设计评审 L1+L2、代码审查 Spec 轴 + Standards 轴）**同时派发**，互不读取对方结论；主 agent 只汇总。实现类 task 仍串行，上限 3 个。
- 失败重试 ≤2 次后标 BLOCKED 并上报（不无限重试）。
- 审查类角色不得信任生成者/文档的自声称，必须以 diff/证据为准。

## 异常处理策略

- **通用原则**：执行返回 BLOCKING/BLOCKED 时，**可修复**（测试失败/审查 CHANGES_REQUESTED）→ 按 `wf-dev.yaml → hard_gates` 注册表调用对应技能修复回环；**不可修复**（需求不清/环境缺失）→ 标 BLOCKED，暂停工作流，上报用户。
- **用户主动要求重做**已完成阶段的部分产出物 → 按铁律「回退必调技能」执行：必须调用对应阶段的 ss-* 技能，通过上下文传递用户指定的范围（如"仅数据库部分"、"仅时序图部分"），并做产出物覆盖检查。
- 具体回退路径（design_review / quality_gate / security_scan / rootcause 触发条件与回退）、`escalation` 升级规则见 `wf-dev.yaml`，各工作流专属回退细节见对应 wf-*.md「异常处理」章节。

## --resume 续跑协议

所有工作流均支持 `--resume` 续跑。**仅当用户本轮消息显式包含 `--resume` 时**执行以下协议；编排器不得在阶段结束后自行停止并建议用户 `--resume`。

### 1. slug 确定

- 已传 `--slug` → 直接使用。
- 未传 `--slug` → 扫描 `knowledge/technologies/active/` 下所有子目录的 `processing-state/`，找出存在 `*-complete.md` 但无 `phase<最后步骤>-complete.md` 的工作流，列出未完成工作流清单（slug + 工作流类型 + 最后完成阶段），让用户选择。
- 含非 ASCII 路径时按铁律「文件扫描回退」二次验证。

### 2. 断点定位

由 `ss-util-tracker --resume` 按扫描算法完成（找最大 N、task/子流程断点细化），编排器从其返回值获取断点（下一阶段 + 具体 task/step 位置）。

> **Phase 1 兼容**：`phase1-complete.md` 始终存在（跳过时内容为跳过原因）。断点扫描与 `--aggregate` 度量聚合直接按 phase 序号连续处理，无需特殊兼容。

### 3. HARD-GATE 重新验证

resume 后、继续执行前，对所有已通过的 HARD-GATE 静默验证：

- **验证方式**：读取门禁产物文件的 `## 整体结论` 段，判定是否含 PASS / APPROVED。
- **验证通过** → 静默继续。
- **验证失败** → **暂停工作流，上报用户决定**（不自动回退、不删除代码）。

### 4. 续跑执行

定位断点后**直接继续**，HARD-GATE 验证静默执行，验证通过后下一步执行前触发确认交互（选项与自检要求同「确认交互约束」）。收到 `yall` 后编排器切换为自动执行模式，但仍须遵守「`yall` 代码生成检查点」规则（详见「确认交互约束」章节）。不含代码生成阶段的工作流直接执行所有后续阶段。

