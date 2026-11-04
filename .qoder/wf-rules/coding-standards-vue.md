---
trigger: glob
glob: **/*.vue
---
# Vue / 前端编码规范（栈扩展）

适用 Vue 3.x（Composition API + `<script setup>`）、TypeScript 5.x、Vite。继承 `coding-standards.md`。

## 组件与结构

- 组件使用 `<script setup lang="ts">`，禁用 Options API（除非维护遗留代码）。
- 组件文件 PascalCase 命名（`UserProfile.vue`）；组合式函数 `use` 前缀（`useAuth.ts`）。
- 单文件组件顺序：`<script setup>` → `<template>` → `<style scoped>`。
- Props 必须声明类型（`defineProps<{ title: string }>()`），必填项不设默认值，可选项用 `withDefaults`。
- Emit 必须声明类型（`defineEmits<{ change: [value: string] }>()`）。

## 状态管理

- 组件局部状态用 `ref`/`reactive`；跨组件状态用 Pinia store（`defineStore`）。
- 禁止在组件外直接操作 DOM；禁止在 store 外持久化状态（除非通过 Pinia plugin）。
- 异步数据用 `async/await` + `try/catch`，禁止裸 Promise 链。

## 样式与布局

- `<style scoped>` 为默认；全局样式仅在 `assets/styles/` 下集中管理。
- 禁止内联样式（`style=""`）；CSS 类名 kebab-case。
- 响应式用 Tailwind CSS 或 CSS 变量；禁止 `!important`（除非覆盖第三方库）。

## 类型与接口

- 所有 API 响应/请求定义 TypeScript interface，放 `types/` 或 `interfaces/` 目录。
- 禁止 `any`（除第三方库无类型声明时的 `// @ts-expect-error` 注释）。
- 枚举用 `const enum` 或字面量联合类型，禁用 `enum` 关键字（编译产物过大）。

## 测试

- 单元测试 Vitest + Vue Test Utils；组件测试用 Testing Library。
- E2E 测试 Playwright；Mock 用 MSW（Mock Service Worker）。
- 覆盖率阈值：新增代码 100%（强制）；整体代码 enhanced ≥70%，basic ≥关键路径覆盖。
- 命名 `describe('ComponentName')` + `it('should ...')`，遵循 AAA（Arrange-Act-Assert）。

## 构建命令策略

- 开发：`npm run dev`（Vite HMR）；构建：`npm run build`（生产产物）。
- 类型检查：`npm run type-check`（`vue-tsc --noEmit`）；Lint：`npm run lint`（ESLint + Prettier）。
- 禁 `npm run build --watch` 污染 CI；禁直接修改 `dist/` 产物。
