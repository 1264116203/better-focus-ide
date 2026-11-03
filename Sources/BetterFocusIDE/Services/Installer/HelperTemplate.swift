// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Qoder hook（`betterfocus-hook.py`）的内嵌 Python 正文。
///
/// 从 stdin 读取 hook 载荷，判断触发的是哪个事件，通过 Unix socket 转发给
/// 灵动岛，轮询应答文件，并在 stdout 打印 Qoder 读取的决策结果。不依赖 `jq`：
/// 仅需 python3。
///
/// 路径 / 超时占位符（`__SOCKET_PATH__` 等）在安装时替换，使脚本指向本构建的命名空间。
enum HelperTemplate {
    static let body = """
        #!/usr/bin/env python3
        # BetterFocusIDE <-> Qoder hook body.
        #
        # Serves the hook events Qoder fires for us:
        #   - PermissionRequest: a tool call needs the person's approval and the
        #     platform waits for our answer, so the island shows Allow / Always /
        #     Reject. This is the permission channel.
        #   - PreToolUse: fired for every tool call; the platform does NOT wait
        #     for its answer. Only AskUserQuestion is handled here (older builds
        #     enter the question flow through it); anything else exits silently.
        #   - Stop: the main agent finished a turn. Pops the "reply done" notice
        #     and must exit 0 printing nothing.
        #   - SessionEnd: the session ended / was interrupted; the island takes
        #     down any leftover card.
        import json
        import os
        import socket
        import subprocess
        import sys
        import time

        SOCKET_PATH = os.environ.get("BETTERFOCUS_SOCKET_PATH") or "__SOCKET_PATH__"
        ANSWER_DIR = os.environ.get("BETTERFOCUS_ANSWER_DIR") or "__ANSWER_DIR__"
        SETTINGS_PATH = os.environ.get("BETTERFOCUS_SETTINGS_PATH") or "__SETTINGS_PATH__"
        QUESTION_TIMEOUT = int(os.environ.get("BETTERFOCUS_QUESTION_TIMEOUT", "__QUESTION_TIMEOUT__"))
        PERMISSION_TIMEOUT = int(os.environ.get("BETTERFOCUS_PERMISSION_TIMEOUT", "__PERMISSION_TIMEOUT__"))

        # Permission modes where the platform already auto-approves; don't raise
        # a card for something the machine has already decided.
        AUTO_MODES = ("accept_edits", "acceptEdits", "auto",
                      "bypass_permissions", "bypassPermissions", "yolo", "dont_ask")

        # Bundles that mean "running in a terminal, no GUI window to jump back to".
        TERMINAL_BUNDLES = (
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
            "com.github.wez.wezterm", "com.microsoft.VSCode",
        )


        def alerts_enabled(kind):
            key = {"question": "question_enabled", "permission": "permission_enabled",
                   "turn": "turn_notify_enabled"}.get(kind)
            if not key:
                return True
            try:
                with open(SETTINGS_PATH) as f:
                    parsed = json.load(f)
                values = (parsed or {}).get("values", {})
                if key not in values:
                    return True
                return values[key] is not False
            except Exception:
                return True


        def send(message):
            # Fire-and-forget: the answer comes back through the answer files.
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(SOCKET_PATH)
                s.sendall((json.dumps(message) + "\\n").encode("utf-8"))
                s.close()
                return True
            except Exception:
                return False


        def emit(decision, reason, event="PermissionRequest"):
            json.dump({"hookSpecificOutput": {
                "hookEventName": event,
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }}, sys.stdout)
            sys.stdout.write("\\n")
            sys.stdout.flush()


        def safe_id(value):
            return "".join(c if c.isalnum() or c in "-_." else "_" for c in str(value or ""))[:80]


        def answer_names(session_id, request_id, question_id):
            names = []
            if request_id:
                names.append("%s_%s_%s.json" % (session_id, request_id, question_id))
            names.append("%s_%s.json" % (session_id, question_id))
            return names


        def read_answer(session_id, request_id, question_id, since):
            for name in answer_names(session_id, request_id, question_id):
                path = os.path.join(ANSWER_DIR, name)
                try:
                    if os.path.getmtime(path) < since - 1:
                        continue
                    with open(path) as f:
                        data = json.load(f)
                except Exception:
                    continue
                if data.get("request_id") and request_id and data["request_id"] != request_id:
                    continue
                try:
                    os.remove(path)
                except OSError:
                    pass
                index = data.get("answer_index", -1)
                if not isinstance(index, int):
                    index = -1
                return (True, data.get("answer_label") or "", index)
            return (False, "", -1)


        def normalise(tool_input):
            raw = tool_input.get("questions") if isinstance(tool_input, dict) else None
            if not isinstance(raw, list) or not raw:
                raw = [tool_input] if isinstance(tool_input, dict) else []
            questions = []
            for i, q in enumerate(raw):
                if not isinstance(q, dict):
                    continue
                options = []
                for o in (q.get("options") or []):
                    if isinstance(o, str):
                        options.append({"label": o, "description": ""})
                    elif isinstance(o, dict):
                        options.append({"label": o.get("label") or "",
                                        "description": o.get("description") or ""})
                multi = q.get("multiSelect")
                if multi is None:
                    multi = q.get("multi_select")
                questions.append({
                    "id": q.get("id") or ("q" + str(i + 1)),
                    "header": q.get("header") or "Question",
                    "question": q.get("question") or "",
                    "multiSelect": multi is True,
                    "options": options,
                })
            return questions


        def host_app():
            # Walk the parent-process chain, skipping shells, to the outermost
            # .app so a turn-finished notice knows which IDE to jump back to.
            # 与 vorssaint 保持一致：返回父进程链中第一个 .app（真实宿主），不做过滤。
            pid = os.getpid()
            bundle, name, path = "", "", ""
            for _ in range(16):
                try:
                    comm = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)],
                                          capture_output=True, timeout=2).stdout.decode().strip()
                    ppid = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                                          capture_output=True, timeout=2).stdout.decode().strip()
                except Exception:
                    break
                app_path = _app_path(comm)
                if app_path:
                    bundle, name = _bundle_identity(app_path)
                    path = app_path
                    break
                if not ppid or ppid == "1" or ppid == str(pid):
                    break
                pid = ppid
            return {"bundle": bundle, "name": name, "path": path}


        def _app_path(comm):
            if not comm or "/" not in comm:
                return ""
            marker = ".app/"
            idx = comm.find(marker)
            if idx == -1:
                return ""
            return comm[:idx + len(marker) - 1]


        def _bundle_identity(app_path):
            info = os.path.join(app_path, "Contents", "Info.plist")
            try:
                import plistlib
                with open(info, "rb") as f:
                    pl = plistlib.load(f)
                return (pl.get("CFBundleIdentifier", ""), pl.get("CFBundleName", ""))
            except Exception:
                return ("", "")


        def run_question(payload, session_id, questions):
            request_id = safe_id(payload.get("request_id") or ("q" + str(int(time.time()))))
            send({"provider": "qoder", "event": "question_requested",
                  "session_id": session_id, "request_id": request_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"questions": questions, "request_id": request_id}})
            since = time.time()
            deadline = since + QUESTION_TIMEOUT
            while time.time() < deadline:
                lines, answered, timed_out = [], 0, False
                for q in questions:
                    found, label, index = read_answer(session_id, request_id, q["id"], since)
                    if found and index == -1:
                        timed_out = True
                    elif found:
                        answered += 1
                    lines.append("  - %s: %s" % (q["header"], label))
                if timed_out:
                    break
                if answered == len(questions) and questions:
                    emit("deny", "The person answered on the BetterFocusIDE island. "
                         "Use these answers and continue.\\n" + "\\n".join(lines))
                    return
                time.sleep(1)
            send({"provider": "qoder", "event": "question_timeout", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"question_id": questions[0]["id"] if questions else "q1",
                              "request_id": request_id}})
            emit("deny", "The person left the island question unanswered. Continue without it.")


        def run_permission(payload, session_id):
            request_id = safe_id(payload.get("tool_use_id") or payload.get("request_id")
                                 or ("p" + str(int(time.time()))))
            tool_input = payload.get("tool_input") or {}
            host = host_app()
            send({"provider": "qoder", "event": "permission_requested", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "host": host,
                  "payload": {"request_id": request_id,
                              "tool_name": payload.get("tool_name") or "",
                              "tool_input": tool_input, "flavor": "permission"}})
            since = time.time()
            deadline = since + PERMISSION_TIMEOUT
            perm_name = "%s_perm-%s.json" % (session_id, request_id)
            perm_path = os.path.join(ANSWER_DIR, perm_name)
            while time.time() < deadline:
                try:
                    if os.path.getmtime(perm_path) >= since - 1:
                        with open(perm_path) as f:
                            data = json.load(f)
                        os.remove(perm_path)
                        decision = data.get("decision", "reject")
                        if decision == "once":
                            emit("allow", "Allowed once from the BetterFocusIDE island.")
                        elif decision == "always":
                            emit("allow", "Always allowed from the BetterFocusIDE island.")
                        else:
                            emit("deny", "Rejected from the BetterFocusIDE island: "
                                 + (data.get("message") or ""))
                        return
                except Exception:
                    pass
                time.sleep(0.5)
            # Island never answered: fall back to Qoder's own dialog.
            emit("ask", "BetterFocusIDE did not answer in time; ask in the Qoder dialog.")


        def emit_turn_finished(session_id, payload):
            host = host_app()
            send({"provider": "qoder", "event": "turn_finished", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "host": host, "cwd": os.getcwd(),
                  "payload": {"transcript_path": payload.get("transcript_path", "")}})


        def emit_session_ended(session_id):
            send({"provider": "qoder", "event": "session_ended", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "payload": {}})


        def main():
            try:
                payload = json.load(sys.stdin)
            except Exception:
                payload = {}
            if not isinstance(payload, dict):
                payload = {}
            session_id = payload.get("session_id") or payload.get("sessionId") or "unknown"
            event = payload.get("hook_event_name") or payload.get("hookEventName") or ""

            if event == "Stop":
                if alerts_enabled("turn"):
                    emit_turn_finished(session_id, payload)
                return  # exit 0, print nothing

            if event == "SessionEnd":
                emit_session_ended(session_id)
                return

            if event == "PermissionRequest":
                # PermissionRequest 是阻塞事件：Qoder 会等待 hook 响应。
                # AskUserQuestion 也通过此事件触发（而非 PreToolUse），
                # 因为 PreToolUse 是 fire-and-forget，平台不等待响应。
                tool_name = payload.get("tool_name") or ""
                if tool_name == "AskUserQuestion":
                    # 提问：走灵动岛问答流程
                    if not alerts_enabled("question") or not os.path.exists(SOCKET_PATH):
                        emit("allow", "BetterFocusIDE question cards are off; ask in Qoder's own dialog.")
                        return
                    questions = normalise(payload.get("tool_input") or {})
                    if questions:
                        run_question(payload, session_id, questions)
                    else:
                        emit("allow", "Nothing to ask; continue.")
                    return
                # 权限申请：走灵动岛审批流程
                if not alerts_enabled("permission"):
                    return  # fall back to platform dialog silently
                mode = str(payload.get("permission_mode") or payload.get("permissionMode") or "")
                if mode in AUTO_MODES:
                    return
                if not os.path.exists(SOCKET_PATH):
                    return
                run_permission(payload, session_id)
                return

            if event == "PreToolUse":
                # PreToolUse 是 fire-and-forget：平台不等待响应，
                # 所以不能在这里处理需要用户交互的请求。
                return


        if __name__ == "__main__":
            main()
        """
}
