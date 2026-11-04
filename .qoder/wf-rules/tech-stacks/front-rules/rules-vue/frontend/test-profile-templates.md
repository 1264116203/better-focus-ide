# Vitest test_env 模式配置模板

本文件提供三种 test_env 模式（mock / real / hybrid）的 Vitest 配置模板与 package.json scripts 模板，供 Vue3 + Vite + TypeScript 项目按需选用。test_env 模式选择见 `testing.md` → "前端测试环境模式 (test_env)"。

> **覆盖率阈值不在此硬编码**，以 `.qoder/wf-dev.yaml` 的 `coverage.*` 配置为准（默认 `new_code: 100` / `overall: 70`），验证时读取校验。

## 一、mock 模式

默认模式，纯前端单元/组件测试，所有外部依赖通过 `vi.mock` 替换。

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

**package.json scripts：**

```json
{
  "scripts": {
    "test:unit": "vitest run",
    "test:coverage": "vitest run --coverage",
    "test:watch": "vitest"
  }
}
```

**说明：** mock 模式无需额外安装，使用 Vitest + happy-dom 配置即可。外部 API 调用通过 `vi.mock` 模拟，不需要后端服务运行。

---

## 二、real 模式

E2E 测试与 Vitest 并行运行，需后端服务处于可达状态。

**Playwright 安装：**

```bash
npm install -D @playwright/test
npx playwright install
```

**配置文件：`vitest.config.real.ts`** — 与 mock 模式的 `vitest.config.ts` 相同（覆盖率配置同上）。

**Playwright 配置文件：`playwright.config.ts`**

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:5173',
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
});
```

**E2E 测试目录结构：**

```
<前端根目录>/
  e2e/
    <模块>/
      <页面>.spec.ts
    smoke/
      homepage.spec.ts
```

**E2E 测试示例：`e2e/smoke/homepage.spec.ts`**

```ts
import { test, expect } from '@playwright/test';

test('homepage renders correctly', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('h1')).toHaveText(/欢迎/);
});

test('list page loads data from real API', async ({ page }) => {
  await page.goto('/list');
  await expect(page.locator('[data-test="list-item"]').first()).toBeVisible();
});
```

**package.json scripts：**

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:all": "npm run test:unit && npm run test:e2e",
    "test:coverage:all": "npm run test:coverage && npm run test:e2e"
  }
}
```

**前置条件：**
- 后端服务必须运行（`mvn spring-boot:run`、`npm run dev` 或项目等效命令）
- 前端 dev server 启动（Playwright `webServer` 配置自动启动，或手动启动 `npm run dev`）
- 环境变量 `E2E_BASE_URL` 可覆盖默认 `http://localhost:5173`

**说明：** real 模式下 Vitest 单元测试仍使用 happy-dom + `vi.mock`，但增加 Playwright E2E 测试覆盖真实交互流程。覆盖率合并需通过覆盖率报告工具手动合并 Vitest 与 Playwright 的结果。

---

## 三、hybrid 模式

部分测试走真实 API（E2E）、其余走 mock，通过 `TEST_ENV` 环境变量切换。

**依赖：** 与 real 模式相同（需安装 `@playwright/test` 及浏览器驱动）。

**配置文件：`vitest.config.hybrid.ts`** — 与 mock 模式的 `vitest.config.ts` 相同（覆盖率配置同上）。

**选择性 mock 覆盖说明：**

1. 对于需要真实 API 的测试文件，用 `describe.skipIf` 控制在 hybrid 环境下执行：

```ts
// src/api/<module>.test.ts
// 该测试需要真实后端 API（仅 hybrid/real 环境执行）
import { describe, it, expect } from 'vitest';

describe.skipIf(process.env.TEST_ENV !== 'hybrid')('<模块> API (real)', () => {
  it('returns expected data', async () => {
    // 调用真实 API，不使用 vi.mock
  });
});
```

2. 对于纯 mock 测试，保持 `vi.mock` 写法不变。

**package.json scripts：**

```json
{
  "scripts": {
    "test:hybrid": "TEST_ENV=hybrid vitest run",
    "test:coverage:hybrid": "TEST_ENV=hybrid vitest run --coverage"
  }
}
```

**前置条件：**
- 后端服务需运行（用于标记为 hybrid 的测试）
- Playwright 配置可选（仅对需要 E2E 的场景）

**说明：** hybrid 模式是 mock 与 real 的折中。大部分测试仍用 `vi.mock` 快速执行，关键交互路径通过 `describe.skipIf` 控制在 hybrid 环境下走真实 API。开发者可通过 `TEST_ENV` 环境变量灵活切换。

---

## 四、模式选择建议

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 本地开发快速迭代 | mock | 无需后端，执行速度快 |
| 发布前全链路验证 | real | 覆盖真实交互 |
| 日常开发但需验证关键路径 | hybrid | 平衡速度与覆盖率 |
