# 前端代码风格规范（React）

## 重要原则
- 严格遵循项目现有技术栈、目录结构、命名规范。
- 优先最小可行改动，不做无关重构。
- 先理解上下文，再改代码。
- 不要为了“更优雅”修改已有稳定逻辑。
- 不要顺手修与当前任务无关的问题。
- 修改公共组件时，必须检查受影响调用方。

---

## 技术栈约定
- 基于 React 项目开发。
- 优先遵循项目现有版本与已有封装，不擅自替换核心依赖。
- 涉及路由、状态管理、UI 组件、请求封装时，优先复用项目已有方案。

---

## 目录职责约定
- `components/`：全局通用组件，复用次数 >= 3 次才可进入此目录。
- `pages/`：页面级目录，按模块划分。
- `layouts/`：系统布局组件。
- `router/`：路由配置、权限守卫、菜单配置。
- `utils/`：全局工具函数，不放业务配置。
- `services/`：跨页面复用的公共接口请求。
- `hooks/`：全局通用 hooks。
- `mock/`：本地静态 mock 数据。
- 页面私有逻辑、私有组件、私有 service、私有 hooks 必须优先放在当前页面目录内。

---

## 命名规范

### 组件命名
- React 组件统一使用 PascalCase。
- 文件名与组件名保持一致。
- 每个组件文件只允许有一个默认导出组件。
- 不允许在一个文件中定义多个大型业务组件。

正确示例：
- `UserTable.jsx`
- `OrderDetailModal.jsx`
- `LayoutBasic/index.jsx`

错误示例：
- `userTable.jsx`
- `index.jsx` 内同时声明多个页面级组件
- `testComponent.jsx`

### 变量命名
- 普通变量使用 camelCase。
- 常量使用 `UPPER_SNAKE_CASE`。
- 布尔值变量命名必须具备明确语义，推荐：
    - `isVisible`
    - `hasPermission`

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

### hooks 命名
- hooks 必须以 `use` 开头。
- hooks 名称必须表达用途，禁止无语义名称。

正确示例：
- `useTableState`
- `usePermission`
- `usePageQuery`

错误示例：
- `useCommon`
- `useLogic`
- `useMethods`

---

## 文件规范
- `.jsx`、`.tsx` 文件不允许超过 250 行。
- 每行代码不允许超过 120 个字符。
- `config.jsx` 文件为配置文件，不允许带有函数。
- `utils.js` 文件为工具函数文件，不允许带有配置类和常量数据。
- 一个文件只承担一个主要职责，避免“大而全”。

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
- 弹窗区拆分为：`ModalEdit` / `ModalDetail`
- 统计区拆分为：`PanelStatistic`
- 详情区拆分为：`PanelDetail`

### 拆分原则
- 当前页面内使用的组件放在当前页面的 `components/` 目录。
- 复用次数 >= 3 次的组件，上移到 `src/components/`。
- 纯展示组件尽量无状态化，优先使用 `props` 驱动。
- 不要为了拆分而拆分，避免出现大量空壳组件。

---

## JSX 编写规范
- JSX 中避免写复杂业务逻辑。
- 条件判断尽量在渲染前处理，不要在 JSX 中嵌套大量三元表达式。
- 列表渲染必须使用稳定 `key`，禁止使用随机值。
- 不要在 JSX 中直接调用高频复杂函数。
- JSX 中的 className、事件、属性命名要清晰，不写无语义缩写。

不推荐：
```jsx
{list?.length ? list.map((item, index) => <Row key={Math.random()}>{item.name}</Row>) : null}
```

## 状态管理规范

* 页面私有状态优先使用 useReducer / useState / 页面私有 hooks。
* 跨页面共享状态优先使用项目现有全局状态方案。
* 不要把页面临时状态提升为全局状态。
* 不要在多个组件中维护同一份来源不一致的数据。

页面临时状态示例：

* 弹窗开关
* 当前 hover 状态
* 本页筛选条件
* 局部 loading

