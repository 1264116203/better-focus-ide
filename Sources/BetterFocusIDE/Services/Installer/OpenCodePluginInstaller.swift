// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 安装 / 卸载 OpenCode 插件，把提问、权限评估、会话空闲（轮次完成）等事件
/// 通过 Unix socket 转发到 BetterFocusIDE 灵动岛。
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
        // 1. Questions: OpenCode's `question` tool blocks on a TUI form, so a
        //    plugin cannot "answer" it directly. This takes over the tool's
        //    execution: forwards the question to the island's socket, waits for
        //    the answer file, returns the choice as the tool result. When the
        //    island is unreachable the original execution runs (TUI still works).
        // 2. Permissions: `permission.evaluate` runs after rules and before the
        //    prompt; forwards to the island and rewrites effect to allow/deny.
        // 3. Turn finished: on session idle, pops the "reply done" notice.
        //
        // Answer files:
        //   __ANSWER_DIR__/<session>_<id>.json            (questions)
        //   __ANSWER_DIR__/<session>_perm-<requestID>.json (permissions)
        // carrying { answer_index, answer_label }; -1 = timeout, -2 = custom.

        import { Plugin } from '@opencode/plugin';
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

        function answerPath(sessionID, requestID, questionID) {
          return requestID
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
              if (got.timedOut) return { answers, resolved: false };
              if (got.labels.length) answers[i] = got.labels;
            }
            if (pending === 0) return { answers, resolved: true };
            await sleep(POLL_MS);
          }
          return { answers, resolved: false };
        }

        export default Plugin.define({
          id: 'betterfocus-notify',
          async setup(ctx) {
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
                  const { answers, resolved } = await awaitAnswers(
                    questions, sessionID, requestID, Date.now());
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
                      directory: sessionDirs.get(sessionID) || ''
                    }
                  });
                }
              } catch { /* stream closed with the plugin */ }
            })();
          }
        });
        """
}
