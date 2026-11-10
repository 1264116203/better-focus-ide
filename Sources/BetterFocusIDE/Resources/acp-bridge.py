#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# BetterFocusIDE ACP stdio bridge.
#
# JetBrains 把代理命令换成这个脚本。脚本再拉起原来的 agent，两边的
# JSON-RPC 按行原样转发。岛上的卡片只看从这些报文里译出来的事件：
# 回合完成、权限提醒、提问提醒、待办、失败、子任务、压缩、会话结束。
# 权限和提问都不代答——IDE 自己的对话框还在等那一帧 JSON-RPC 响应。

import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

SOCKET_PATH = os.environ.get("BETTERFOCUS_SOCKET") or os.path.expanduser(
    "~/Library/Application Support/BetterFocusIDE/agent-events.sock")
SETTINGS_PATH = os.environ.get("BETTERFOCUS_SETTINGS") or os.path.expanduser(
    "~/Library/Application Support/BetterFocusIDE/settings.json")
SIDECAR_PATH = os.environ.get("BETTERFOCUS_ACP_SIDECAR") or os.path.expanduser(
    "~/Library/Application Support/BetterFocusIDE/acp-bridge.json")

SKIP_COMM = frozenset(("sh", "bash", "zsh", "fish", "dash", "ksh", "csh",
                       "tcsh", "nu", "xonsh", "env", "python", "python3"))
OVERWRITE_TOOLS = frozenset(("todowrite", "todo_write", "settodolist"))
UPSERT_TOOLS = frozenset(("taskcreate", "taskupdate"))
QUESTION_TOOLS = frozenset(("askuserquestion", "ask_user_question"))
TURN_REASONS = frozenset(("end_turn", "max_tokens", "max_turn_requests", "cancelled"))
FAIL_REASONS = frozenset(("error", "refusal"))
BUNDLE_PRODUCT = {
    "com.todesktop.230313mzl4w4u92": "cursor",
    "com.cursor": "cursor",
    "ai.opencode.desktop": "opencode",
    "com.tencent.workbuddy.mac": "workbuddy",
    "ai.workbuddy": "workbuddy",
    "com.workbuddy.workbuddy-ai": "workbuddy",
    "com.qoder.app": "qoder",
    "com.qoder.ide": "qoder_ide",
    "com.aliyun.lingma.ide": "qoder_cn_ide",
    "com.anthropic.claudefordesktop": "claude_code",
    "com.openai.codex": "codex",
    "cn.trae.app": "trae_cn",
    "com.trae.app": "trae",
    "com.moonshot.kimichat.kmp.mac": "kimi",
    "com.github.githubapp": "copilot",
}


def alerts_enabled(kind):
    keys = {"question": ("questionEnabled", "question_enabled"),
            "permission": ("permissionEnabled", "permission_enabled"),
            "turn": ("turnNotifyEnabled", "turn_notify_enabled")}.get(kind)
    if not keys:
        return True
    try:
        with open(SETTINGS_PATH) as handle:
            values = (json.load(handle) or {}).get("values", {})
        for key in keys:
            if key in values:
                return values[key] is not False
    except Exception:
        return True
    return True


def send(message):
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(1.0)
        client.connect(SOCKET_PATH)
        client.sendall((json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8"))
        client.close()
    except Exception:
        return


def _app_path(comm):
    marker = ".app/Contents/MacOS/"
    idx = comm.find(marker)
    if idx == -1:
        return ""
    return comm[:idx + len(".app")]


def _bundle_identity(app_path):
    info = os.path.join(app_path, "Contents", "Info.plist")
    try:
        import plistlib
        with open(info, "rb") as handle:
            plist = plistlib.load(handle)
        return (plist.get("CFBundleIdentifier", "") or "",
                plist.get("CFBundleName", "") or "")
    except Exception:
        return ("", "")


def host_app():
    override = os.environ.get("BETTERFOCUS_ACP_HOST")
    if override:
        try:
            parsed = json.loads(override)
            if isinstance(parsed, dict):
                return {"bundle": parsed.get("bundle") or "",
                        "name": parsed.get("name") or "",
                        "path": parsed.get("path") or ""}
        except Exception:
            pass
    pid = os.getpid()
    for _hop in range(16):
        try:
            ppid = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                                  capture_output=True, timeout=2).stdout.decode().strip()
        except Exception:
            break
        if not ppid.isdigit():
            break
        pid = int(ppid)
        if pid <= 1:
            break
        try:
            comm = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)],
                                  capture_output=True, timeout=2).stdout.decode().strip()
        except Exception:
            break
        if not comm or os.path.basename(comm) in SKIP_COMM:
            continue
        app_path = _app_path(comm)
        if not app_path:
            continue
        bundle, name = _bundle_identity(app_path)
        return {"bundle": bundle, "name": name, "path": app_path}
    bundle = os.environ.get("__CFBundleIdentifier") or ""
    return {"bundle": bundle, "name": "", "path": ""}


