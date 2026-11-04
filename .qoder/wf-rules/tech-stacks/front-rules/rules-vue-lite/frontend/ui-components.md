# UI 组件使用规范（Ant Design Vue @4 / Element Plus @2）

> 全局原则见入口 Vue-lite.md，此文件不重复。
> 两库通用规则只写一次，差异点用 **[Ant]** / **[EL]** 标注。

---

## 一、组件使用总原则

- 能复用项目已有封装时，不直接重复使用原生基础组件造轮子
- 表格/表单/弹窗/抽屉/上传/分页/筛选等高频能力统一风格与交互
- 公共场景优先抽象，不在多个页面复制粘贴相同配置
- 不允许因一个页面特殊需求引入第二套大型UI库
- 所有组件使用遵循项目内约定的 props/events/slots/expose

---

## 二、版本与基础约定

- 基于 vue@3 + vue-router@4 + pinia
- **[Ant]** ant-design-vue@4
- **[EL]** element-plus@2 + @element-plus/icons-vue
- 组件注册方式必须项目统一（全局注册/按需引入/自动导入），不混用多套
- 组件API以项目锁定版本为准，不照搬其它版本文档示例
- 图标统一使用项目约定方案，不混入多套风格

---

## 三、主题与样式

涉及主题色/字号/圆角/阴影/边框/间距时，优先走：
- `theme.js` + 全局样式变量 + CSS Variables + **[Ant]** less变量 / **[EL]** SCSS变量

不要在页面硬编码颜色值/阴影值/圆角值。

样式覆盖优先级：
1. 主题变量
2. 组件封装层 class
3. 页面局部 class
4. 谨慎覆盖 **[Ant]** `.ant-*` / **[EL]** `.el-*`

- 优先语义化class名
- `scoped` 用于页面局部隔离，不替代设计规范
- `:deep()` 覆盖内部结构时控制作用域，禁止无边界覆盖
- 不堆积大量patch式样式修复

---

## 四、组件命名与封装

