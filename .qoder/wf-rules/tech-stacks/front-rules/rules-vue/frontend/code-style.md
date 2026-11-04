# 前端代码风格规范（Vue 3）

## 重要原则
- 严格遵循项目现有技术栈、目录结构、命名规范。
- 优先最小可行改动，不做无关重构。
- 先理解上下文，再改代码。
- 不要为了“更优雅”修改已有稳定逻辑。
- 不要顺手修与当前任务无关的问题。
- 修改公共组件时，必须检查受影响调用方。

---

## 技术栈约定
- 基于 Vue 3 项目开发。
- 优先遵循项目现有版本与已有封装，不擅自替换核心依赖。
- 涉及路由、状态管理、UI 组件、请求封装时，优先复用项目已有方案。
- 默认以 `Composition API` 为主，除非项目已有统一例外约定。
- 默认优先使用 `script setup`，除非项目已有统一例外约定。

---

## 目录职责约定
- `components/`：全局通用组件，复用次数 >= 3 次才可进入此目录。
- `views/`：页面级目录，按模块划分。
- `layouts/`：系统布局组件。
- `router/`：路由配置、权限守卫、菜单配置。
- `utils/`：全局工具函数，不放业务配置。
- `services/`：跨页面复用的公共接口请求。
- `stores/`：全局状态管理。
- `composables/`：全局通用组合式逻辑。
- `mock/`：本地静态 mock 数据。
- 页面私有逻辑、私有组件、私有 service、私有 composables 必须优先放在当前页面目录内。

---

## 命名规范

### 组件命名
- Vue 组件统一使用 PascalCase。
- 文件名与组件名保持一致。
- 一个 `.vue` 文件只承载一个主要组件。
- 不允许在一个文件中定义多个大型业务组件。

正确示例：
- `UserTable.vue`
- `OrderDetailDialog.vue`
- `LayoutBasic/index.vue`

错误示例：
- `userTable.vue`
- `index.vue` 内同时承载多个页面级组件
- `testComponent.vue`

### 变量命名
- 普通变量使用 camelCase。
- 常量使用 `UPPER_SNAKE_CASE`。
- 布尔值变量命名必须具备明确语义，推荐：
  - `isVisible`
  - `isLoading`
  - `hasPermission`
  - `canEdit`

避免：
- `flag`
- `status`（语义不清时）
- `data1`
- `temp`

### 方法命名
- 方法名使用动词开头，表达行为。
- 事件处理函数统一使用：
  - `handleXxx`
- 数据获取类函数统一使用：
  - `fetchXxx`
  - `loadXxx`
- 创建、更新、删除动作统一使用：
  - `createXxx`
  - `updateXxx`
  - `removeXxx`
- 设置类函数统一使用：
  - `setXxx`

正确示例：
- `handleSearch`
- `handleReset`
- `fetchUserList`
- `updateUserStatus`

### composables 命名
- composables 必须以 `use` 开头。
- composables 名称必须表达用途，禁止无语义名称。

正确示例：
- `useTableState`
- `usePermission`
- `usePageQuery`

错误示例：
- `useCommon`
- `useLogic`
- `useMethods`

### store 命名
- store 名称必须表达业务领域或职责。
- store 文件命名建议使用：
  - `useUserStore.ts`
  - `usePermissionStore.ts`
  - `useAppStore.ts`
- 不要出现无语义 store 命名，例如：
  - `useDataStore`
  - `useCommonStore`

---

## 文件规范
- `.vue`、`.js`、`.ts` 文件不允许超过 250 行。
- 每行代码不允许超过 120 个字符。
- `config.ts` / `config.js` 文件为配置文件，不允许带有复杂业务函数。
- `utils.ts` / `utils.js` 文件为工具函数文件，不允许带有配置类和常量数据。
- 一个文件只承担一个主要职责，避免“大而全”。
- 单文件组件内应保持结构清晰：
  - `template`
  - `script setup`
  - `style`
- 不要在一个 `.vue` 文件中混入过多与当前组件无关的辅助逻辑。

---

