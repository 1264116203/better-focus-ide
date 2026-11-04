# tech-stacks 技术栈规则

本目录是 wf-dev 的技术栈规则库，由技能按 SKILL.md「规则依赖」按需读取，**不依赖框架自动加载**。

## 目录结构

```text
tech-stacks/
├── front-rules/
│   ├── Vue.md                    # Vue 栈入口（技术栈 + 索引 + 加载协议）
│   ├── React.md                  # React 栈入口
│   ├── rules-vue/                # Vue 全量规则（编码/结构/UI 库/测试/质量门禁）
│   │   └── frontend/
│   ├── rules-react/              # React 全量规则
│   │   └── frontend/
│   ├── rules-vue-lite/           # Vue 轻量规则（中小项目，入口 Vue-lite.md）
│   └── README.md                 # 本文件
└── backend-rules/
    ├── rules-java/Java.md        # Java 栈入口（JDK 17+ / Spring Boot 3.x）
    │   └── backend/              # 全量规则（含共享文件）
    ├── rules-java-17/Java-17.md  # Java 17 栈入口（含 JDK 17+ 特性边界）
    │   └── backend/              # 差异规则 + 共享引用
    └── rules-python/Python.md    # Python 栈入口（3.10+ / FastAPI / Django）
        └── backend/
```

## 加载方式

技能按「规则依赖」读取（路径以 `.qoder/wf-rules/tech-stacks/` 为基准）：

| 技能类别 | 读取内容 |
|---------|---------|
| 编码类（ss-tdd-cycle） | 对应栈入口文件 + `code-style.md` + `project-structure.md` + 框架规范（spring-boot.md / framework.md / UI 库规范） |
| 验证类（ss-tdd-cycle / ss-test-run / ss-test-integration） | 对应栈 `testing.md` / `test-profile-templates.md` / `phase4-6-*-dependencies.md` / `sonarqube.md` |
| 专项（涉及数据库/日志/监控/MQ 时） | 对应栈 `database.md` / `logging.md` / `monitoring.md` / `mq.md` / `clickhouse.md` |

## 规则集选择

* **rules-vue vs rules-vue-lite**：全量规则覆盖 UI 库（antd / element-plus）与完整测试模板，适合中大型项目；轻量规则（编码 4 文件约 1,194 行）适合中小项目。入口分别为 `rules-vue`（经 `Vue.md`）与 `rules-vue-lite/Vue-lite.md`。
* **rules-java vs rules-java-17**：JDK 21+ 项目用 `rules-java`；JDK 17 项目用 `rules-java-17`（含特性边界）。两者共享 `logging.md` / `monitoring.md` / `mq.md` / `clickhouse.md` / `test-profile-templates.md` / `phase4-6-backend-dependencies.md`，仅维护于 `rules-java/backend/`。

## 通用约定

* 覆盖率阈值一律以 `.qoder/wf-dev.yaml` 的 `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`），规则文件中不硬编码。
* 所有规则文件只描述规范与命令，不包含个人/项目特定路径、步骤编号（Phase x-y）或外部工作流协议。
