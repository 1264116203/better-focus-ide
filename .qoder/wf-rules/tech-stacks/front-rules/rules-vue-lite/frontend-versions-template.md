# Vue 3.5 + Vite 6.4 标准前端规范

**版本声明模板** - 本文档定义标准 Vue 3.5 + Vite 6.4 前端项目的依赖版本、构建配置和质量验证规范。

**适用范围:** 所有基于 Vue 3.5.34 + Vite 6.4.2 的前端项目

---

## 快速索引

| 章节 | 内容 |
|------|------|
| [依赖版本清单](#依赖版本清单) | 核心依赖、开发依赖 |
| [项目配置模板](#项目配置模板) | package.json 通用配置 |
| [质量验证规范](#质量验证规范) | 验证依赖与命令（wf-dev 验证类技能） |

---

## 依赖版本清单

### 核心依赖规范

| 分类 | 包名 | 声明版本 | 锁定版本 | 必选 |
|------|------|----------|----------|------|
| **核心框架** ||||
| Vue | vue | ^3.5.0 | 3.5.34 | ✅ |
| Vue Router | vue-router | ^4.5.0 | 4.6.4 | ✅ |
| Pinia | pinia | ^2.0.0 | 2.3.1 | ✅ |
| **UI 组件库** ||||
| Ant Design Vue | ant-design-vue | ^4.2.0 | 4.2.6 | ⚪ |
| Ant Design Icons | @ant-design/icons-vue | ^7.0.0 | 7.0.1 | ⚪ |
| Element Plus | element-plus | ^2.0.0 | - | ⚪ |
| **工具库** ||||
| Axios | axios | ^1.15.0 | 1.16.1 | ✅ |
| Day.js | dayjs | ^1.11.0 | 1.11.20 | ⚪ |

**图例:** ✅ 必选 | ⚪ 可选

### 开发依赖规范

| 分类 | 包名 | 声明版本 | 锁定版本 | 用途 |
|------|------|----------|----------|------|
| **构建工具** ||||
| Vite | vite | ^6.0.0 | 6.4.2 | 构建工具 |
| Vue Plugin | @vitejs/plugin-vue | ^5.0.0 | 5.2.4 | Vue 支持 |
| Less | less | ^4.2.0 | 4.6.4 | CSS 预处理 |
| TypeScript | typescript | ^5.0.0 | 5.8.2 | 类型支持（可选）|
| **代码质量** ||||
| ESLint | eslint | ^9.39.4 | 9.39.4 | 代码检查 |
| ESLint JS | @eslint/js | ^9.39.4 | 9.39.4 | JS 规则 |
| ESLint Vue | eslint-plugin-vue | ^10.9.1 | 10.9.1 | Vue 规则 |
| Vue Parser | vue-eslint-parser | ^10.4.0 | 10.4.0 | Vue 解析器 |
| TypeScript ESLint | typescript-eslint | ^8.59.4 | 8.59.4 | TS 支持（可选）|
| **测试** ||||
| Vitest | vitest | ^4.1.7 | 4.1.7 | 测试框架 |
| Coverage V8 | @vitest/coverage-v8 | ^4.1.7 | 4.1.7 | 覆盖率工具 |
| Vue Test Utils | @vue/test-utils | ^2.4.10 | 2.4.10 | Vue 组件测试 |
| Happy DOM | happy-dom | ^20.9.0 | 20.9.0 | 浏览器环境模拟 |

### 环境要求

| 工具 | 版本要求 | 用途 |
|------|----------|------|
| Node.js | v22+ | 运行环境 |
| npm | 10.9.0+ | 包管理器 |

---

## 项目配置模板

### package.json 模板

**用途:** 新项目初始化时的 package.json 基础配置

```json
{
  "name": "your-application-name",
  "version": "1.0.0",
  "description": "Your application description",
  "type": "module",
  "main": "src/main.{js,ts}",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "type-check": "vue-tsc --noEmit && vite build",
    "lint": "eslint src/",
    "lint:fix": "eslint src/ --fix",
    "test": "vitest run",
    "test:coverage": "vitest run --coverage",
    "test:watch": "vitest"
  },
  "dependencies": {
    "vue": "^3.5.0",
    "vue-router": "^4.5.0",
    "pinia": "^2.0.0",
    "axios": "^1.15.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "vite": "^6.0.0",
    "less": "^4.2.0",
    "eslint": "^9.39.4",
    "@eslint/js": "^9.39.4",
    "eslint-plugin-vue": "^10.9.1",
    "vue-eslint-parser": "^10.4.0",
    "globals": "^17.6.0",
    "vitest": "^4.1.7",
    "@vitest/coverage-v8": "^4.1.7",
    "@vue/test-utils": "^2.4.10",
    "happy-dom": "^20.9.0"
  }
}
```

### vite.config.js 模板

```javascript
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': '/src',
      '#': '/public'
    }
  },
  server: {
    port: 3000,
    host: true
  }
});
```

### vitest.config.ts 模板

```typescript
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
      thresholds: {
        lines: 70,
        functions: 70,
        branches: 70,
        statements: 70
      }
    }
  }
});
```

### eslint.config.js 模板

```javascript
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import pluginVue from 'eslint-plugin-vue';
import vueParser from 'vue-eslint-parser';

export default tseslint.config(
  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        ecmaVersion: 'latest',
        sourceType: 'module'
      }
    }
  },
  {
    rules: {
      'vue/no-unused-vars': 'warn',
      'no-unused-vars': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }]
    }
  },
  {
    ignores: ['dist/**', 'node_modules/**']
  }
);
```

### 标准项目目录结构

```
{项目根目录}/
├── package.json
├── package-lock.json
├── vite.config.js
├── vitest.config.ts
├── eslint.config.js
├── index.html
└── src/
    ├── main.{js,ts}
    ├── App.vue
    ├── pages/                      # 页面组件
    ├── components/                 # 全局组件
    ├── router/                     # 路由配置
    ├── store/                      # 状态管理
    ├── utils/                      # 工具函数
    ├── api/                        # API 接口
    ├── __tests__/                  # 测试文件
    └── types/                      # 类型定义（可选）
```

---

## 质量验证规范

### 质量验证（wf-dev 验证类技能）

#### 依赖版本一致性检查（推荐）

检查项目依赖版本是否与本规范一致，如一致可跳过部分安全检查。（如项目配置有版本比对脚本，则执行脚本并输出对比报告；否则人工核对 `package.json` 与本文件版本清单）

#### Lint 与类型检查

```bash
npm run lint
```

**TypeScript 类型检查（如使用 TS）:**
```bash
npm run type-check
```

#### 安全审计

```bash
npm audit
```

#### 测试验证

**完整测试 + 覆盖率:**
```bash
npm run test:coverage
```

**仅测试:**
```bash
npm run test:unit
```

**目标覆盖率:** 以 `.qoder/wf-dev.yaml` `coverage.*` 配置为准（默认 `overall: 70` / `new_code: 100`）

### 自动修复

```bash
npm run lint:fix
```

### CICD 验证

#### 构建验证

```bash
npm run build
```

#### 类型检查 + 构建

```bash
npm run type-check && npm run build
```

---

## 版本维护

### 更新原则

1. **单一真实来源** - 本文件是版本定义的唯一来源
2. **向后兼容** - 主版本更新需评估影响
3. **测试验证** - 更新后需验证兼容性

### 禁止操作

- ❌ 禁止使用本规范不支持的非规范版本
- ❌ 禁止跳过版本验证直接使用最新版
- ❌ 禁止在其他地方硬编码本文件定义的版本

### 相关模板

- **后端版本模板:** `backend-rules/rules-java-17/backend/backend-versions-template.md`（路径以 `.qoder/wf-rules/tech-stacks/` 为基准）
