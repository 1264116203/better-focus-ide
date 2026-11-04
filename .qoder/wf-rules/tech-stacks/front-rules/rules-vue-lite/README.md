# rules-vue-lite 目录说明

## 与 rules-vue 的关系

rules-vue-lite 是 rules-vue 的精简版，合并了冗余内容，消除了重复声明。

| rules-vue (原版) | rules-vue-lite (精简版) | 变化 |
|------------------|------------------------|------|
| Vue.md (283行) | Vue-lite.md (134行) | 删除与子文件重复的编码规则（Vue.md 已瘦身为入口） |
| code-style.md (504行) + project-structure.md (634行) | frontend/dev-spec.md (367行) | 合并编码+目录结构，消除重叠 |
| antd.md (493行) + element-plus.md (503行) | frontend/ui-components.md (308行) | 合并两库规范，差异点条件标注 |
| 原工作流三文件（变更安全/命令策略/测试规范） | frontend/workflow-spec.md (197行) | 合并工作流规范 |
| sonarqube.md (392行) | **已移除** | SonarQube是CI/CD工具规范，不属于前端编码规范 |
| phase4-6-frontend-dependencies.md (196行) | 保留于 rules-vue/frontend/（130行） | 去 cojoy 化，改由验证类技能按需读取 |
| **10文件 ~3,914行** | **5文件 ~1,194行** | implementer加载量降76% |

## wf-dev 技能加载规则

### 编码类技能（ss-tdd-cycle，按「规则依赖」读取 tech-stacks 时）
只需Read 4个文件：
1. 项目规则（如有，最高优先）
2. `Vue-lite.md` — 入口（技术栈+目录树+全局原则）
3. `frontend/dev-spec.md` — 编码+目录结构规范
4. `frontend/ui-components.md` — UI组件使用规范
5. `frontend/workflow-spec.md` — 变更安全+命令策略+校验规范

### 验证类技能（ss-tdd-cycle / ss-test-run / ss-test-integration）
额外Read：
- `../rules-vue/frontend/phase4-6-frontend-dependencies.md` — 验证依赖安装指引
- `../rules-vue/frontend/test-profile-templates.md` — test_env 配置模板

## 移除SonarQube的原因

SonarQube 规范（392行）是 CI/CD 质量门禁工具的使用规范，不属于前端编码规范范畴：
- 它描述的是如何配置/使用 SonarQube 服务端、Quality Gate、Quality Profile、PR分析等 CI/CD 流程
- 实际编码规则（复杂度治理、重复代码、覆盖率）已在 dev-spec.md 的组件拆分/250行限制/ESLint配置中覆盖
- ESLint 已承担基础语法和风格检查职责，SonarQube 作为补充层不影响日常编码决策
- 项目当前未接入 SonarQube，392行内容对实现agent无实际指导价值

如未来接入 SonarQube，可在验证类技能中单独引入 SonarQube 规范文件。

## 精简要点

1. 全局原则只在入口声明一次，子文件不重复
2. antd+element-plus合并，通用规则只写一次，差异点用 [Ant]/[EL] 标注
3. code-style+project-structure合并，消除目录职责重复声明
4. 原工作流三文件合并为工作流规范
5. SonarQube移除（CI/CD工具规范，编码规则已在dev-spec覆盖）
6. 依赖手册保留在 rules-vue/frontend/，由验证类技能按需读取
7. 最终说明要求只在入口声明一次