## 组件拆分规则
- 页面主文件只负责页面编排、状态组织、事件分发，不承载全部业务细节。
- 页面文件超过 250 行时，必须评估是否拆分。
- 单个组件若同时承担以下 2 项及以上职责，应优先拆分：
  - 数据获取
  - 列表渲染
  - 筛选查询
  - 表单编辑
  - 弹窗交互
  - 复杂表格配置
  - 权限展示控制

### 推荐拆分方式
- 查询区拆分为：`PanelFilter`
- 表格区拆分为：`PanelTable`
- 弹窗区拆分为：`DialogEdit` / `DialogDetail`
- 抽屉区拆分为：`DrawerEdit` / `DrawerDetail`
- 统计区拆分为：`PanelStatistic`
- 详情区拆分为：`PanelDetail`

### 拆分原则
- 当前页面内使用的组件放在当前页面的 `components/` 目录。
- 复用次数 >= 3 次的组件，上移到 `src/components/`。
- 纯展示组件尽量无状态化，优先使用 `props` 驱动。
- 不要为了拆分而拆分，避免出现大量空壳组件。
- composables 负责复用逻辑，组件负责视图表达，不要职责混乱。

---

## 模板编写规范
- 模板中避免写复杂业务逻辑。
- 条件判断尽量在渲染前处理，不要在模板中嵌套大量三元表达式。
- 列表渲染必须使用稳定 `key`，禁止使用随机值。
- 不要在模板中直接调用高频复杂函数。
- 模板中的 class、事件、属性命名要清晰，不写无语义缩写。

不推荐：
```vue
<template>
  <div v-if="list?.length">
    <div v-for="item in list" :key="Math.random()">
      {{ formatItem(item, someVeryComplexCondition) }}
    </div>
  </div>
</template>
```

推荐：
```vue
<template>
  <div v-if="hasList">
    <div v-for="item in displayList" :key="item.id">
      {{ item.name }}
    </div>
  </div>
</template>
```

### 插槽使用规范
- 插槽命名必须语义清晰。
- 不要为了“灵活”把组件设计成过度依赖大量不受控插槽。
- 具名插槽数量过多时，应评估组件职责是否已经过重。
- 表格列插槽、表单项插槽、头部操作区插槽应有统一命名习惯。

---

## 响应式状态管理规范
- 页面私有状态优先使用：
  - `ref`
  - `reactive`
  - 页面私有 composables
- 跨页面共享状态优先使用项目现有全局状态方案，例如 Pinia。
- 不要把页面临时状态提升为全局状态。
- 不要在多个组件中维护同一份来源不一致的数据。

页面临时状态示例：
- 弹窗开关
- 当前 hover 状态
- 本页筛选条件
- 局部 loading
- 当前 tab
- 当前行选中状态

这些状态优先留在页面内部，不要进入全局状态。

### ref / reactive 使用约定
- 基础类型优先使用 `ref`
- 结构化对象优先根据场景评估 `ref` 或 `reactive`
- 不要为了少写 `.value` 无脑使用 `reactive`
- 不要把超大对象整体做深层响应式而缺乏边界控制

---

## 副作用与生命周期规范
- `onMounted`、`onUnmounted`、`watch`、`watchEffect` 只处理明确职责的副作用。
- 请求、订阅、事件监听、定时器等副作用必须在适当时机清理。
- 不要通过堆叠多个混乱 `watch` 来拼业务逻辑。
- 遇到依赖复杂的问题，优先拆分监听逻辑或抽离 composables。
- 不要用 `watchEffect` 代替所有显式依赖管理。

### watch 使用要求
- `watch` 必须明确监听来源和处理意图。
- 不要监听整个大对象后在回调中处理大量无关逻辑。
- 能通过 `computed` 解决的派生状态，不要滥用 `watch`。
- 不要为了“立即生效”在多个地方重复触发同一初始化逻辑。

---

## 事件处理规范
- 事件方法统一使用 `handleXxx` 命名。
- 不要在模板中内联大段事件逻辑。
- 涉及多步逻辑时，将处理函数抽离到 `script setup` 中。
- 表单提交、查询、重置、分页、排序等事件命名保持统一。

不推荐：
```vue
<template>
  <el-button @click="() => { form.page = 1; form.keyword = ''; loadList(); resetOtherState(); }">
    重置
  </el-button>
</template>
```