def product_for(bundle):
    if bundle.startswith("com.jetbrains."):
        return "jetbrains_plugin"
    return BUNDLE_PRODUCT.get(bundle, "unknown")


def text_of(value, limit=200):
    if not isinstance(value, str):
        return ""
    text = " ".join(value.split())
    return text[:limit]


def prompt_text(params):
    prompt = params.get("prompt")
    if isinstance(prompt, str):
        return text_of(prompt)
    if isinstance(prompt, list):
        parts = []
        for block in prompt:
            if isinstance(block, dict):
                part = block.get("text") or ""
                if isinstance(part, str) and part.strip():
                    parts.append(part)
            elif isinstance(block, str):
                parts.append(block)
        return text_of(" ".join(parts))
    return ""


def session_id_of(obj):
    if not isinstance(obj, dict):
        return ""
    for key in ("sessionId", "session_id"):
        value = obj.get(key)
        if value:
            return str(value)
    return ""


def tool_name(tool):
    if not isinstance(tool, dict):
        return ""
    for key in ("name", "title", "kind"):
        value = tool.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def normalise_item(raw, fallback_id):
    if isinstance(raw, str):
        content = text_of(raw, 500)
        if not content:
            return None
        return {"id": fallback_id, "content": content, "status": "pending"}
    if not isinstance(raw, dict):
        return None
    content = ""
    for key in ("content", "title", "subject", "text", "step"):
        value = raw.get(key)
        if isinstance(value, str) and value.strip():
            content = text_of(value, 500)
            break
    if not content:
        return None
    status = raw.get("status") or raw.get("state") or "pending"
    item_id = raw.get("id") or raw.get("taskId") or raw.get("task_id") or fallback_id
    return {"id": str(item_id), "content": content, "status": str(status)}


def normalise_list(raw, prefix):
    items = []
    for index, entry in enumerate(raw or []):
        item = normalise_item(entry, "%s:%d" % (prefix, index))
        if item:
            items.append(item)
    return items


