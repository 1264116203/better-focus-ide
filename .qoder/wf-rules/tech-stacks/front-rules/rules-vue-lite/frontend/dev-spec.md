# Vue 3 开发规范（编码风格 + 目录结构）

> 全局原则见入口 Vue-lite.md，此文件不重复。

---

## 一、目录职责约定

| 目录 | 职责 | 放入条件 |
|------|------|----------|
| `components/` | 全局通用组件 | 复用 ≥ 3 次或明确项目级能力 |
| `layouts/` | 系统布局组件 | 系统级页面结构，不承载业务逻辑 |
| `pages/` | 页面级业务代码 | 按模块划分，每页面独立目录 |
| `router/` | 路由+守卫+菜单配置 | 路由统一维护，禁止页面散落 |
| `store/` | 全局 Pinia store | 仅跨页面共享状态 |
| `composables/` | 全局通用composables | 多页面复用，不绑定单一业务 |
| `services/` | 跨页面公共API | 共用接口，非页面私有接口 |
| `utils/` | 全局工具函数 | 只放函数，不放配置和常量 |
| `mock/` | 本地mock数据 | 仅开发辅助，按组件命名 |

**页面私有内容优先放在页面目录内**，不要擅自上移到全局。

**新增文件落位判断流程：**
1. 先判断是否页面私有 → 放 `pages/.../{PageName}/` 内
2. 再判断是否模块通用 → 先在模块内组织
3. 最后判断是否全局通用 → 放 `src/components/` 等全局目录

---

## 二、页面目录标准结构

每个页面目录只承载当前页面内容：

```text
{PageName}/
├── index.vue       # 页面编排+数据流+事件分发
├── config.js       # columns/formItems/options/enum/常量（无函数）
├── style.less      # 页面私有样式（scoped收口）
├── hooks.js        # 页面私有composables（可选）
├── store.js        # 页面私有store（仅复杂时，可选）
├── service.js      # 页面私有接口请求
├── utils.js        # 页面私有工具函数（可选）
└── components/     # 页面私有组件
```

### 各文件职责边界

| 文件 | 只放 | 禁放 |
|------|------|------|
| `index.vue` | 编排、状态组织、事件分发 | 大段配置、全部子组件实现、复杂请求逻辑 |
| `config.js` | 静态配置数据（columns/options/enum） | 接口请求、副作用、业务函数 |
| `service.js` | 页面私有接口方法 | 跨页面共用接口、axios实例、拦截器 |
| `hooks.js` | 页面私有composables逻辑 | 全局通用composables、配置数据、常量 |
| `utils.js` | 页面私有格式化/转换函数 | 配置项、枚举常量、公共通用函数 |
| `style.less` | 页面私有样式 | 全局覆盖、第三方组件全局污染 |

---

## 三、命名规范

### 组件命名
- Vue 组件统一 PascalCase，文件名与组件名一致
- 一个 `.vue` 文件只承载一个主要组件
- 正确：`UserTable.vue`、`LayoutBasic/index.vue`
- 错误：`userTable.vue`、`index.vue`内多组件

### 变量命名
- 普通变量 camelCase，常量 `UPPER_SNAKE_CASE`
- 布尔值语义明确：`isVisible`/`isLoading`/`hasPermission`/`canEdit`
- 避免：`flag`/`status`(语义不清)/`data1`/`temp`

### 方法命名
- 事件处理：`handleXxx`
- 数据获取：`fetchXxx`/`loadXxx`
- 创建/更新/删除：`createXxx`/`updateXxx`/`removeXxx`
- 设置：`setXxx`

### composables命名
- 必须 `use` 开头且表达用途
- 正确：`useTableState`/`usePermission`/`usePageQuery`
- 错误：`useCommon`/`useLogic`/`useMethods`

### store命名
- 文件命名：`useUserStore.ts`/`usePermissionStore.ts`/`useAppStore.ts`
- 避免：`useDataStore`/`useCommonStore`

---

## 四、文件规范

- `.vue`/`.js`/`.ts` 文件不超过 **250 行**
- 每行不超过 **120 个字符**
- `config.js` 不允许带复杂业务函数
- `utils.js` 不允许带配置类和常量数据
- 单文件组件结构：`template` → `script setup` → `style`

