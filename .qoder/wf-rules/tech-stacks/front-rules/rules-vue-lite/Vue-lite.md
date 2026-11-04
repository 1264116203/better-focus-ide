# 项目协作规范（Vue版）— 精简版

> ⚠️ 不要修改此文件。{} 内为占位符，按实际业务命名。
> ⚠️ 不要执行 NPM 安装依赖和联网操作，只提示开发者。

---

## 全局原则（唯一声明处，子文件不再重复）

1. **最小可行改动** — 不做无关重构，不为"更优雅"改稳定逻辑
2. **先理解后修改** — 先看调用链、状态来源、路由入口、权限逻辑
3. **优先复用** — 先复用现有组件/工具/样式/约定，再新增
4. **职责单一** — config只放配置，utils只放函数，service只放请求
5. **局部收敛** — 页面私有逻辑内聚，不擅自上移为全局能力
6. **保持兼容** — 修改公共模块时检查所有调用方

---

## 语言

- 默认中文交流、解释、总结和变更说明
- 代码命名、文件名、类型名、组件名保持英文规范

---

## 技术栈

- vite@8 / vue@3 / vue-router@4 / pinia@3
- ant-design-vue@4 / element-plus@2
- @ant-design/icons-vue / axios@1.15.0
- less / dayjs / ali-oss

---

## 项目目录结构

```text
项目根目录/
├── .qoder/                    # AI 规则（只放规则文档，不放业务代码）
│   └── wf-rules/tech-stacks/front-rules/rules-vue-lite/
│       ├── Vue-lite.md         # 入口（技术栈+目录树+全局原则）
│       └── frontend/           # 编码规范（dev-spec / ui-components / workflow-spec）
│
├── env/                        # 环境变量（按环境拆分，不放业务常量）
│   ├── .env
│   ├── .env.development
│   ├── .env.test
│   └── .env.production
│
├── public/                     # 静态资源（favicon/icons/fonts/images）
│
├── src/
│   ├── components/             # 全局通用组件（复用 ≥ 3 次，PascalCase目录）
│   │   └── CommonTable/
│   │       ├── index.vue
│   │       ├── config.js
│   │       ├── style.less
│   │       ├── hooks.js（可选）
│   │       └── utils.js（可选）
│   │
│   ├── layouts/                # 系统布局（LayoutBasic/LayoutBlank）
│   │   └── LayoutBasic/
│   │       ├── index.vue
│   │       ├── style.less
│   │       └── components/
│   │
│   ├── pages/                  # 页面（按模块划分，每页面独立目录）
│   │   └── {ModuleName}/
│   │       └── {PageName}/
│   │           ├── index.vue     # 页面编排+状态组织+事件分发
│   │           ├── config.js     # 页面私有配置（columns/options/enum）
│   │           ├── style.less    # 页面私有样式
│   │           ├── hooks.js      # 页面私有composables（可选）
│   │           ├── store.js      # 页面私有store（可选）
│   │           ├── service.js    # 页面私有接口请求
│   │           ├── utils.js      # 页面私有工具函数（可选）
│   │           └── components/   # 页面私有组件
│   │
│   ├── router/
│   │   ├── index.js             # 路由配置/守卫/权限
│   │   └── routes.js            # 路由表+菜单配置
│   │
│   ├── store/                  # 全局 Pinia（index.js + modules/）
│   │   ├── index.js
│   │   └── modules/
│   │
│   ├── composables/            # 全局通用composables（useXxx风格）
│   ├── services/               # 跨页面共用公共API
│   ├── utils/                  # 全局工具函数
│   │   ├── request.js           # get/post/put/delete/upload/download
│   │   ├── storage.js           # localStorage/sessionStorage封装
│   │   ├── http.js              # axios实例
│   │   ├── auth.js              # token/权限工具
│   │   └── oss.js               # OSS工具（可选）
│   │
│   ├── mock/                   # 本地mock数据（可选）
│   ├── App.vue                 # 应用根组件
│   ├── main.js                 # 应用入口
│   ├── theme.js                # UI库主题配置
│   └── global.less             # 全局自定义样式
│
├── eslint.config.js            # ESLint Flat Config
├── index.html                  # Vite入口
├── .gitignore
├── package.json
├── vite.config.js
└── README.md
```

---

## 规范优先级

**项目规则（用户自带 .qoder/rules/）> wf 技能规则（.qoder/wf-rules/）> 技能默认行为**

> 本文件是**精简版**（编码类技能加载量约 1,194 行），适合中小项目。需要全量规范（含 antd / element-plus 完整 UI 库规范、SonarQube 门禁、完整测试模板）时，改用全量入口 `../Vue.md`（front-rules/rules-vue/）。验证类文件（依赖安装/测试模板）两版共用 `../rules-vue/frontend/` 下的同名文件。

wf-dev 加载顺序（由技能按 SKILL.md「规则依赖」按需读取）：
1. 项目规则（如有，最高优先）
2. `frontend/dev-spec.md` — 编码+目录结构规范
3. `frontend/ui-components.md` — UI组件使用规范
4. `frontend/workflow-spec.md` — 变更安全+命令策略+校验规范

以下文件由验证类技能（ss-tdd-cycle / ss-test-run / ss-test-integration）额外按需读取，编码类技能不加载：
- `../rules-vue/frontend/phase4-6-frontend-dependencies.md` — 验证依赖安装指引
- `../rules-vue/frontend/test-profile-templates.md` — test_env 配置模板

---

## 最终回复格式

- 说明改了哪些文件
- 说明核心改动点
- 说明是否执行了校验（及范围）
- 说明风险点或后续建议