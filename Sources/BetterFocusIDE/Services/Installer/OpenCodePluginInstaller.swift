// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 OpenCode 插件，把提问、会话空闲（轮次完成）和待办
/// 通过 Unix socket 转发到 BetterFocusIDE 灵动岛。
///
/// 一份文件两个入口：V2 调 `setup()`，V1（1.18.29 起）调 `server()`。
/// 权限卡两边都不做。
enum OpenCodePluginInstaller {
    static let pluginPath = InstallerPaths.opencodePluginPath

    /// 安装：确保目录存在后写入插件；内容相同则跳过（幂等，保持 mtime 稳定）。
    static func install() throws {
        let dir = (pluginPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = pluginContent
        // 幂等：不重写相同内容（保持 mtime 稳定）。
        if let existing = try? String(contentsOfFile: pluginPath, encoding: .utf8),
           existing == content { return }
        try content.write(toFile: pluginPath, atomically: true, encoding: .utf8)
    }

    /// 卸载：删除插件文件。
    static func uninstall() {
        try? FileManager.default.removeItem(atPath: pluginPath)
    }

    /// 通过文件是否存在判断安装状态。
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: pluginPath)
    }

    /// 插件正文：安装时把占位符替换为本构建的命名空间路径与超时值。
    static var pluginContent: String {
        PluginTemplate.body
            .replacingOccurrences(of: "__SOCKET_PATH__", with: InstallerPaths.socketPath)
            .replacingOccurrences(of: "__ANSWER_DIR__", with: InstallerPaths.answerDir)
            .replacingOccurrences(of: "__SETTINGS_PATH__", with: InstallerPaths.settingsPath)
            .replacingOccurrences(of: "__ANSWER_TIMEOUT_MS__",
                                  with: "\(InstallerPaths.questionTimeoutSeconds * 1000)")
    }
}