### 文件头部注释
```javascript
/**
 * @Author:
 * @Description:
 * @Date: Created in YYYY/MM/DD HH:mm
 */
```

---

## 五、组件拆分规则

- 页面主文件只负责编排、状态、事件分发
- 超过250行必须评估拆分
- 同时承担2项以上职责时应拆分：数据获取/列表渲染/筛选查询/表单编辑/弹窗交互/复杂表格/权限控制

### 推荐拆分方式
| 职责 | 组件名 |
|------|--------|
| 查询区 | `PanelFilter` |
| 表格区 | `PanelTable` |
| 弹窗区 | `DialogEdit`/`DialogDetail` |
| 抽屉区 | `DrawerEdit`/`DrawerDetail` |
| 统计区 | `PanelStatistic` |
| 详情区 | `PanelDetail` |

### 拆分原则
- 页面内组件放 `components/`，复用 ≥ 3 次再上移到 `src/components/`
- 纯展示组件无状态化，优先 `props` 驱动
- composables负责逻辑，组件负责视图，不要职责混乱

### 组件提升规则
- 页面组件 → 模块组件：被模块内多页面复用时
- 模块组件 → 全局组件：跨模块复用 ≥ 3 次 + props稳定
- 禁止：还没复用就提前通用化、"以后可能用"就放全局

---

## 六、模板编写规范

- 模板避免复杂业务逻辑，不嵌套大量三元表达式
- 列表渲染使用稳定 `key`，禁止随机值
- 不在模板中直接调用高频复杂函数
- class/事件/属性命名清晰，不写无语义缩写

不推荐：
```vue
<div v-for="item in list" :key="Math.random()">
  {{ formatItem(item, someVeryComplexCondition) }}
</div>
```

推荐：
```vue
<div v-for="item in displayList" :key="item.id">
  {{ item.name }}
</div>
```

---

## 七、响应式状态管理

### 状态归属原则
| 状态类型 | 管理方式 |
|----------|----------|
| 页面私有（弹窗开关/hover/筛选/loading/tab/行选中） | ref/reactive/composables，留在页面内 |
| 多组件共享 | composables 或 Pinia |
| 全局共享 | Pinia store/modules/ |

- 不要把页面临时状态提升为全局状态
- 不要在多个组件维护同一份来源不一致的数据

### ref/reactive使用
- 基础类型优先 `ref`
- 结构化对象按场景评估 `ref` 或 `reactive`
- 不为少写 `.value` 无脑用 `reactive`
- 不把超大对象整体做深层响应式

---

## 八、副作用与生命周期

- `onMounted`/`onUnmounted`/`watch`/`watchEffect` 只处理明确职责的副作用
- 请求、订阅、事件监听、定时器必须在适当时机清理
- 不堆叠多个 `watch` 拼业务逻辑
- 能用 `computed` 解决的不滥用 `watch`
- 不用 `watchEffect` 代替所有显式依赖管理

---

## 九、事件处理

- 统一 `handleXxx` 命名
- 不在模板中内联大段事件逻辑
- 多步逻辑抽离到 `script setup`

不推荐：
```vue
<el-button @click="() => { form.page = 1; form.keyword = ''; loadList(); }">重置</el-button>
```

推荐：
```vue
<el-button @click="handleReset">重置</el-button>
```

---

## 十、路由与权限

- 路由统一在 `router/` 维护
- 页面标题/菜单/权限统一用路由配置，禁止页面硬编码
- 权限判断复用已有工具/指令/守卫，不散写

### route.meta 标准字段
| 字段 | 用途 |
|------|------|
| `meta.title` | 页面标题 |
| `meta.icon` | 菜单图标 |
| `meta.hidden` | 是否隐藏菜单 |
| `meta.activeMenu` | 详情页高亮父菜单 |
| `meta.permission` | 权限标识 |
| `meta.keepAlive` | 缓存控制 |

---

## 十一、接口请求

- 不允许页面直接散写原始 axios 调用
- 所有请求走 `utils/http.js` + `utils/request.js` 封装
- 页面私有接口 → `service.js`
- 跨页面共用接口 → `src/services/`
- 接口返回值必须统一转换或兜底，不把后端原始结构散落到模板

---

## 十二、样式规范

