# 项目协作规范（Vue 版）

> **入口文件**：本文件是 wf-dev 技术栈规则（Vue）的入口，由编码类技能（ss-tdd-cycle）按 SKILL.md「规则依赖」读取。详细编码/结构/测试规范按需读取下方索引文件，不在本文件重复维护。

## 语言

* 默认使用中文交流、解释、总结和变更说明。
* 代码中的命名、文件名、类型名、组件名保持英文规范。
* 除非我明确要求，否则不要切换其它语言回复。

## 项目目标

* 这是一个前端项目，必须完全遵循现有技术栈、目录结构。
* 如业务需要其他技术栈，需要经过我的允许，由我来决定。
* 修改时优先采用最小可行改动，不做无关重构。

## 修改原则

* 遇到不确定逻辑时，先查看调用链、路由入口、状态来源、权限逻辑，再修改。
* 先理解上下文，再改代码；避免未经确认的大范围重构。
* 修改时尽量复用现有组件、工具函数、样式变量和约定。
* 优先做最小可行修改，保持现有行为兼容。
* 不要顺手修改与当前任务无关的逻辑；发现潜在问题可在最终总结中提示，不擅自扩大改动范围。
* 不要为了"更优雅"而改变已有稳定行为。
* 修改公共组件时，检查受影响调用方。

## 技术栈

* vite@8 / vue@3 / vue-router@4 / pinia@3
* ant-design-vue@4 / element-plus@2 / @ant-design/icons-vue
* axios@1.15.0 / less / dayjs / ali-oss

## 规则文件索引（路径以 `.qoder/wf-rules/tech-stacks/` 为基准）

| 文件 | 内容 | 按需读取时机 |
|------|------|-------------|
| `front-rules/rules-vue/frontend/code-style.md` | 编码风格：命名/模板/状态/路由/接口/样式 | 编码与代码审查 |
| `front-rules/rules-vue/frontend/project-structure.md` | 项目目录结构与职责 | 编码与结构评审 |
| `front-rules/rules-vue/frontend/antd.md` | Ant Design Vue 使用规范 | 使用 antd 时 |
| `front-rules/rules-vue/frontend/element-plus.md` | Element Plus 使用规范 | 使用 element-plus 时 |
| `front-rules/rules-vue/frontend/sonarqube.md` | SonarQube 质量门禁 | ss-test-run |
| `front-rules/rules-vue/frontend/testing.md` | 测试规范（test_env 模式选择） | ss-tdd-cycle / ss-test-run |
| `front-rules/rules-vue/frontend/test-profile-templates.md` | Vitest 配置模板 | ss-tdd-cycle |
| `front-rules/rules-vue/frontend/phase4-6-frontend-dependencies.md` | 验证依赖安装指引 | ss-test-* 需安装依赖时 |

## 加载协议

* **编码类技能**（ss-tdd-cycle）：读本文件 + `code-style.md` + `project-structure.md` + 对应 UI 库规范（antd / element-plus）。
* **验证类技能**（ss-tdd-cycle / ss-test-run）：读 `testing.md` / `test-profile-templates.md` / `phase4-6-frontend-dependencies.md` / `sonarqube.md`。覆盖率由 `ss-test-run` 按 yaml 校验。
* 覆盖率阈值以 `.qoder/wf-dev.yaml` 的 `coverage.*` 为准（默认 `new_code: 100` / `overall: 70`），不在规则文件中硬编码。
* 轻量规则集（中小项目，编码 4 文件加载量约 1,194 行）见 `front-rules/rules-vue-lite/`，入口为 `Vue-lite.md`。

## 校验原则

* 修改文件后，优先做语法检查。
* 如果项目已有 lint / test / build 命令，优先执行与当前改动最相关、最小范围的校验。
* 校验失败时，要区分代码问题、环境问题、工具缺失还是历史遗留问题。
* 非必要不跑全量 build。
* 如涉及路由、状态管理、公共组件、权限逻辑，优先检查最直接影响路径是否正常。

## 文件编辑方式

* 创建或修改 JSON、JS 对象、TS 对象内容时，优先直接编辑文件。
* 尽量不要使用 bash 的 echo/printf 内联大段 JSON 或对象字面量写文件。
* 避免执行带大量引号和花括号的单行 shell 命令，减少权限与安全拦截。

## 最终回复格式

* 说明改了哪些文件
* 说明核心改动点
* 说明是否执行了校验
* 说明风险点或后续建议