class Bridge:
    def __init__(self):
        self.lock = threading.Lock()
        self.host = host_app()
        self.product = product_for(self.host.get("bundle") or "")
        self.pending = {}
        self.sessions = {}
        self.tools = {}
        self.seen = set()

    def observe(self, direction, message):
        with self.lock:
            return self._observe(direction, message)

    def finish(self):
        with self.lock:
            events = []
            for session_id in list(self.sessions):
                events.append(self._event("session_ended", session_id, {}))
            self.sessions.clear()
            return events

    def _session(self, session_id):
        state = self.sessions.get(session_id)
        if state is None:
            state = {"cwd": "", "prompt": "", "title": "", "turn_open": False,
                     "queue": []}
            self.sessions[session_id] = state
        return state

    def _event(self, name, session_id, payload):
        state = self.sessions.get(session_id) or {}
        return {
            "provider": "acp",
            "product": self.product,
            "event": name,
            "session_id": session_id or "unknown",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "host": self.host,
            "cwd": state.get("cwd") or os.getcwd(),
            "payload": payload,
        }

    def _once(self, key):
        if key in self.seen:
            return False
        self.seen.add(key)
        return True

    def _observe(self, direction, message):
        if not isinstance(message, dict):
            return []
        method = message.get("method") or ""
        if direction == "client" and method:
            return self._client_request(message, method)
        if direction == "agent" and method:
            return self._agent_message(message, method)
        if "id" in message and "method" not in message:
            return self._response(message)
        return []

    def _client_request(self, message, method):
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        request_id = message.get("id")
        if method in ("session/new", "session/load"):
            if request_id is not None:
                self.pending[str(request_id)] = {
                    "method": method,
                    "cwd": params.get("cwd") or "",
                    "session_id": session_id_of(params),
                }
            return []
        if method == "session/prompt":
            session_id = session_id_of(params) or "unknown"
            state = self._session(session_id)
            text = prompt_text(params)
            if text:
                state["prompt"] = text
            if isinstance(params.get("cwd"), str) and params["cwd"]:
                state["cwd"] = params["cwd"]
            state["turn_open"] = True
            if request_id is not None:
                self.pending[str(request_id)] = {"method": method, "session_id": session_id}
            return []
        if method in ("session/close", "session/delete"):
            session_id = session_id_of(params)
            if session_id and session_id in self.sessions:
                event = self._event("session_ended", session_id, {})
                self.sessions.pop(session_id, None)
                return [event]
        return []

    def _response(self, message):
        pending = self.pending.pop(str(message.get("id")), None)
        if not pending:
            return []
        result = message.get("result") if isinstance(message.get("result"), dict) else {}
        method = pending.get("method")
        if method in ("session/new", "session/load"):
            session_id = session_id_of(result) or pending.get("session_id") or ""
            if not session_id:
                return []
            state = self._session(session_id)
            if pending.get("cwd"):
                state["cwd"] = pending["cwd"]
            return []
        if method == "session/prompt":
            reason = result.get("stopReason") or result.get("stop_reason")
            return self._finish_turn(pending.get("session_id") or "unknown", reason, result)
        return []

    def _agent_message(self, message, method):
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        if method == "session/update":
            return self._session_update(params)
        if method in ("session/request_permission", "session/requestPermission"):
            return self._permission(params)
        return []

    def _session_update(self, params):
        session_id = session_id_of(params) or "unknown"
        update = params.get("update") if isinstance(params.get("update"), dict) else params
        kind = update.get("sessionUpdate") or update.get("session_update") or ""
        state = self._session(session_id)
        if kind == "session_info_update":
            title = text_of(update.get("title") or "", 80)
            if title:
                state["title"] = title
            return []
        if kind == "state_update":
            return self._state_update(session_id, update)
        if kind in ("plan_update", "plan"):
            return self._plan(session_id, update)
        if kind == "plan_removed":
            return [self._event("todo_cleared", session_id, {})]
        if kind in ("tool_call", "tool_call_update"):
            return self._tool(session_id, update)
        if kind in ("compaction_update", "compaction"):
            return self._compact(session_id, update)
        if kind == "subagent_update":
            return self._subagent(session_id, update)
        if kind == "notice":
            return self._notice(session_id, update)
        return []

    def _state_update(self, session_id, update):
        nested = update.get("state") if isinstance(update.get("state"), dict) else None
        body = nested or update
        phase = body.get("state") if nested else update.get("state")
        if phase != "idle":
            return []
        reason = body.get("stopReason") or body.get("stop_reason")
        return self._finish_turn(session_id, reason, body)

    def _finish_turn(self, session_id, reason, detail):
        if not isinstance(reason, str) or not reason:
            return []
        state = self._session(session_id)
        if not state.get("turn_open"):
            return []
        if reason in FAIL_REASONS:
            if not alerts_enabled("turn"):
                state["turn_open"] = False
                return []
            state["turn_open"] = False
            error = detail.get("error") if isinstance(detail.get("error"), dict) else {}
            body = text_of(error.get("message") or detail.get("message") or reason, 180)
            return [self._event("failure_notice", session_id, {
                "title": "这一轮没有完成",
                "body": body or reason,
            })]
        if reason not in TURN_REASONS:
            return []
        if not alerts_enabled("turn"):
            state["turn_open"] = False
            return []
        state["turn_open"] = False
        payload = {"transcript_path": ""}
        if state.get("title"):
            payload["title"] = state["title"]
        if state.get("prompt"):
            payload["prompt"] = state["prompt"]
        return [self._event("turn_finished", session_id, payload)]

    def _plan(self, session_id, update):
        plan = update.get("plan") if isinstance(update.get("plan"), dict) else update
        entries = plan.get("entries")
        if not isinstance(entries, list):
            return []
        plan_id = str(plan.get("planId") or plan.get("plan_id") or session_id)
        items = normalise_list(entries, plan_id)
        if not items:
            return [self._event("todo_cleared", session_id, {})]
        return [self._event("todo_updated", session_id, {"todos": items})]

    def _tool(self, session_id, update):
        tool_id = str(update.get("toolCallId") or update.get("tool_call_id") or "")
        known = self.tools.get(tool_id, {})
        name = tool_name(update) or known.get("name") or ""
        raw = update.get("rawInput") if isinstance(update.get("rawInput"), dict) else known.get("raw")
        if tool_id:
            self.tools[tool_id] = {"name": name, "raw": raw if isinstance(raw, dict) else {}}
        folded = name.replace(" ", "").lower()
        if folded in OVERWRITE_TOOLS and isinstance(raw, dict):
            items = []
            found = False
            for key in ("todos", "tasks", "items"):
                if isinstance(raw.get(key), list):
                    found = True
                    items = normalise_list(raw[key], tool_id or session_id)
                    break
            if not found:
                return []
            if raw.get("merge") is True:
                return [self._event("todo_item_updated", session_id, {"todo": item})
                        for item in items]
            if not items:
                return [self._event("todo_cleared", session_id, {})]
            return [self._event("todo_updated", session_id, {"todos": items})]
        if folded in UPSERT_TOOLS and isinstance(raw, dict):
            return self._upsert(session_id, folded, raw)
        return []

    def _upsert(self, session_id, folded, raw):
        state = self._session(session_id)
        content = ""
        for key in ("subject", "content", "title"):
            value = raw.get(key)
            if isinstance(value, str) and value.strip():
                content = text_of(value, 500)
                break
        task_id = str(raw.get("taskId") or raw.get("task_id") or raw.get("id") or "").strip()
        status = str(raw.get("status") or ("pending" if folded == "taskcreate" else ""))
        if content and not task_id:
            state["queue"].append(content)
            item = normalise_item({"content": content, "status": status or "pending"},
                                  "task:%d" % len(state["queue"]))
            return [self._event("todo_item_updated", session_id, {"todo": item})] if item else []
        if task_id and not content and state["queue"]:
            content = state["queue"].pop(0)
        if not content and not task_id:
            return []
        item = normalise_item({
            "id": task_id or content,
            "content": content or task_id,
            "status": status or "pending",
        }, task_id or session_id)
        if not item:
            return []
        return [self._event("todo_item_updated", session_id, {"todo": item})]

    def _permission(self, params):
        session_id = session_id_of(params) or "unknown"
        tool = params.get("toolCall") if isinstance(params.get("toolCall"), dict) else {}
        name = tool_name(tool)
        raw = tool.get("rawInput") if isinstance(tool.get("rawInput"), dict) else {}
        folded = name.replace(" ", "").lower()
        detail = ""
        for key in ("command", "file_path", "path", "url", "query", "pattern", "question"):
            value = raw.get(key)
            if isinstance(value, str) and value.strip():
                detail = text_of(value, 400)
                break
        if not detail and raw:
            try:
                detail = json.dumps(raw, ensure_ascii=False)[:400]
            except Exception:
                detail = ""
        request_id = str(tool.get("toolCallId") or tool.get("tool_call_id") or name or "permission")
        if folded in QUESTION_TOOLS or "questions" in raw:
            if not alerts_enabled("question"):
                return []
            question = ""
            questions = raw.get("questions")
            if isinstance(questions, list) and questions:
                first = questions[0]
                if isinstance(first, dict):
                    question = text_of(first.get("question") or first.get("header") or "", 180)
                elif isinstance(first, str):
                    question = text_of(first, 180)
            return [self._event("question_notice", session_id, {
                "title": question or name or "需要你的回答",
                "body": detail,
            })]
        if not alerts_enabled("permission"):
            return []
        if not self._once("permission:" + session_id + ":" + request_id):
            return []
        return [self._event("permission_notice", session_id, {
            "request_id": request_id,
            "tool_name": name,
            "tool_input": raw,
            "resources": [detail] if detail else [],
            "flavor": "permission",
        })]

    def _compact(self, session_id, update):
        if not alerts_enabled("turn"):
            return []
        status = str(update.get("status") or "")
        title = "即将压缩上下文" if status in ("", "pending", "in_progress", "running") else "上下文已压缩"
        compact_id = str(update.get("compactionId") or update.get("compaction_id") or title)
        if not self._once("compact:" + session_id + ":" + compact_id + ":" + title):
            return []
        return [self._event("compact_notice", session_id, {"title": title, "body": ""})]

    def _subagent(self, session_id, update):
        if not alerts_enabled("turn"):
            return []
        nested = update.get("state") if isinstance(update.get("state"), dict) else {}
        phase = nested.get("state") or update.get("status") or ""
        reason = nested.get("stopReason") or update.get("stopReason")
        if phase not in ("idle", "completed", "done") and reason not in TURN_REASONS:
            return []
        child = str(update.get("sessionId") or update.get("session_id") or "")
        if not self._once("subagent:" + session_id + ":" + child):
            return []
        title = text_of(update.get("title") or "", 80) or "子任务完成"
        return [self._event("subagent_finished", session_id, {"title": title, "body": ""})]

    def _notice(self, session_id, update):
        if not alerts_enabled("turn"):
            return []
        if str(update.get("severity") or "").lower() not in ("error", "warning"):
            return []
        title = text_of(update.get("title") or "", 80) or "这一轮没有完成"
        body = text_of(update.get("description") or "", 180)
        if not self._once("notice:" + session_id + ":" + title + ":" + body):
            return []
        return [self._event("failure_notice", session_id, {"title": title, "body": body})]


