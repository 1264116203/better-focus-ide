# Vue 前端验证依赖项与安装方法

本文件列出 wf-dev 工作流前端验证环节（ss-tdd-cycle 测试生成 / ss-test-run 测试执行 / ss-test-integration 真实联调 / ss-test-run 质量门禁）所需的依赖项，以及 Vue3 + Vite + TypeScript 项目中的安装方法。

## 一、系统级依赖

| 工具 | 用途 | 安装/确认方式 |
|------|------|---------------|
| Node.js 22+ | 前端构建运行环境 | `node -v` 确认 |
| npm | 包管理 | `npm -v` 确认 |

## 二、前端依赖（按需安装）

所有安装命令需在项目前端根目录（含 `package.json` 的目录）下执行。

### 1. 单元测试与覆盖率 — Vitest + Vue Test Utils + coverage-v8

**安装命令：**

```bash
npm install -D vitest @vitest/coverage-v8 @vue/test-utils happy-dom
```

| 包名 | 用途 |
|------|------|
| vitest | Vite-native 测试框架，与 Vue/Vite 零配置集成 |
| @vitest/coverage-v8 | V8 引擎覆盖率（推荐，比 istanbul 更快） |
| @vue/test-utils | Vue 组件单元测试官方工具 |
| happy-dom | 轻量 DOM 环境（比 jsdom 更快） |

**配置文件：`vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'happy-dom',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.{ts,vue}'],
      exclude: ['src/types/**', 'src/config/**'],
    },
  },
});
```

> 覆盖率阈值**不在本文件硬编码**，以 `.qoder/wf-dev.yaml` 的 `coverage.*` 配置为准（默认 `new_code: 100` / `overall: 70`），由 ss-test-run 执行时读取校验。

**package.json scripts 添加：**

```json
{
  "scripts": {
    "test:unit": "vitest run",
    "test:coverage": "vitest run --coverage",
    "test:watch": "vitest"
  }
}
```

**执行命令：**
- 单元测试: `npm run test:unit`（ss-tdd-cycle / ss-test-run 使用）
- 覆盖率: `npm run test:coverage`

### 2. 代码风格与类型检查 — ESLint + vue-tsc

ESLint flat config 配置规范见同目录 `code-style.md` → "ESLint 配置规范"，此处仅列安装与执行命令。

**安装命令：**

```bash
npm install -D eslint @eslint/js typescript-eslint vue-eslint-parser eslint-plugin-vue
```

**执行命令：**
- 规范检查: `npm run lint`（package.json scripts 添加 `"lint": "eslint src/"`）
- 自动修复: `npx eslint --fix src/`
- 类型检查: `npm run type-check`（`vue-tsc --noEmit`，ss-test-run 使用）

### 3. E2E 集成测试 — Playwright（全栈项目/联调场景）

真实环境联调用（ss-test-integration），测试环境模式（mock/real/hybrid）见同目录 `testing.md` → "前端测试环境模式 (test_env)"。

**安装命令：**

```bash
npm install -D @playwright/test
npx playwright install
```

**执行命令：** `npm run test:e2e`（package.json scripts 添加 `"test:e2e": "playwright test"`）

### 4. 安全审计 — npm audit

npm 内置功能，无需额外安装。执行: `npm audit`

**判定标准：**
- 0 critical + 0 high → PASS
- 存在 critical/high → 阻断（安全零容忍），需 `npm audit fix` 或手动升级

### 5. 构建验证 — Vite build

**执行命令：** `npm run build`（含 `vue-tsc --noEmit && vite build`），ss-test-run 构建检查使用。

## 三、wf-dev 技能对应命令速查

| 技能 | 检查项 | 命令 |
|------|--------|------|
| ss-tdd-cycle | 单元测试（红绿循环） | `npm run test:unit` |
| ss-test-run | 测试执行与报告 | `npm run test:unit` / `npm run test:e2e` |
| ss-test-integration | 真实环境联调 | `npx playwright test` |
| ss-test-run | 构建 | `npm run build` |
| ss-test-run | 类型检查 | `npm run type-check` |
| ss-test-run | 覆盖率 | `npm run test:coverage`（阈值按 `coverage.*` 配置） |
| ss-test-run | 规范检查 | `npm run lint` |
| 安全门禁 | 依赖审计 | `npm audit` |

**全栈项目注意：** 后端验证并行执行，命令见 `wf-rules/tech-stacks/backend-rules/` 对应栈规则。所有验证结论必须附真实命令输出证据（证据先于宣称），由 ss-test-run 汇总写 `quality-gate.md`；任一 FAIL 即整体 FAIL，禁止宣称完成。

## 四、安装顺序建议

1. 先安装 ESLint 生态 → 配置 `eslint.config.js`（见 code-style.md）→ 添加 `npm run lint` script → 验证 `npm run lint` 通过
2. 再安装 Vitest 生态 → 配置 `vitest.config.ts` → 添加 test scripts → 验证 `npm run test:unit` 可执行
3. 验证 `npm run test:coverage` 覆盖率报告生成
4. 全量验证：`npm run lint && npm run type-check && npm run test:unit && npm audit && npm run build`