推荐：
```vue
<template>
  <el-button @click="handleReset">重置</el-button>
</template>
```

---

## 路由与权限规范
- 路由统一在 `router/` 目录维护。
- 页面标题、菜单信息、权限标识统一使用路由配置或统一配置管理。
- 不要在页面组件中硬编码菜单名称、权限字段、布局类型。
- 权限判断优先复用已有权限工具函数、权限指令或路由守卫。
- 路由相关展示逻辑优先依赖 `route.meta`，不要在页面内散写一套映射关系。

### 推荐约定
- `meta.title`：页面标题
- `meta.icon`：菜单图标
- `meta.hidden`：是否隐藏菜单
- `meta.activeMenu`：详情页高亮父菜单
- `meta.permission`：权限标识
- `meta.keepAlive`：缓存控制

---

## 接口请求规范
- 不允许在页面组件中直接散写原始请求调用。
- 所有请求统一走项目已有 `request.ts` / `http.ts` 封装。
- 页面私有接口放当前页面 `service.ts`。
- 公共接口放 `src/services/`。
- 组件只消费干净稳定的数据，不直接处理混乱接口结构。
- 接口返回值必须经过统一转换或兜底处理，不要把后端原始结构直接散落到模板中。

### 数据处理要求
- 请求参数构造与视图展示逻辑分离。
- 列表数据、分页数据、详情数据、表单回显数据要分层处理。
- 不要在模板中直接写接口字段兼容逻辑。
- 不要在多个页面重复写相同的数据转换代码。

---

## 样式规范
- 样式优先复用项目已有变量、主题配置、公共样式。
- 页面样式放页面目录下 `style.scss / style.less`。
- 通用组件样式放当前组件目录下 `style.scss / style.less`。
- 不允许大量内联 `style`。
- 不要无约束覆盖全局样式。
- 修改公共样式时必须评估影响范围。

### Vue 样式约定
- 页面局部样式优先使用 `scoped`。
- 覆盖第三方组件内部样式时，必须谨慎使用 `:deep()`。
- 不允许在页面内大量使用无边界的全局样式覆盖。
- 不要将主题变量、组件修正样式、页面业务样式混在同一处随意维护。

---

## import 规范
- 优先按以下顺序组织 import：
  1. Vue 核心能力
  2. Vue Router / Pinia / 第三方库
  3. 项目公共能力
  4. 公共组件 / composables / utils / services
  5. 当前模块私有组件 / 配置 / 工具
  6. 样式文件
  7. 空行
  8. 当前文件头部注释

- 跨层级引用优先使用别名：
  - `@` -> `src`
  - `#` -> `public`

- 避免出现过长相对路径：
  - `../../../../utils`

---

## 文件头部注释
```javascript
/**
 * @Author:
 * @Description:
 * @Date: Created in YYYY/MM/DD HH:mm
 */
```

---

## props / emits 规范
- `props` 必须声明清晰，不要无约束透传。
- `props` 命名必须具备语义，不要使用模糊字段名。
- 组件对外事件必须通过 `emits` 明确声明。
- 不要把组件内部实现细节暴露成一堆难以理解的 props。
- 不要把多个无关行为强行塞进一个组件对外协议。

### 推荐要求
- `props` 表达输入
- `emits` 表达输出
- `slots` 表达可扩展视图
- `expose` 只暴露必要能力

---

## defineExpose 规范
- `defineExpose` 仅在确有必要时使用。
- 暴露的方法必须是外部组件真正需要调用的能力。
- 不要把组件内部所有方法都暴露出去。
- 子组件优先通过 `props + emits` 与父组件通信，`defineExpose` 作为补充，不作为默认手段。

---

## computed 规范
- 派生状态优先使用 `computed`，不要把本可推导的数据再次存储一份。
- `computed` 名称必须体现语义。
- 不要在 `computed` 中混入副作用。
- 不要把复杂流程控制全部堆在一个超长 `computed` 中。

正确示例：
- `tableColumns`
- `displayList`
- `isSubmitDisabled`

错误示例：
- `data`
- `result`
- `tempValue`