def pump(direction, source, sink, bridge):
    try:
        while True:
            line = source.readline()
            if not line:
                break
            if sink is not None:
                sink.write(line)
                sink.flush()
            try:
                message = json.loads(line.decode("utf-8"))
            except Exception:
                continue
            try:
                events = bridge.observe(direction, message)
            except Exception:
                continue
            for event in events:
                send(event)
    finally:
        # IDE 关掉 stdin 后必须让 agent 也看到 EOF，否则它会一直等下一条报文。
        if sink is not None and sink is not sys.stdout.buffer:
            try:
                sink.close()
            except Exception:
                pass


def agent_short_name(agent_id):
    short = agent_id or ""
    for prefix in ("acp.registry.", "acp."):
        if short.startswith(prefix):
            return short[len(prefix):]
    return short


def resolve_cmd(agent_id, cmd):
    """登记里的 cmd 是相对代理解压目录的，例如 ./dist-package/cursor-agent。

    IDE 拉起桥时，工作目录是项目目录，不是那份缓存。相对路径要在
    ~/Library/Caches/JetBrains/<IDE>/acp-agents/<名字>/<版本>/ 下找。
    """
    if not cmd:
        return cmd
    if os.path.isabs(cmd) and os.path.isfile(cmd):
        return cmd
    rel = cmd[2:] if cmd.startswith("./") or cmd.startswith(".\\") else cmd
    cache = os.environ.get("BETTERFOCUS_ACP_CACHE") or os.path.expanduser(
        "~/Library/Caches/JetBrains")
    short = agent_short_name(agent_id)
    found = []
    if not short or not os.path.isdir(cache):
        return cmd
    try:
        ide_names = os.listdir(cache)
    except OSError:
        return cmd
    for ide in ide_names:
        base = os.path.join(cache, ide, "acp-agents", short)
        if not os.path.isdir(base):
            continue
        roots = [base]
        try:
            for name in os.listdir(base):
                path = os.path.join(base, name)
                if os.path.isdir(path):
                    roots.append(path)
        except OSError:
            continue
        for root in roots:
            full = os.path.normpath(os.path.join(root, rel))
            if os.path.isfile(full):
                found.append(full)
    if not found:
        return cmd
    found.sort(key=lambda path: os.path.getmtime(path))
    return found[-1]


