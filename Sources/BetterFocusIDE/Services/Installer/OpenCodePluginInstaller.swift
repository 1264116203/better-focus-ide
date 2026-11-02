// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Installs / uninstalls the OpenCode plugin that forwards questions,
/// permission evaluations and session-idle (turn finished) events to the
/// BetterFocusIDE island over the Unix socket.
enum OpenCodePluginInstaller {
    static let pluginPath = InstallerPaths.opencodePluginPath

    static func install() throws {
        let dir = (pluginPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = pluginContent
        // Idempotent: don't rewrite identical content (keeps mtime stable).
        if let existing = try? String(contentsOfFile: pluginPath, encoding: .utf8),
           existing == content { return }
        try content.write(toFile: pluginPath, atomically: true, encoding: .utf8)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: pluginPath)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: pluginPath)
    }

    static var pluginContent: String {
        PluginTemplate.body
            .replacingOccurrences(of: "__SOCKET_PATH__", with: InstallerPaths.socketPath)
            .replacingOccurrences(of: "__ANSWER_DIR__", with: InstallerPaths.answerDir)
            .replacingOccurrences(of: "__SETTINGS_PATH__", with: InstallerPaths.settingsPath)
            .replacingOccurrences(of: "__ANSWER_TIMEOUT_MS__",
                                  with: "\(InstallerPaths.questionTimeoutSeconds * 1000)")
    }
}

/// The embedded `betterfocus-notify.js` body. Placeholders are substituted at
/// install time so the plugin points at this build's namespace.
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
          const key = kind === 'question' ? 'question_enabled'
            : (kind === 'permission' ? 'permission_enabled'
              : (kind === 'turn' ? 'turn_notify_enabled' : null));
          if (!key) return true;
          try {
            const parsed = JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
            const values = (parsed && parsed.values) || {};
            if (!(key in values)) return true;
            return values[key] !== false;
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
            if (ctx.event && ctx.event.on) {
              await ctx.event.on('session.idle', async ({ event }) => {
                if (!alertsEnabled('turn')) return;
                const sessionID = (event && event.sessionID) || (event && event.session_id) || 'unknown';
                await sendToIsland({
                  provider: 'opencode', event: 'turn_finished',
                  session_id: sessionID, timestamp: new Date().toISOString(),
                  payload: {}
                });
              });
            }
          }
        });
        """
}