- 优先复用项目已有变量/主题配置/公共样式
- 页面样式放页面目录 `style.less` 或组件内 `scoped less`
- 通用组件样式放组件目录 `style.less`
- 不大量内联 style，不无约束覆盖全局样式
- 修改公共样式时评估影响范围
- 覆盖第三方组件样式用 `:deep()` 并控制作用域
- 涉及主题色/圆角/阴影/间距优先走 `theme.js` 或全局变量

---

## 十三、import规范

顺序：
1. Vue 核心能力
2. Vue Router / Pinia / 第三方库
3. 项目公共能力
4. 公共组件 / composables / utils / services
5. 当前模块私有组件 / 配置 / 工具
6. 样式文件

别名：`@` → `src`，`#` → `public`。避免 `../../../../` 过长相对路径。

---

## 十四、props / emits / computed / defineExpose

- `props` 声明清晰，命名语义明确，不无约束透传
- `emits` 明确声明，不把内部实现细节暴露成 props
- `computed` 只做派生逻辑，不混入副作用，名称体现语义
- `defineExpose` 仅在必要时使用，只暴露外部真正需要的方法
- v-model协议：`update:modelValue` 事件名

正确computed名：`tableColumns`/`displayList`/`isSubmitDisabled`
错误computed名：`data`/`result`/`tempValue`

---

## 十五、Pinia使用

- 全局共享状态进 Pinia，页面临时状态不进 Pinia
- store按业务领域拆分：`useUserStore`/`usePermissionStore`/`useAppStore`/`useDictStore`
- 禁止：一个巨型 `useGlobalStore` 承载所有状态
- actions命名清晰表达行为，getters只做派生不做副作用
- 不把弹窗开关/hover/tab等临时状态塞进全局store

---

## 十六、ESLint配置规范

使用 `eslint.config.js`（ESLint 9+ Flat Config），禁止旧格式 `.eslintrc`。

### 必须启用的规则

| 规则 | 配置 | 说明 |
|------|------|------|
| 组件PascalCase | `vue/component-name-casing` error | 对齐命名规范 |
| script setup优先 | `vue/component-api-style` warn | Composition API约定 |
| 禁止v-html用户输入 | `vue/no-v-html` warn | XSS防护 |
| props类型声明 | `vue/require-prop-types` warn | |
| 禁止空catch | `no-empty` error | catch至少console.error |
| 行长度限制 | `max-len` warn 120 | 对齐规范 |
| 驼峰命名 | `camelcase` error | 禁止混用 |
| 禁止魔术数字 | `no-magic-numbers` warn | 提取为常量 |
| 禁止未使用变量 | `no-unused-vars` warn | argsIgnorePattern: ^_ |
| 禁止console(生产) | `no-console` warn(生产) | |

### 配置模板
```js
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import vuePlugin from 'eslint-plugin-vue';
import vueParser from 'vue-eslint-parser';

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...vuePlugin.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
  },
  {
    rules: {
      'vue/no-v-html': 'warn',
      'vue/component-api-style': ['warn', 'script-setup'],
      'vue/component-name-casing': ['error', 'PascalCase'],
      'vue/require-prop-types': 'warn',
      'no-empty': ['error', { allowEmptyCatch: false }],
      'camelcase': ['error', { properties: 'always' }],
      'max-len': ['warn', { code: 120 }],
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      'no-console': 'warn',
      'no-magic-numbers': ['warn', { ignore: [0, 1, -1] }],
    },
  },
  { ignores: ['dist/**', 'node_modules/**'] },
);
```

---

## 十七、新增页面标准要求

至少保证：
- 页面路径归属正确
- `index.vue` 只做编排
- 私有配置 → `config.js`
- 私有请求 → `service.js`
- 私有工具 → `utils.js`
- 复杂局部块 → `components/`
- 页面样式 → `style.less`

---

## 十八、明确禁止

- 禁止随意新增 common/shared/temp/test 模糊目录
- 禁止页面私有逻辑直接塞进 `src/utils/`
- 禁止公共能力散落页面目录重复实现
- 禁止配置/工具/组件/服务混放
- 禁止无依据把页面组件上移全局
- 禁止创建职责不清的"万能文件"
- 禁止在模板中堆积过多业务逻辑
- 禁止绕过项目已有封装和主题规范
- 禁止擅自引入新技术栈或安装依赖