def load_target(agent_id):
    with open(SIDECAR_PATH) as handle:
        agents = (json.load(handle) or {}).get("agents") or {}
    record = agents.get(agent_id) or {}
    cmd = record.get("cmd") or ""
    args = record.get("args") or []
    if not cmd or not isinstance(args, list):
        raise SystemExit("acp bridge: 没有 %s 的原始命令" % agent_id)
    resolved = resolve_cmd(agent_id, cmd)
    if not os.path.isfile(resolved):
        raise SystemExit("acp bridge: 找不到 %s 的代理程序 %s" % (agent_id, cmd))
    return resolved, [str(item) for item in args]


def serve(agent_id, extra):
    cmd, args = load_target(agent_id)
    env = os.environ.copy()
    env["BETTERFOCUS_ACP_BRIDGE"] = "1"
    env.pop("BETTERFOCUS_ACP_HOST", None)
    child = subprocess.Popen([cmd, *args, *extra], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=None, env=env)
    bridge = Bridge()

    def stop(signum, _frame):
        if child.poll() is None:
            child.send_signal(signum)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    outgoing = threading.Thread(target=pump, args=("client", sys.stdin.buffer, child.stdin, bridge))
    incoming = threading.Thread(target=pump, args=("agent", child.stdout, sys.stdout.buffer, bridge))
    outgoing.daemon = True
    incoming.daemon = True
    outgoing.start()
    incoming.start()
    code = child.wait()
    if child.stdin:
        try:
            child.stdin.close()
        except Exception:
            pass
    outgoing.join(timeout=1)
    incoming.join(timeout=1)
    for event in bridge.finish():
        send(event)
    return code


def check():
    bridge = Bridge()
    for line in sys.stdin.buffer:
        try:
            item = json.loads(line.decode("utf-8"))
        except Exception:
            continue
        direction = item.get("direction")
        if direction == "exit":
            events = bridge.finish()
        else:
            events = bridge.observe(direction, item.get("message"))
        for event in events:
            sys.stdout.buffer.write((json.dumps(event, ensure_ascii=False) + "\n").encode("utf-8"))
            sys.stdout.buffer.flush()


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--check":
        check()
        return 0
    if len(sys.argv) < 2:
        sys.stderr.write("acp bridge: 缺少代理 id\n")
        return 64
    return serve(sys.argv[1], sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main() or 0)