---

## Pinia 使用规范
- 全局共享状态进入 Pinia，页面临时状态不要进入 Pinia。
- store 中只维护真正需要跨组件、跨页面共享的数据。
- actions 命名必须清晰表达行为。
- getters 只处理派生逻辑，不承担副作用。
- 不要把接口请求、组件 UI 状态、路由临时参数全部堆进一个 store。

### 推荐 store 划分
- `useUserStore`
- `usePermissionStore`
- `useAppStore`
- `useDictStore`

### 不推荐
- 一个巨型 `useGlobalStore` 承载所有状态
- 把弹窗开关、hover 状态、当前页 tab 这种临时状态塞进全局 store

---

## ESLint 配置规范

### 配置文件
- 使用 `eslint.config.js`（ESLint Flat Config，ESLint 9+ 新格式），放置在项目根目录。
- 禁止使用旧格式 `.eslintrc.js` / `.eslintrc.json` / `.eslintrc.yml`。

### 必须启用的规则（对齐前端开发规范）

| 规则 | ESLint 配置 | 说明 |
|------|-------------|------|
| 禁止魔术数字/字符串 | `no-magic-numbers`（warn） + `no-magic-strings`（自定义 warn） | 提取为常量 |
| 禁止空 catch | `no-empty`（error） | catch 块必须至少 console.error |
| 变量驼峰命名 | `camelcase`（error） | 禁止混用驼峰与下划线 |
| 行长度限制 | `max-len`（warn, 120） | 对齐 250 行 / 120 字符规范 |
| 禁止未使用变量 | `no-unused-vars`（warn） | 见名知意，避免冗余 |
| 禁止 console 生产环境 | `no-console`（生产 warn，开发 off） | 生产环境禁止残留 console.log |

### Vue 专属规则

| 规则 | ESLint 配置 | 说明 |
|------|-------------|------|
| 禁止 v-html 渲染用户输入 | `vue/no-v-html`（warn，需人工判断是否为用户输入） | 防止 XSS |
| script setup 优先 | `vue/component-api-style`（warn, 'script-setup'） | 对齐 Composition API 约定 |
| 组件命名 PascalCase | `vue/component-name-casing`（error, 'PascalCase'） | 对齐命名规范 |
| props 类型声明 | `vue/require-prop-types`（warn） | props 必须声明类型 |

### 配置模板

```js
// eslint.config.js
import js from '@eslint/js';
import vuePlugin from 'eslint-plugin-vue';

export default [
  js.configs.recommended,
  ...vuePlugin.configs['flat/recommended'],
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
];
```

### 要求
- ESLint 配置必须与前端开发规范对齐，不能出现规范禁止但 ESLint 允许的情况。
- 修改代码后应执行 `npx eslint src/` 校验，校验失败需修复。
- 禁止安装未经允许的 ESLint 插件依赖。

---

## 禁止事项
- 不要修改无关文件。
- 不要大范围重命名。
- 不要擅自引入新技术栈。
- 不要擅自安装依赖。
- 不要直接连接公网执行安装或更新操作。
- 不要仅为了“代码好看”重构稳定模块。
- 不要把配置、工具函数、视图逻辑混写在同一文件中。
- 不要在模板中堆积过多业务逻辑。
- 不要在多个页面重复实现同一套私有规则却不抽象。
- 不要绕过项目已有组件封装与主题规范。

---

## 变更前检查
修改前优先确认：
- 路由入口在哪里
- 页面状态来源是什么
- 当前组件是否为公共组件
- 是否已有同类封装可复用
- 权限逻辑是否依赖路由或全局状态
- 当前改动是否会影响其它页面
- 当前页面是否已有 composables / service / store 可直接复用
- 当前样式修改是否会污染其它组件

---

## 变更后要求
- 保持现有行为兼容。
- 最小范围验证语法与核心链路。
- 最终说明：
  - 改了哪些文件
  - 核心改动点
  - 是否执行了校验
  - 风险点或后续建议

---

## 一句话原则
- 先理解，再修改
- 先复用，再新增
- 先局部收敛，再考虑抽象
- 不为局部需求破坏全局一致性