- 基于UI库封装的组件命名体现业务语义
- 公共组件推荐：`CommonTable`/`CommonForm`/**[Ant]** `CommonModal`/**[EL]** `CommonDialog`/`CommonDrawer`/`CommonUpload`/`CommonSearchBar`/`CommonPageHeader`
- 页面私有组件放页面 `components/`，不直接上移全局
- 一个组件一个主要职责，不造巨型通用组件
- 通用组件禁止耦合具体业务字段名/接口名/路由名
- 封装时保持与原生UI库能力兼容，不把常用能力封死
- 文件名 PascalCase，`script setup` 默认推荐

---

## 五、Layout 使用

- 布局复用项目 `layouts/` 目录方案
- 固定侧边栏/固定顶部/响应式由布局层处理，不每个页面重复
- 页面只关心业务内容，不负责系统级壳层
- 系统级布局：`LayoutBasic`/`LayoutBlank`
- 页面容器统一：`PageContainer`/`CommonPage`
- 不在业务页面内拼装完整布局壳层

---

## 六、Menu 使用

- 菜单数据优先来源于路由配置或统一配置，不硬编码
- 菜单icon统一使用项目已注册图标
- 菜单选中/高亮/展开依赖路由状态
- 隐藏页/详情页高亮父菜单通过统一 `activeMenu` 机制
- 菜单渲染由 `route.meta` 驱动（title/icon/hidden/activeMenu/permission）
- 不在组件内维护伪菜单映射，不把权限/菜单/选中逻辑混写模板

---

## 七、Button 使用

- 按钮类型表达操作语义：
  - 主操作：`type="primary"`
  - 次操作：默认按钮
  - 危险操作：**[Ant]** `danger` / **[EL]** `type="danger"`

- 页面主按钮数量受控，不多个主按钮竞争视觉焦点
- 危险操作必须有确认机制
- 异步提交按钮绑定独立 loading 状态，避免重复点击
- 禁用按钮必须明确原因，必要时给出提示
- 不滥用彩色按钮/ghost/渐变等样式

---

## 八、Form 使用

- 表单优先统一使用项目内已有封装
- 新增/编辑尽量复用同一套表单结构
- 表单项命名与字段语义一致，不使用模糊字段名
- 校验规则统一管理，不散落多位置
- 表单提交前后状态完整：loading → 成功提示 → 失败提示 → 禁止重复提交

### 表单组件
- **[Ant]** `a-form` + `a-form-item`
- **[EL]** `el-form` + `el-form-item`

- 表单数据统一放响应式对象管理，不散落多个ref
- 默认值/回显值/提交参数转换明确分层

### Form.Item约定
- **[Ant]** `name` / **[EL]** `prop` 必须与字段含义一致
- `label` 使用用户可理解的业务名称
- 不在 Form.Item 中塞过多复杂逻辑
- 条件显隐复杂时抽离组件或预处理配置

### 交互要求
- 必填项明确标识
- 禁用态/只读态/编辑态行为一致
- 重置按钮恢复到初始条件
- 弹窗表单关闭时根据业务决定是否重置
- 编辑回显保证数据类型正确（Select值类型/DatePicker日期类型/Switch/Checkbox布尔语义）

### 校验规范
- 校验规则优先统一抽离到 `rules.ts` / `formRules.ts`
- 同类字段校验规则保持一致
- 后端错误信息与前端校验提示区分清楚

---

## 九、Table 使用

- 列配置优先放 `columns.ts`/`config.ts` 等独立文件
- 复杂列渲染不堆在页面主文件，抽离局部组件或独立render
- 查询/分页/排序/筛选交互统一
- 必须考虑：loading / 空数据 / 错误态
- 操作列按钮数量克制

### columns规范
- **[Ant]** `title`/`dataIndex`/`key` / **[EL]** `label`/`prop`/`key` — 明确且一致
- 自定义渲染简洁，不写大段业务逻辑
- 状态/时间/金额字段按项目统一格式展示

### 特别要求
- **[Ant]** `rowKey` / **[EL]** `row-key` 必须稳定，禁止不可靠索引
- 分页配置格式统一
- 表格滚动/固定列/固定头部优先走项目统一方案
- **[Ant]** `customRender`/插槽/render函数职责清晰 / **[EL]** `formatter`/插槽职责清晰
- 大表格关注性能，不在单元格渲染中创建大量新对象/新函数

---

## 十、Modal / Drawer 使用

- 多个弹窗必须拆分独立组件，不堆在页面主文件
- 弹窗命名明确：**[Ant]** `ModalXxxXxx` / **[EL]** `DialogXxxXxx` / `DrawerXxxXxx`
- 显隐状态命名：**[Ant]** `openModalXxxXxx` / **[EL]** `xxxDialogVisible` / `xxxDrawerVisible`

### 交互要求
- 打开时初始数据明确，关闭时状态清理明确
- 提交按钮有 loading
- 二次打开不残留脏状态
- 危险提交结合确认逻辑

### 选择Modal还是Drawer
- 简单编辑/确认/提示 → Modal/**[EL]** Dialog
- 较长表单/详情浏览/复杂操作 → Drawer
- 不因个人偏好混用，保持系统统一

### 状态控制
- 优先通过 **[Ant]** `v-model:open` / **[EL]** `v-model` 控制显隐
- 子组件不私自维护和父组件冲突的open状态
- 如需暴露打开方法用 `defineExpose` 且有统一规范

---

## 十一、Message / Notification / 确认框

- 成功 → **[Ant]** `message.success` / **[EL]** `ElMessage.success`
- 警告 → **[Ant]** `message.warning` / **[EL]** `ElMessage.warning`
- 错误 → **[Ant]** `message.error` / **[EL]** `ElMessage.error`
- 重要系统通知 → **[Ant]** `notification` / **[EL]** `ElNotification`
- 高风险动作确认 → **[Ant]** `Modal.confirm` / **[EL]** `ElMessageBox.confirm`

**禁止使用 `window.confirm()` / `window.alert()`**

### 反馈文案要求
- 简洁明确，说明动作结果
- 推荐："删除成功"/"保存成功"/"状态更新成功"/"提交失败，请稍后重试"
- 避免："操作完成"/"处理成功"

---

## 十二、Upload 使用

- 上传优先走项目已有封装
- 上传前校验（文件大小/类型限制）必须明确
- 上传成功与失败都应有反馈
- 返回结果结构统一处理，不暴露后端原始结构
- 涉及OSS/预览/回显/多文件管理时复用现有工具

---

## 十三、DatePicker / TimePicker 使用

- 日期处理统一使用 `dayjs`
- 展示格式/提交格式/查询格式统一
- 范围选择/起止时间边界/默认值逻辑明确
- 必须明确：展示给用户的格式 / 传给接口的格式 / 组件绑定值类型
- 不在模板散写大量日期转换逻辑

---

## 十四、Select / Cascader / TreeSelect 使用

- 选项数据优先配置化管理
- 选项值与显示文案语义清晰
- 异步选项加载处理 loading 与空状态
- 不在组件散写大量 options 常量，优先放 `config.ts`
- `value` 类型稳定，不一会儿string一会儿number
- 枚举选项统一维护：enum/options/字典映射表

---

## 十五、Tabs / Card / Descriptions 使用

- Tabs用于同级信息切换，不承载隐藏式页面路由逻辑
- Card用于结构分组和信息承载，保持间距层级统一
- Descriptions用于详情展示，不混入大量可编辑行为
- 多容器并存保证信息层级清晰

---

## 十六、Icons 使用

- 图标统一使用项目方案，不混入多套风格
- 图标表达业务含义，不为装饰滥用
- 同一语义复用同一图标
- 菜单图标/按钮图标/状态图标分层使用

---

## 十七、路由与权限协同

- 菜单/面包屑/页面标题由路由配置驱动
- 按钮权限复用统一权限判断工具，不散写模板
- 详情页/编辑页高亮依赖统一配置，不手工处理
- 权限判断优先在：路由守卫/权限指令/权限工具函数/按钮权限封装组件
- 禁止仅前端隐藏按钮而忽略后端权限校验

---

## 十八、Pinia协同

- 页面筛选/表格状态/用户配置相关数据优先评估是否进Pinia
- 不把临时UI状态和长期共享状态混放
- 共享字典/全局枚举/用户信息/权限信息有统一store管理
- 不在多页面重复请求相同基础数据

### 状态边界
- 页面内部短期 → 组件内管理
- 多组件共享 → composables 或 Pinia
- 全局级别 → Pinia
- 不为"看起来统一"把所有状态塞进store

---

## 十九、composables协同

- UI库相关复用逻辑优先沉淀为composables：
  - `useTable`/`usePagination`/**[Ant]** `useModal`/**[EL]** `useDialog`/`useDrawer`/`useFormRules`/`useDictionaryOptions`
- composables负责复用逻辑，不承担复杂视图渲染
- 不把组件实例引用/API调用/UI patch全揉进一个composable

---

## 二十、模板书写

- 模板只保留必要绑定和结构表达，不堆积复杂业务逻辑
- 复杂显示逻辑转移到 computed/格式化函数/composables/配置项
- 不在模板链式调用多个方法
- 原则："模板做展示，脚本做逻辑，配置做复用"

---

## 二十一、性能与可维护性

- 不在模板或渲染过程中创建大量重复对象/函数/配置
- 表格columns/表单配置/菜单配置优先抽离到配置文件
- 重型页面拆分子组件
- 公共配置集中，不散落多页面
- 关注：首屏压力/表单项响应式开销/大表格渲染/弹窗多实例/watch频繁触发

---

## 二十二、修改UI组件相关代码检查点

- 页面布局正常
- 表单/表格/弹窗/抽屉交互正常
- 样式不污染其它页面
- 主题变量统一
- 调用方兼容
- 权限与菜单高亮正常
- 路由跳转和缓存正常
- 表单回显和提交数据格式正确
- 表格分页/筛选/排序联动正常
- 弹窗重复打开无脏状态