/// 内嵌的 `betterfocus-notify.js` 正文。占位符在安装时替换，使插件指向本构建的命名空间。
enum PluginTemplate {
    static let body = """
        // BetterFocusIDE <-> OpenCode plugin.
        //
        // One file, two entries. V2 calls setup(); V1 (1.18.29+) calls server()
        // and ignores setup. A static import of @opencode/plugin would fail to
        // load on V1, so this file exports a plain object.
        //
        // 1. Questions.
        //    V2 replaces question.execute and returns the island's choice as the
        //    tool result. If the island is unreachable the original tool runs.
        //    V1 listens for question.asked and replies with client.question.reply.
        //    The TUI form can flash until that reply arrives. If the client has
        //    no reply method, or the island is down, the hook writes nothing.
        // 2. Turn finished: V2 watches the event stream; V1 uses the event hook
        //    for session.idle and session.status { type: idle }.
        // 3. Todo progress: V2 wraps the todo tool when it still exists. V1
        //    forwards tool.execute.after for the same names. A removed tool
        //    simply never enters the hook.
        //
        // Permission cards are intentionally not implemented on either entry.
        //
        // Answer files:
        //   __ANSWER_DIR__/<session>_<request>_<id>.json
        // carrying { answer_index, answer_label }; -1 = timeout, -2 = custom,
        // -4 = hand the question back to the host.

        import net from 'node:net';
        import fs from 'node:fs';

        const SOCKET_PATH = process.env.BETTERFOCUS_SOCKET_PATH || '__SOCKET_PATH__';
        const ANSWER_DIR = process.env.BETTERFOCUS_ANSWER_DIR || '__ANSWER_DIR__';
        const SETTINGS_PATH = process.env.BETTERFOCUS_SETTINGS_PATH || '__SETTINGS_PATH__';

        const SOCKET_TIMEOUT_MS = 2000;
        const ANSWER_TIMEOUT_MS = __ANSWER_TIMEOUT_MS__;
        const POLL_MS = 250;

        function alertsEnabled(kind) {
          // 设置文件里 `values` 的键是驼峰（Settings 的 @Published 名），
          // 旧版 Python 实现用的是下划线键。两种都认，驼峰优先。
          const keys = kind === 'question' ? ['questionEnabled', 'question_enabled']
            : (kind === 'permission' ? ['permissionEnabled', 'permission_enabled']
              : (kind === 'turn' ? ['turnNotifyEnabled', 'turn_notify_enabled'] : null));
          if (!keys) return true;
          try {
            const parsed = JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
            const values = (parsed && parsed.values) || {};
            for (const key of keys) {
              if (key in values) return values[key] !== false;
            }
            return true;
          } catch { return true; }
        }

        function sendToIsland(message) {
          // ACP 桥已经按外面那个 IDE 发过通知。返回 false，提问会交回宿主自己的对话框。
          if (process.env.BETTERFOCUS_ACP_BRIDGE === '1') return Promise.resolve(false);
          return new Promise((resolve) => {
            const client = new net.Socket();
            let settled = false;
            const done = (ok) => { if (!settled) { settled = true; resolve(ok); } };
            client.connect(SOCKET_PATH, () => {
              client.write(JSON.stringify(message) + '\\n');
              client.end();
              done(true);
            });
            client.on('error', () => done(false));
            client.setTimeout(SOCKET_TIMEOUT_MS, () => { client.destroy(); done(false); });
          });
        }

        function normaliseQuestions(input, sessionID) {
          const args = input && typeof input === 'object' ? input : {};
          const raw = (Array.isArray(args.questions) && args.questions.length)
            ? args.questions : (args.question ? [args] : []);
          return raw.map((q, i) => ({
            id: q.id || (sessionID + '-q' + (i + 1)),
            header: q.header || 'Question',
            question: q.question || '',
            multiSelect: q.multiple === true || q.multiSelect === true,
            options: (q.options || []).map((o) =>
              (typeof o === 'string')
                ? { label: o, description: '' }
                : { label: o.label || '', description: o.description || '' })
          }));
        }

        // 待办整表：OpenCode 的工具名是 todowrite（v2 已移除，wrap 不到就自然跳过）。
        // 字段是 content + status，但这里仍按各家的别名兜一遍，避免版本差异导致丢项。
        function normaliseTodos(input) {
          const args = input && typeof input === 'object' ? input : {};
          const raw = Array.isArray(args.todos) ? args.todos
            : (Array.isArray(args.tasks) ? args.tasks : []);
          const todos = [];
          raw.forEach((item, i) => {
            if (typeof item === 'string') {
              const text = item.trim();
              if (text) todos.push({ id: 't' + i, content: text, status: 'pending' });
              return;
            }
            if (!item || typeof item !== 'object') return;
            const content = String(item.content || item.title || item.subject || '').trim();
            if (!content) return;
            let status = item.status || item.state;
            if (!status) status = item.completed ? 'completed' : 'pending';
            todos.push({
              id: String(item.id || item.task_id || ('t' + i)),
              content,
              status: String(status)
            });
          });
          return todos;
        }

        function answerPath(sessionID, requestID, questionID) {          return requestID
            ? ANSWER_DIR + '/' + sessionID + '_' + requestID + '_' + questionID + '.json'
            : ANSWER_DIR + '/' + sessionID + '_' + questionID + '.json';
        }

        function readAnswer(sessionID, requestID, questionID, sinceMs) {
          const files = [answerPath(sessionID, requestID, questionID)];
          if (requestID) files.push(answerPath(sessionID, '', questionID));
          for (const file of files) {
            let raw;
            try {
              if (fs.statSync(file).mtimeMs < sinceMs - 1000) continue;
              raw = fs.readFileSync(file, 'utf8');
            } catch { continue; }
            let parsed;
            try { parsed = JSON.parse(raw); } catch { continue; }
            if (parsed.request_id && requestID && parsed.request_id !== requestID) continue;
            try { fs.unlinkSync(file); } catch {}
            const index = typeof parsed.answer_index === 'number' ? parsed.answer_index : -1;
            // 岛侧让位（宿主自带提问面板且正在前台）：交回原生 question 工具。
            if (parsed.defer === true || index === -4) return { deferred: true };
            if (index === -1) return { timedOut: true };
            const label = typeof parsed.answer_label === 'string' ? parsed.answer_label : '';
            const labels = (index === -3)
              ? label.split('\\u3001').filter((p) => p.length)
              : (label ? [label] : []);
            return { labels };
          }
          return null;
        }

        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

        async function awaitAnswers(questions, sessionID, requestID, sinceMs) {
          const deadline = Date.now() + ANSWER_TIMEOUT_MS;
          const answers = questions.map(() => []);
          while (Date.now() < deadline) {
            let pending = 0;
            for (let i = 0; i < questions.length; i++) {
              if (answers[i].length) continue;
              const got = readAnswer(sessionID, requestID, questions[i].id, sinceMs);
              if (got === null) { pending++; continue; }
              if (got.deferred) return { answers, resolved: false, deferred: true };
              if (got.timedOut) return { answers, resolved: false };
              if (got.labels.length) answers[i] = got.labels;
            }
            if (pending === 0) return { answers, resolved: true };
            await sleep(POLL_MS);
          }
          return { answers, resolved: false };
        }

        // 有的版本会把 setup 和 server 都调一次。先到的入口占住，后到的直接返回，
        // 避免同一轮弹出两张卡。
        let entryClaimed = false;

        const TODO_TOOL_NAMES = new Set(['todowrite', 'todo_write', 'TodoWrite', 'SetTodoList']);
        const V1_TURN_DEBOUNCE_MS = 2000;
        const v1LastTurnAt = new Map();

        async function replyFromIsland(props, client) {
          const sessionID = props.sessionID || props.session_id || 'unknown';
          if (!alertsEnabled('question')) return;
          const questions = normaliseQuestions({ questions: props.questions }, sessionID);
          if (!questions.length) return;
          const requestID = props.id || ('q' + Date.now());
          const sent = await sendToIsland({
            provider: 'opencode', event: 'question_requested',
            session_id: sessionID, timestamp: new Date().toISOString(),
            payload: { questions, request_id: requestID }
          });
          if (!sent) return;
          const reply = client && client.question && client.question.reply;
          if (typeof reply !== 'function') return;
          const result = await awaitAnswers(questions, sessionID, requestID, Date.now());
          if (result.deferred) return;
          if (!result.resolved) {
            await sendToIsland({
              provider: 'opencode', event: 'question_timeout',
              session_id: sessionID, timestamp: new Date().toISOString(),
              payload: { question_id: questions[0].id, request_id: requestID }
            });
            return;
          }
          try {
            await reply.call(client.question, { requestID, answers: result.answers });
          } catch { /* 回写失败就留着 TUI 自己的提问框 */ }
        }

        async function handleV1Event(event, client, directory) {
          if (!event || typeof event.type !== 'string') return;
          const props = event.properties || {};
          if (event.type === 'question.asked') {
            await replyFromIsland(props, client);
            return;
          }
          const idle = event.type === 'session.idle'
            || (event.type === 'session.status' && props.status && props.status.type === 'idle');
          if (!idle || !alertsEnabled('turn')) return;
          const sessionID = props.sessionID || props.session_id || 'unknown';
          const now = Date.now();
          if (now - (v1LastTurnAt.get(sessionID) || 0) < V1_TURN_DEBOUNCE_MS) return;
          v1LastTurnAt.set(sessionID, now);
          if (v1LastTurnAt.size > 64) v1LastTurnAt.clear();
          await sendToIsland({
            provider: 'opencode', event: 'turn_finished',
            session_id: sessionID, timestamp: new Date().toISOString(),
            payload: { directory: directory || '', pid: process.pid }
          });
        }

        export default {
          id: 'betterfocus-notify',
          async setup(ctx) {
            if (entryClaimed) return;
            entryClaimed = true;
            // Questions: take over the question tool's execution.
            await ctx.tool.transform((tools) => {
              const question = tools.get('question');
              if (!question) return;
              const original = question.execute;
              tools.update('question', (tool) => {
                tool.execute = async (input, context) => {
                  const sessionID = (context && context.sessionID) || 'unknown';
                  if (!alertsEnabled('question')) return original(input, context);
                  const questions = normaliseQuestions(input, sessionID);
                  if (!questions.length) return original(input, context);
                  const requestID = 'q' + Date.now();
                  const sent = await sendToIsland({
                    provider: 'opencode', event: 'question_requested',
                    session_id: sessionID, timestamp: new Date().toISOString(),
                    payload: { questions, request_id: requestID }
                  });
                  if (!sent) return original(input, context);
                  const { answers, resolved, deferred } = await awaitAnswers(
                    questions, sessionID, requestID, Date.now());
                  // 让位：宿主自带提问面板且用户就在它前面 → 交回原生工具，
                  // 只问一次。不发 question_timeout，否则岛上会留一张废卡。
                  if (deferred) return original(input, context);
                  if (!resolved) {
                    await sendToIsland({
                      provider: 'opencode', event: 'question_timeout',
                      session_id: sessionID, timestamp: new Date().toISOString(),
                      payload: { question_id: questions[0].id, request_id: requestID }
                    });
                    return { output: { answers: questions.map(() => []) } };
                  }
                  return { output: { answers } };
                };
              });
            });

            // Todo progress: wrap the todo tool so every write forwards the full
            // list. todowrite is overwrite-semantics (the whole table each time),
            // which is exactly what the island's todo_updated expects.
            await ctx.tool.transform((tools) => {
              for (const name of ['todowrite', 'todo_write', 'TodoWrite', 'SetTodoList']) {
                const tool = tools.get(name);
                if (!tool) continue;
                const originalTodo = tool.execute;
                tools.update(name, (t) => {
                  t.execute = async (input, context) => {
                    const result = await originalTodo(input, context);
                    try {
                      const todos = normaliseTodos(input);
                      if (todos.length) {
                        await sendToIsland({
                          provider: 'opencode', event: 'todo_updated',
                          session_id: (context && context.sessionID) || 'unknown',
                          timestamp: new Date().toISOString(),
                          payload: { todos }
                        });
                      }
                    } catch { /* 待办只是过程可视化，绝不影响工具本身 */ }
                    return result;
                  };
                });
              }
            });

            // Turn finished: pop the notice when a session goes idle.
            //
            // ctx.event is an async-iterable stream, NOT an EventEmitter:
            // ctx.event.on does not exist (silently undefined), so the old
            // code registered nothing and no notice ever fired — with the
            // plugin still "loading" cleanly. Subscribe and iterate instead.
            //
            // 2.2.x emits fine-grained progress events and reports the end
            // of a turn as session.execution.succeeded — there is no
            // session.idle and no session.status any more (verified against
            // 2.2.5). Older builds used session.idle / session.status with
            // status.type === 'idle', so keep those as fallbacks. Sub-agents
            // finish too, hence the debounce.
            const TURN_EVENTS = new Set([
              'session.execution.succeeded', // 2.2.x
              'session.idle',                // 1.x / early 2.x
              'session.status',              // mid 2.x
            ]);
            const TURN_DEBOUNCE_MS = 2000;
            const lastTurnAt = new Map();
            // 会话标题与最近一次用户输入：随 turn_finished 上报，否则通知
            // 只能显示「OpenCode 回复完成 / 点击跳转回 OpenCode」这类空话。
            const sessionTitles = new Map();
            const lastPrompt = new Map();
            // 会话目录（事件顶层 location.directory）：应用侧据此定位项目与终端。
            const sessionDirs = new Map();
            const eventController = new AbortController();
            void (async () => {
              try {
                for await (const event of ctx.event.subscribe({ signal: eventController.signal })) {
                  const d = event.data || {};
                  const sid = d.sessionID || d.session_id || '';
                  if (sid && event.location && event.location.directory) {
                    sessionDirs.set(sid, event.location.directory);
                  }
                  if (sid) {
                    if ((event.type === 'session.renamed' || event.type === 'session.created')
                        && typeof d.title === 'string' && d.title) {
                      sessionTitles.set(sid, d.title);
                    } else if (event.type === 'session.inbox.enqueued') {
                      const text = d.item && d.item.payload && d.item.payload.text;
                      if (typeof text === 'string' && text) lastPrompt.set(sid, text);
                    }
                  }
                  if (!TURN_EVENTS.has(event.type)) continue;
                  if (event.type === 'session.status' && (!d.status || d.status.type !== 'idle')) continue;
                  if (!alertsEnabled('turn')) continue;
                  const sessionID = d.sessionID || d.session_id
                    || (d.info && (d.info.id || d.info.sessionID)) || 'unknown';
                  const now = Date.now();
                  if (now - (lastTurnAt.get(sessionID) || 0) < TURN_DEBOUNCE_MS) continue;
                  lastTurnAt.set(sessionID, now);
                  if (lastTurnAt.size > 64) lastTurnAt.clear();
                  await sendToIsland({
                    provider: 'opencode', event: 'turn_finished',
                    session_id: sessionID, timestamp: new Date().toISOString(),
                    payload: {
                      title: sessionTitles.get(sessionID) || '',
                      prompt: lastPrompt.get(sessionID) || '',
                      directory: sessionDirs.get(sessionID) || '',
                      // 插件所在的进程：应用侧据此判定这一轮是终端 TUI、
                      // 浏览器（`opencode serve`）还是桌面端服务——三者事件一样。
                      pid: process.pid
                    }
                  });
                }
              } catch { /* stream closed with the plugin */ }
            })();
          },
          async server(input) {
            if (entryClaimed) return;
            entryClaimed = true;
            const directory = (input && input.directory) || '';
            const client = input && input.client;
            return {
              // 宿主不 await 这个钩子。提问的等待另起任务，避免堵住事件总线。
              event(payload) {
                void handleV1Event(payload && payload.event, client, directory);
              },
              "tool.execute.after": async (toolInput) => {
                try {
                  const name = toolInput && toolInput.tool;
                  if (!TODO_TOOL_NAMES.has(name)) return;
                  const todos = normaliseTodos(toolInput && toolInput.args);
                  if (!todos.length) return;
                  await sendToIsland({
                    provider: 'opencode', event: 'todo_updated',
                    session_id: (toolInput && toolInput.sessionID) || 'unknown',
                    timestamp: new Date().toISOString(),
                    payload: { todos }
                  });
                } catch { /* 待办只是过程可视化，绝不影响工具本身 */ }
              },
            };
          },
        };
        """
}
