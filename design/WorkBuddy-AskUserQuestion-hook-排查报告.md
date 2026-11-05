# WorkBuddy AskUserQuestion hook 排查报告

> 日期：2026-11-05
> 目标：让「灵动岛提问卡片先于 WorkBuddy IDE 面板出现」，并且「岛上作答后 IDE 面板自动消失」
> 结论：**「岛先弹」可行且已实现；「岛上作答关闭 IDE 面板」在 WorkBuddy 上不可行，受产品架构硬限制。**

---

## 一、结论先行

| 诉求 | 是否可行 | 说明 |
|---|---|---|
| 岛先于 IDE 面板弹出题面 | ✅ 可行（已实现） | 靠 `Notification(permission_prompt)` + 转录预取 |
| 岛上作答、IDE 面板自动消失 | ❌ 不可行 | WorkBuddy 提问面板是进程内 REPL 交互，hook 无法注入答案或关闭它 |
| 借助 PermissionRequest 让岛先弹 | ❌ 对 WorkBuddy 无效 | WorkBuddy 对 AskUserQuestion **从不发** PermissionRequest |

---

## 二、真实时序（探针实测）

探针记录（`/tmp/bf-probe-events.log`，2026-11-05 20:42）：

```
20:42:13  Notification  notification_type=permission_prompt
          message="needs your permission to use AskUserQuestion"
          （无 tool_name / tool_input，只有一句 message）
20:42:17  PreToolUse    tool_name=AskUserQuestion
          tool_input={questions:[...]}   ← 用户答完之后 4 秒才发
（全程无 PermissionRequest）
```

即：提问面板出现那一刻只发一条 `Notification`；用户答完、工具真正执行前才发 `PreToolUse`。

## 三、WorkBuddy 源码级证据（shared.cjs）

证据文件：`/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/node_modules/@genie/agent-harness/cli/dist-server/shared.cjs`

### 1. AskUserQuestion 是「产品交互工具」，走 REPL 而非权限审批

```js
function isProductInteractionTool(ei) {
    return ei === ASK_USER_QUESTION || ei === EXIT_PLAN_MODE;
}
```

### 2. 产品交互工具被显式跳过 PermissionRequest hook

```js
if (eI?.behavior === "ask") {
    if (!isProductInteractionTool(ea)) {          // AskUserQuestion 走 true → 跳过
        let ev = await this.dispatchReplPermissionRequest(...); // 只有非产品工具才走
        ...
    }
    ...
}
```

→ 这就是「WorkBuddy 从不发 PermissionRequest」的根本原因。

### 3. 提问面板关闭只靠进程内 REPL 交互回调

```js
async function runReplProductInteraction(ei, ea, eg, eA, ev) {
    ...
    // 面板弹出前，只发一条观测型 Notification
    return (await ei.onWillPrompt?.(),
        "approved" !== await waitForNestedDecision(ei.interruptionService, ...))
        ? fail : executeNested(...)
}

function waitForNestedDecision(ei, ea, eg, eA) {
    return new Promise(ev => {
        ...
        // 把「关闭面板」的 resolve 挂到审批项上，只有 UI 点选才触发
        (eg.rawItem.providerData ??= {})._sandboxResolve = ei => {
            settle(ei === false || ei === "deny" ? "rejected" : "approved");
        };
        ...
        ei.enqueueSandboxApproval(ea, eg);  // 入 IDE 审批队列
    });
}
```

### 4. Notification hook 的 stdout 不被消费

```js
onWillPrompt: async () => {
    await eg.executeNotificationHooks(ei.context,
        `needs your permission to use ${ea}`, PERMISSION_PROMPT)
}
```

`executeNotificationHooks` 是 fire-and-forget，返回值（hook 的 stdout，含 `permissionDecision`）**不会被用来关闭面板**。

---

## 四、为什么「岛答完、IDE 面板还在等」

因果链：

1. WorkBuddy 弹提问面板时，只发 `Notification`（观测型，stdout 不读）。
2. 面板关闭由 `_sandboxResolve` 回调驱动，回调由 `interruptionService`（IDE 的 UI 审批队列）在用户点选时触发。
3. 这是 WorkBuddy **进程内**的事件循环，没有任何外部 socket / 文件 / hook 通道能注入这个 resolve。
4. `PreToolUse` 要等面板答完、工具执行时才发，那时面板已关，来不及。

因此：岛侧无论怎么回 `allow` / `deny`，WorkBuddy 都不会读，也不会关面板。

---

## 五、当前实现状态

- 预取题面（岛先弹）：**已实现**，`_collect_tool_blocks` 已修复为识别 WorkBuddy 的
  `function_call` + `arguments`(JSON 字符串) 形状，实测 `uses=6` 命中（`prefetch.log: 20:49:32 hit try=0`）。
- 岛上作答关 IDE 面板：**不可实现**（见第四节）。

## 六、可选后续方向

1. **保留预取、把岛卡片改为只读预览**：岛先显示题目让用户提前看清，但明确提示「请在 IDE 面板作答」，避免双次作答的困惑。
2. **回退预取、WorkBuddy 提问完全交还 IDE**：岛只处理其他宿主（Qoder / OpenCode）的提问，彻底避免双次作答。
3. **维持现状**：岛可作答但 IDE 面板不消失（体验不佳，不推荐）。

## 七、待办

- [ ] 移除 `/tmp/bf-probe` 探针代码（`HostHookTemplate.swift` 中 `PROBE` 相关段），或默认关闭。
- [ ] 根据选定的方向（第六节）调整 `preview_question` / 岛侧 `QuestionController`。
- [ ] 全量测试 + 提交。