这些状态优先留在页面内部，不要进入全局状态。

---

## 副作用与生命周期规范

* useEffect 只处理副作用，不要塞入过多混杂逻辑。
* useEffect 依赖项必须完整明确，避免隐式依赖。
* 请求、订阅、事件监听、定时器等副作用必须在适当时机清理。
* 不要通过刻意省略依赖项来“修复”重复执行问题。
* 遇到依赖复杂的问题，优先拆分 effect 或抽离 hooks。

---

## 事件处理规范

* 事件方法统一使用 handleXxx 命名。
* 不要在 JSX 中内联大段事件逻辑。
* 涉及多步逻辑时，将处理函数抽离到组件主体中。
* 表单提交、查询、重置、分页、排序等事件命名保持统一。

---

## 路由与权限规范

* 路由统一在 router/ 目录维护。
* 页面标题、菜单信息、权限标识统一使用路由配置或统一配置管理。
* 不要在页面组件中硬编码菜单名称、权限字段、布局类型。
* 权限判断优先复用已有权限工具函数或路由守卫。

---

## 接口请求规范

* 不允许在页面组件中直接散写 axios 请求。
* 所有请求统一走项目已有 http.js / request.js 封装。
* 页面私有接口放当前页面 service.js。
* 公共接口放 src/services/。
* 组件只消费干净稳定的数据，不直接处理混乱接口结构。

---

## 样式规范

* 样式优先复用项目已有变量、主题配置、公共样式。
* 页面样式放页面目录下 style.less。
* 通用组件样式放当前组件目录下 style.less。
* 不允许大量内联 style。
* 不要无约束覆盖全局样式。
* 修改公共样式时必须评估影响范围。

---

## import 规范

* 优先按以下顺序组织 import：
    1. React 库
    2. Antd 与第三方库
    3. 项目公共能力
    4. 公共组件 / hooks / utils / services
    5. 当前模块私有组件 / 配置 / 工具
    6. 样式 / less
    7. 空行
    8. 当前文件头部注释
* 跨层级引用优先使用别名：
    * @ -> src
    * \# -> public
* 避免出现过长相对路径：
    * ../../../../utils

## 文件头部注释
```javascript
/**
 * @Author: 
 * @Description:
 * @Date: Created in YYYY/MM/DD HH:mm
 */
```

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

### React 专属规则

| 规则 | ESLint 配置 | 说明 |
|------|-------------|------|
| Hooks 规则 | `react-hooks/rules-of-hooks`（error） | 必须遵守 Hooks 调用规则 |
| Hooks 依赖完整性 | `react-hooks/exhaustive-deps`（warn） | useEffect 依赖项必须完整 |
| 组件 displayName | `react/display-name`（warn） | 组件命名必须明确 |

### 配置模板

```js
// eslint.config.js
import js from '@eslint/js';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';

export default [
  js.configs.recommended,
  reactPlugin.configs.flat.recommended,
  reactPlugin.configs.flat['jsx-runtime'],
  {
    plugins: { 'react-hooks': reactHooksPlugin },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
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

* 不要修改无关文件。
* 不要大范围重命名。
* 不要擅自引入新技术栈。
* 不要擅自安装依赖。
* 不要直接连接公网执行安装或更新操作。
* 不要仅为了“代码好看”重构稳定模块。
* 不要把配置、工具函数、视图逻辑混写在同一文件中。

---

## 变更前检查

修改前优先确认：

* 路由入口在哪里
* 页面状态来源是什么
* 当前组件是否为公共组件
* 是否已有同类封装可复用
* 权限逻辑是否依赖路由或全局状态
* 当前改动是否会影响其它页面

---

## 变更后要求

* 保持现有行为兼容。
* 最小范围验证语法与核心链路。
* 最终说明：
    * 改了哪些文件
    * 核心改动点
    * 是否执行了校验
    * 风险点或后续建议


