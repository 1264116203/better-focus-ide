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
        #     Reject. AskUserQuestion is answered here. Qoder IDE / Qoder CN
        #     still use this path.
        #   - PreToolUse: fired for every tool call. Qoder IDE does not wait, so
        #     ordinary tools exit immediately. Qoder.app does wait, and it asks
        #     questions here instead of PermissionRequest — AskUserQuestion on
        #     the desktop app shows the island question card and blocks until
        #     the person answers.
        #   - Notification: Qoder.app also emits permission_prompt when its own
        #     dialog appears. Question tools are not turned into a second
        #     notice if the card is already up. Other confirms stay notice-only;
        #     stdout stays empty so Qoder's own dialog is not swallowed.
        #   - PostToolUse: fired after a tool finished. Only the todo tools are
        #     handled here — the island draws the segmented progress card from
        #     the tool's own argument list (TodoWrite sends the whole table
        #     every time, so a plain overwrite is the correct semantics).
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

        # Bundles that mean "running in a terminal, no GUI window to jump back to".
        TERMINAL_BUNDLES = (
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
            "com.github.wez.wezterm", "com.microsoft.VSCode",
        )


        def alerts_enabled(kind):
            # 设置文件里 `values` 的键是驼峰（Settings 的 @Published 名），
            # 旧版 Python 实现用的是下划线键。两种都认，驼峰优先。
            keys = {"question": ("questionEnabled", "question_enabled"),
                    "permission": ("permissionEnabled", "permission_enabled"),
                    "turn": ("turnNotifyEnabled", "turn_notify_enabled")}.get(kind)
            if not keys:
                return True
            try:
                with open(SETTINGS_PATH) as f:
                    parsed = json.load(f)
                values = (parsed or {}).get("values", {})
                for key in keys:
                    if key in values:
                        return values[key] is not False
                return True
            except Exception:
                return True


        def send(message):
            # ACP 桥已经按外面那个 IDE 发过同一条通知。这里再发会多一张卡片。
            if os.environ.get("BETTERFOCUS_ACP_BRIDGE") == "1":
                return False
            # Fire-and-forget: the answer comes back through the answer files.
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(SOCKET_PATH)
                s.sendall((json.dumps(message) + "\\n").encode("utf-8"))
                s.close()
                return True
            except Exception:
                return False


        def emit(decision, reason, event="PermissionRequest", updates=None):
            # permissionDecision 是 IDE / PreToolUse 认的字段。
            # Qoder.app 的 PermissionRequest 只读 decision.behavior（allow / deny）。
            # ask 不在那个枚举里，写进去整段 stdout 会被丢掉，所以只在 allow / deny 时附上。
            # IDE 的解析器不认 decision 这个对象。附在 PermissionRequest 上时，
            # 整段 stdout 会被当成没有解析结果，卡片上的允许不会生效，
            # IDE 仍弹出自己的选择框。所以只在桌面版附上。
            # Qoder.app 的「本会话允许」只带 destination=session。
            # 写进 userSettings 会永久作用于整个 Qoder，设置里又改不掉。
            output = {
                "hookEventName": event,
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
            if (event == "PermissionRequest" and decision in ("allow", "deny")
                    and _desktop_qoder()):
                decided = {"behavior": decision}
                if decision == "deny" and reason:
                    decided["message"] = reason
                if decision == "allow" and updates:
                    decided["updatedPermissions"] = updates
                output["decision"] = decided
            json.dump({"hookSpecificOutput": output}, sys.stdout)
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
                # 岛侧判定「宿主正在前台、它自己会画提问面板」→ 放弃接管。
                if data.get("defer") is True or index == -4:
                    return (True, "", -4)
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


        # 渠道识别：这条通知是谁弹的
        # Qoder 有四种跑法（JetBrains 插件 / Qoder IDE / 终端里的 CLI / OpenCode），
        # turn_finished 只带 provider 时，岛无法知道该跳回哪个窗口 —— 在 IDEA 里用
        # 插件写的代码，点通知却弹出了 Qoder IDE。这里沿父进程链向上找到宿主 .app，
        # 把它的身份一并上报，由岛侧的 launcher 决定唤起谁。
        #
        # 为什么要跳过 shell：hook 通常经一层 sh 启动（python ← sh ← IDE）。不跳过的
        # 话看见的永远是 /bin/sh，认不出宿主；跳过之后，IDE 内终端里跑的 CLI 也会
        # 正确落到 IDE 上，与「人就在 IDE 里干活」的预期一致。
        SKIP_COMM = frozenset(("sh", "bash", "zsh", "fish", "dash", "ksh", "csh",
                               "tcsh", "nu", "xonsh", "env", "python", "python3"))


        def host_app():
            # Walk the parent-process chain, skipping shells, to the outermost
            # .app so a turn-finished notice knows which IDE to jump back to.
            # 与 vorssaint 保持一致：跳过 shell 进程，用 .app/Contents/MacOS/ 标记
            # 定位真正的宿主 IDE；找不到时回退到 __CFBundleIdentifier 环境变量。
            pid = os.getpid()
            for _hop in range(16):
                try:
                    ppid_raw = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                                              capture_output=True, timeout=2).stdout.decode().strip()
                except Exception:
                    break
                if not ppid_raw or not ppid_raw.isdigit():
                    break
                pid = int(ppid_raw)
                if pid <= 1:
                    break
                try:
                    comm = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)],
                                          capture_output=True, timeout=2).stdout.decode().strip()
                except Exception:
                    break
                if not comm:
                    break
                if os.path.basename(comm) in SKIP_COMM:
                    continue
                app_path = _app_path(comm)
                if app_path:
                    bundle, name = _bundle_identity(app_path)
                    return {"bundle": bundle, "name": name, "path": app_path}
            # 父进程链没找到：回退到 __CFBundleIdentifier（IDE 启动的进程会继承它）
            bundle = os.environ.get("__CFBundleIdentifier") or ""
            if bundle:
                return {"bundle": bundle, "name": "", "path": ""}
            return {"bundle": "", "name": "", "path": ""}


        def _app_path(comm):
            if not comm or "/" not in comm:
                return ""
            marker = ".app/Contents/MacOS/"
            idx = comm.find(marker)
            if idx == -1:
                return ""
            return comm[:idx + len(".app")]


        def _bundle_identity(app_path):
            info = os.path.join(app_path, "Contents", "Info.plist")
            try:
                import plistlib
                with open(info, "rb") as f:
                    pl = plistlib.load(f)
                return (pl.get("CFBundleIdentifier", ""), pl.get("CFBundleName", ""))
            except Exception:
                return ("", "")


        # ── Product 识别：三层决策树 ──────────────────────────────────
        # product 完全由 hook 进程启动时读取的环境变量决定，与事件 JSON 内容无关。
        # 识别结果写入 SessionState 并持久化到磁盘，后续事件从 state 读取。

        _STATE_DIR = os.path.join(os.path.expanduser("~"),
                                  "Library", "Application Support",
                                  "BetterFocusIDE", "sessions")


        # CN 发行版（Qoder CN / 通义灵码）与英文版是同一套代码，只有产品名不同。
        # 安装器在启动器里 export BETTERFOCUS_VARIANT=cn，识别结果整体换到 _cn
        # 命名空间；这样 IDE 内置、CLI、插件三种形态依然各自可辨，不会因为
        # 「一律改成 qoder_cn」而丢掉 IDE 与 CLI 的区别。
        _VARIANT = os.environ.get("BETTERFOCUS_VARIANT") or ""
        _CN_PRODUCT_MAP = {
            "qoder": "qoder_cn",
            "qoder_ide": "qoder_cn_ide",
            "qoder_cli": "qoder_cn_cli",
        }


        def _identify_product_base():
            \"\"\"通过环境变量决策树推导 product（与事件 JSON 无关）。

            优先级：
              1 - 有 QODER_PROJECT_DIR 且无 QODER_SESSION_ID：
                  Bundle 是 com.qoder.app，或 QODER_STANDALONE=1 => qoder
                  Bundle 含 jetbrains/intellij => jetbrains_plugin
                  Bundle 含 qoder / lingma => qoder_ide
                  其余 => qoder_cli
                  （Qoder.app 会注入项目目录，但不给 hook 进程会话 id。
                  只看目录会把桌面版记成无头 CLI。）
              2 - 有 QODER_SESSION_ID:
                 - QODER_STANDALONE=1 => qoder
                 - Bundle ID 含 jetbrains/intellij => jetbrains_plugin
                 - Bundle ID 含 qoder => qoder_ide
                 - 有 QODER_TRANSCRIPT_PATH（Bundle 缺失兜底）=> qoder_ide
              3 - 以上均不满足 => unknown
            \"\"\"
            project_dir = os.environ.get("QODER_PROJECT_DIR") or ""
            session_id = os.environ.get("QODER_SESSION_ID") or ""
            standalone = os.environ.get("QODER_STANDALONE") or ""
            bundle_id = (os.environ.get("QODER_BUNDLE_ID")
                         or os.environ.get("__CFBundleIdentifier")
                         or "").lower()
            transcript_path = os.environ.get("QODER_TRANSCRIPT_PATH") or ""

            # 优先级 1：有项目目录但无会话 id。
            # 桌面版 Qoder.app 走这条，不能当成无头 CLI。
            if project_dir and not session_id:
                if bundle_id == "com.qoder.app" or standalone == "1":
                    return "qoder"
                if "jetbrains" in bundle_id or "intellij" in bundle_id:
                    return "jetbrains_plugin"
                if "qoder" in bundle_id or "lingma" in bundle_id:
                    return "qoder_ide"
                return "qoder_cli"

            if session_id:
                # 优先级 2a：显式 standalone 标记 → 独立 Qoder
                if standalone == "1":
                    return "qoder"
                # 优先级 2b：Bundle ID 含 jetbrains / intellij → JetBrains 插件
                if "jetbrains" in bundle_id or "intellij" in bundle_id:
                    return "jetbrains_plugin"
                # 优先级 2c：Bundle ID 含 qoder → Qoder IDE
                if "qoder" in bundle_id:
                    return "qoder_ide"
                # 优先级 2d：有 transcript path（Bundle 缺失兜底）→ Qoder IDE
                if transcript_path:
                    return "qoder_ide"

            # 优先级 3：兜底
            return "unknown"


        def _identify_product():
            \"\"\"产品识别的最终结果：基线结果 + 发行版变体映射。\"\"\"
            product = _identify_product_base()
            if _VARIANT == "cn":
                return _CN_PRODUCT_MAP.get(product, product)
            return product


        def _state_path(session_id):
            return os.path.join(_STATE_DIR, safe_id(session_id) + ".json")


        def _load_state(session_id):
            try:
                with open(_state_path(session_id)) as f:
                    return json.load(f)
            except Exception:
                return {}


        def _save_state(session_id, state):
            try:
                os.makedirs(_STATE_DIR, exist_ok=True)
                with open(_state_path(session_id), "w") as f:
                    json.dump(state, f)
            except Exception:
                pass


        def _merge_state(session_id, new_product):
            \"\"\"合并 product 到会话状态：新值为空或 unknown 时保留磁盘上已有的值。\"\"\"
            state = _load_state(session_id)
            if new_product and new_product != "unknown":
                state["product"] = new_product
            _save_state(session_id, state)
            return state.get("product", "unknown")


        def _get_product(session_id):
            \"\"\"获取会话的 product：优先从持久化 state 读取，缺失则降级重新识别。\"\"\"
            state = _load_state(session_id)
            product = state.get("product") or ""
            if product and product != "unknown":
                return product
            # state 缺失或为 unknown → 降级再次识别
            return _identify_product()


        def _real_questions(tool_input):
            # 只认真正的 questions 数组。normalise 在缺这个字段时会把整个
            # tool_input 当成一道题，普通工具不能走这条。
            if not isinstance(tool_input, dict):
                return []
            raw = tool_input.get("questions")
            if not isinstance(raw, list) or not raw:
                inner = tool_input.get("input")
                if isinstance(inner, str):
                    try:
                        inner = json.loads(inner)
                    except Exception:
                        inner = None
                if isinstance(inner, dict):
                    raw = inner.get("questions")
            if not isinstance(raw, list) or not raw:
                return []
            questions = normalise({"questions": raw})
            return [q for q in questions if q.get("question") or q.get("options")]


        def _question_input(payload):
            raw = payload.get("tool_input")
            if raw is None:
                raw = payload.get("toolInput")
            if isinstance(raw, str):
                try:
                    raw = json.loads(raw)
                except Exception:
                    raw = {}
            return raw if isinstance(raw, dict) else {}


        def _desktop_qoder():
            # Qoder.app 的提问不走 PermissionRequest。IDE / CLI 仍走原来的通道，
            # 不能在 PreToolUse 上堵住，否则和 PermissionRequest 各开一张卡。
            product = _identify_product()
            if product in ("qoder", "qoder_cn"):
                return True
            bundle = (host_app().get("bundle") or "").lower()
            return bundle == "com.qoder.app"


        def _mark_question(session_id):
            state = _load_state(session_id)
            state["question_card"] = time.time()
            _save_state(session_id, state)


        def _question_card_recent(session_id):
            state = _load_state(session_id)
            try:
                started = float(state.get("question_card") or 0)
            except Exception:
                return False
            return started > 0 and (time.time() - started) < (QUESTION_TIMEOUT + 30)


        def publish_question(payload, session_id, questions):
            request_id = safe_id(payload.get("request_id")
                                 or payload.get("tool_use_id")
                                 or payload.get("toolUseId")
                                 or ("q" + str(int(time.time()))))
            product = _get_product(session_id)
            send({"provider": "qoder", "product": product,
                  "event": "question_requested",
                  "session_id": session_id, "request_id": request_id,
                  # 宿主身份：岛侧历史列表要写出「是哪个渠道找过我」（在 IDEA 里跑的
                  # Qoder 写 IntelliJ IDEA），点那一行也按它决定跳回哪个窗口。
                  "host": host_app(),
                  "cwd": payload.get("cwd") or "",
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"questions": questions, "request_id": request_id}})
            _mark_question(session_id)
            return request_id


        def run_question(payload, session_id, questions, event="PermissionRequest"):
            request_id = publish_question(payload, session_id, questions)
            since = time.time()
            deadline = since + QUESTION_TIMEOUT
            while time.time() < deadline:
                lines, answered, timed_out = [], 0, False
                for q in questions:
                    found, label, index = read_answer(session_id, request_id, q["id"], since)
                    if found and index == -4:
                        # 让位：宿主自带提问面板且正在前台。静默退出，把问题交回
                        # IDE 自己的对话框，避免同一道题让用户答两遍。
                        return
                    if found and index == -1:
                        timed_out = True
                    elif found:
                        answered += 1
                    lines.append("  - %s: %s" % (q["header"], label))
                if timed_out:
                    break
                if answered == len(questions) and questions:
                    emit("deny", "The person answered on the BetterFocusIDE island. "
                         "Use these answers and continue.\\n" + "\\n".join(lines),
                         event)
                    return
                time.sleep(1)
            send({"provider": "qoder", "product": product,
                  "event": "question_timeout", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"question_id": questions[0]["id"] if questions else "q1",
                              "request_id": request_id}})
            emit("deny", "The person left the island question unanswered. Continue without it.",
                 event)


        def shell_command(tool_input):
            if not isinstance(tool_input, dict):
                return ""
            value = tool_input.get("command")
            if isinstance(value, str):
                return value.strip()
            return ""


        def prefix_permission_updates(tool_name, token):
            # 前缀是「命令名:*」。destination 用 session：只在当前 Qoder 会话有效。
            # userSettings 会写进 ~/.qoder/settings.json，永久作用于整个 Qoder，
            # 设置页又没有地方把它改回去。
            name = str(token or "").strip()
            if not name:
                return []
            return [{
                "type": "addRules",
                "behavior": "allow",
                "destination": "session",
                "rules": [{
                    "toolName": tool_name or "Bash",
                    "ruleContent": name + ":*",
                }],
            }]


        # 这些命令名不能进允许名单，即使设置里已经有同名规则也不要静默放行。
        DENY_COMMANDS = {"rm", "mv", "sudo", "wget", "curl", "chown", "remove-item"}


        def session_permission_mode(payload):
            raw = payload.get("permission_mode") or payload.get("permissionMode") or ""
            return str(raw).strip().lower().replace("-", "_")


        def qoder_handles_approval(payload):
            # 自动审批是 auto，完全访问是 bypass_permissions（别名 yolo）。
            # 这两种由 Qoder 自己放行，岛上不再开权限卡。
            # 每次询问是 accept_edits，那种仍然开卡。
            return session_permission_mode(payload) in ("auto", "bypass_permissions", "yolo")


        def command_head(command):
            head = command.split(None, 1)[0] if command else ""
            if not head or any(ch in head for ch in (",", '"', "'")):
                return ""
            if head.lower() in DENY_COMMANDS:
                return ""
            return head


        def rule_covers_command(rule, command, tool_name):
            # 落盘形式是 ToolName(ruleContent)，前缀是「命令名:*」。
            if not isinstance(rule, str) or "(" not in rule or not rule.endswith(")"):
                return False
            tool, _, rest = rule.partition("(")
            content = rest[:-1]
            if tool_name and tool != tool_name:
                return False
            if content.endswith(":*"):
                prefix = content[:-2]
                if not prefix or prefix.lower() in DENY_COMMANDS:
                    return False
                return command == prefix or command.startswith(prefix + " ")
            return content == command


        def remember_session_allow(session_id, tool_name, token):
            # 只记在这份会话状态里。不写 ~/.qoder/settings.json，
            # 否则规则会永久留下，Qoder 里没有地方删。
            name = str(token or "").strip()
            if not name or name.lower() in DENY_COMMANDS:
                return
            if any(ch in name for ch in (",", '"', "'", "(", ")", "$", ";", "&", "|", "<", ">")):
                return
            rule = "%s(%s:*)" % (tool_name or "Bash", name)
            state = _load_state(session_id)
            rules = state.get("session_allow")
            if not isinstance(rules, list):
                rules = []
            if rule not in rules:
                rules.append(rule)
            state["session_allow"] = rules
            _save_state(session_id, state)


        def session_allows(session_id, command, tool_name):
            if not command_head(command):
                return False
            rules = _load_state(session_id).get("session_allow")
            if not isinstance(rules, list):
                return False
            name = tool_name or "Bash"
            return any(rule_covers_command(rule, command, name) for rule in rules)


        def permission_hold_path(session_id):
            return os.path.join(ANSWER_DIR, "perm-hold-%s.json" % safe_id(session_id))


        def remember_permission_hold(session_id, command, decision, token, tool_name):
            # PreToolUse 先拿到答案。PermissionRequest 若随后仍出现，用这份记录
            # 立刻回放，不再开第二张卡，也不让原生框一直挂着。
            path = permission_hold_path(session_id)
            body = {
                "command": command,
                "decision": decision,
                "token": token or "",
                "tool_name": tool_name or "Bash",
                "ts": time.time(),
            }
            tmp = path + ".tmp"
            try:
                os.makedirs(ANSWER_DIR, exist_ok=True)
                with open(tmp, "w") as f:
                    json.dump(body, f)
                    f.flush()
                os.replace(tmp, path)
            except Exception:
                pass


        def take_permission_hold(session_id, command):
            path = permission_hold_path(session_id)
            try:
                with open(path) as f:
                    data = json.load(f)
            except Exception:
                return None
            try:
                os.remove(path)
            except OSError:
                pass
            try:
                age = time.time() - float(data.get("ts") or 0)
            except Exception:
                return None
            if age < 0 or age > 4:
                return None
            if str(data.get("command") or "") != command:
                return None
            return data


        def read_permission_answer(session_id, request_id, since):
            path = os.path.join(ANSWER_DIR, "%s_perm-%s.json" % (session_id, request_id))
            try:
                if os.path.getmtime(path) < since - 1:
                    return None
                with open(path) as f:
                    data = json.load(f)
            except Exception:
                return None
            try:
                os.remove(path)
            except OSError:
                pass
            return data


        def permission_message(session_id, product, event, request_id, tool_name, tool_input, detail, host, cwd):
            return {"provider": "qoder", "product": product,
                    "event": event,
                    "session_id": session_id,
                    "host": host,
                    "cwd": cwd or "",
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "payload": {
                        "request_id": request_id,
                        "tool_name": tool_name,
                        "tool_input": tool_input,
                        "resources": [detail] if detail else [],
                        "flavor": "permission"}}


        def run_permission(payload, session_id, event="PermissionRequest"):
            # 终端命令（tool_input.command）等岛上的三按钮卡。
            # Qoder 的 stdout 只有 allow / deny / ask，没有「始终允许」字段。
            # 「始终允许」由岛把命令名写入界面 settings.json 和执行端 app-config.json，
            # Qoder.app 还要在 PermissionRequest 上回 allow，并带 updatedPermissions。
            # 没有 command 的权限请求只发 permission_notice，立刻回 ask。
            # 超时也回 ask，把决定权交回 Qoder 自己的对话框，不等满 hook 的 660 秒。
            tool_name = payload.get("tool_name") or payload.get("toolName") or ""
            tool_input = _question_input(payload)
            request_id = safe_id(payload.get("tool_use_id")
                                 or payload.get("toolUseId")
                                 or payload.get("request_id")
                                 or (tool_name + "-" + str(int(time.time() * 1000))))
            host = host_app()
            product = _get_product(session_id)
            command = shell_command(tool_input)

            # 桌面版已经在 PreToolUse 上答过。这里只回放，不再开卡。
            if event == "PermissionRequest" and command:
                held = take_permission_hold(session_id, command)
                if held:
                    decision = str(held.get("decision") or "")
                    if decision == "reject":
                        emit("deny", "The person rejected this command on BetterFocusIDE.")
                        return
                    updates = None
                    if decision == "always":
                        token = str(held.get("token") or "").strip()
                        name = held.get("tool_name") or tool_name
                        updates = prefix_permission_updates(name, token) or None
                    if decision in ("always", "once"):
                        emit("allow", "The person allowed this command on BetterFocusIDE.",
                             updates=updates)
                        return

            detail = command
            if not detail:
                for key in ("file_path", "path", "url", "query", "pattern"):
                    value = tool_input.get(key)
                    if isinstance(value, str) and value:
                        detail = value
                        break
            if not detail and tool_input:
                detail = json.dumps(tool_input, ensure_ascii=False)[:400]

            cwd = payload.get("cwd") or ""
            if not command:
                send(permission_message(session_id, product, "permission_notice",
                                        request_id, tool_name, tool_input, detail, host, cwd))
                emit("ask", "BetterFocusIDE only notifies about permissions; decide in Qoder's own dialog.",
                     event)
                return

            send(permission_message(session_id, product, "permission_requested",
                                    request_id, tool_name, tool_input, detail, host, cwd))
            since = time.time()
            deadline = since + PERMISSION_TIMEOUT
            while time.time() < deadline:
                data = read_permission_answer(session_id, request_id, since)
                if not data:
                    time.sleep(0.5)
                    continue
                decision = str(data.get("decision") or "")
                if decision == "reject":
                    if event == "PreToolUse":
                        remember_permission_hold(session_id, command, decision, "", tool_name)
                    emit("deny", "The person rejected this command on BetterFocusIDE.", event)
                    return
                if decision in ("always", "once"):
                    # 「本会话允许」附上 destination=session 的前缀规则。
                    # 「允许」只放行这一次，不带 updatedPermissions。
                    token = ""
                    updates = None
                    if decision == "always":
                        token = str(data.get("command_token") or "").strip()
                        updates = prefix_permission_updates(tool_name, token) or None
                    if event == "PreToolUse":
                        remember_permission_hold(session_id, command, decision, token, tool_name)
                        if decision == "always":
                            remember_session_allow(session_id, tool_name, token)
                    emit("allow", "The person allowed this command on BetterFocusIDE.",
                         event, updates=updates)
                    return
                break
            send(permission_message(session_id, product, "permission_timeout",
                                    request_id, tool_name, tool_input, detail, host, cwd))
            emit("ask", "The person left the permission card unanswered. Ask in Qoder's own dialog.",
                 event)


        def emit_turn_finished(session_id, payload):
            host = host_app()
            product = _get_product(session_id)
            send({"provider": "qoder", "product": product,
                  "event": "turn_finished", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "host": host, "cwd": os.getcwd(),
                  "payload": {"transcript_path": payload.get("transcript_path", "")}})


        def emit_session_ended(session_id):
            product = _get_product(session_id)
            send({"provider": "qoder", "product": product,
                  "event": "session_ended", "session_id": session_id,
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "payload": {}})


        # ── 待办进度 ────────────────────────────────────────────────────
        # Qoder 原生名是 todo_write，Claude 血统（CLI / 插件旧版）是 TodoWrite；
        # 匹配器与这里都要两个都认，否则换个宿主形态卡片就永远不出现。
        # V2 家族（Claude Code 血统演进）用 TaskCreate / TaskUpdate 单条写入——
        # Qoder 新版跟随这条线，所以这里也要认，否则「任务推进」只有第一次
        # TodoWrite 整表能到，后续 TaskUpdate 全部漏掉（这正是进度不更新的根因）。
        TODO_TOOLS = ("TodoWrite", "todo_write", "todowrite", "SetTodoList")
        TODO_UPSERT_TOOLS = ("TaskCreate", "TaskUpdate")


        def normalise_todos(raw):
            \"\"\"把各家 todo 数组压成 {id, content, status}。

            宿主字段差异：Claude 系用 content，Kimi 用 title，V2 任务用 subject；
            状态值 Kimi 写 done，其余写 completed。认不出的正文直接丢弃——
            发一张空表会把卡片错误地推进「全部完成」。
            \"\"\"
            todos = []
            for index, item in enumerate(raw):
                if isinstance(item, str):
                    text = item.strip()
                    if text:
                        todos.append({"id": "t%d" % index, "content": text,
                                      "status": "pending"})
                    continue
                if not isinstance(item, dict):
                    continue
                content = (item.get("content") or item.get("title")
                           or item.get("subject") or "")
                content = content.strip() if isinstance(content, str) else ""
                if not content:
                    continue
                status = item.get("status") or item.get("state")
                if not status:
                    status = "completed" if item.get("completed") else "pending"
                todos.append({"id": str(item.get("id") or item.get("task_id")
                                        or item.get("taskId")
                                        or ("t%d" % index)),
                              "content": content,
                              "status": str(status)})
            return todos


        def emit_todo(session_id, payload):
            \"\"\"转发待办。tool_input 是首选来源：它就是要写进去的那张表。

            Qoder 的 TodoWrite 带一个 `merge` 参数（Claude Code V2 语义）：
            - `merge=False`（或缺失）：整表覆盖，发 `todo_updated`，岛侧直接替换。
            - `merge=True`：增量——只传变化的那几条，岛侧没有合并能力，必须在这里
              拆成单条 `todo_item_updated` 交给岛侧按 id UPSERT，否则整表覆盖会把
              没出现的那几条全抹掉（进度从 N/N 塌成 1/1）。
            \"\"\"
            tool_input = payload.get("tool_input")
            if not isinstance(tool_input, dict):
                return
            raw = tool_input.get("todos")
            if not isinstance(raw, list):
                # 少数宿主把结果放在 tool_response 里（写入后的回读）。
                response = payload.get("tool_response")
                if isinstance(response, dict):
                    raw = response.get("todos")
            if not isinstance(raw, list):
                return
            todos = normalise_todos(raw)
            if not todos:
                return
            # merge=True 走逐条 UPSERT；否则整表覆盖。
            if tool_input.get("merge") is True:
                for item in todos:
                    send({"provider": "qoder", "product": _get_product(session_id),
                          "event": "todo_item_updated", "session_id": session_id,
                          "host": host_app(),
                          "cwd": payload.get("cwd") or os.getcwd(),
                          "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                          "payload": {"todo": item}})
                return
            send({"provider": "qoder", "product": _get_product(session_id),
                  "event": "todo_updated", "session_id": session_id,
                  "host": host_app(),
                  "cwd": payload.get("cwd") or os.getcwd(),
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"todos": todos}})


        def emit_todo_upsert(session_id, payload):
            \"\"\"单条写入（TaskCreate / TaskUpdate）。V2 家族一条任务一次调用。

            Qoder CLI 的实测载荷（探针）：
            - TaskCreate 入参 `{subject, description, activeForm}`（无 id），
              但 `tool_response.task = {id, subject}` 里有服务端分配的真实 id。
            - TaskUpdate 入参 `{taskId, status}`（无正文），只能靠 taskId 定位。

            所以这里维护一张「taskId → 正文」映射（持久化到会话 state），
            TaskCreate 用 response 的 id 登记正文，TaskUpdate 靠 taskId 反查。
            全程 id 都用服务端分配的 taskId，保证岛侧 UPSERT 精确命中、不重复。
            \"\"\"
            tool_input = payload.get("tool_input")
            if not isinstance(tool_input, dict):
                return
            response = payload.get("tool_response")
            if not isinstance(response, dict):
                response = {}
            # 服务端分配的真实 id：TaskCreate 在 response.task.id，
            # TaskUpdate 直接在入参 taskId。
            task = response.get("task")
            if isinstance(task, dict):
                resp_id = str(task.get("id") or task.get("taskId") or "")
                resp_subject = task.get("subject") or task.get("content") or ""
            else:
                resp_id = ""
                resp_subject = ""
            todo_id = str(tool_input.get("taskId") or tool_input.get("task_id")
                          or tool_input.get("id") or resp_id or "").strip()
            content = (tool_input.get("subject") or tool_input.get("content")
                       or tool_input.get("title") or resp_subject or "")
            content = content.strip() if isinstance(content, str) else ""

            # 正文缺失时从会话映射表反查（TaskUpdate 的常态）。
            state = _load_state(session_id)
            mapping = state.get("tasks") or {}
            if not content and todo_id:
                content = mapping.get(todo_id) or ""
                content = content.strip() if isinstance(content, str) else ""
            if not content:
                return

            # 登记/回填映射：TaskCreate 把 response 的真实 id 与正文绑定。
            if todo_id:
                mapping[todo_id] = content
                state["tasks"] = mapping
                _save_state(session_id, state)

            status = tool_input.get("status") or tool_input.get("state")
            if not status:
                status = "pending"
            send({"provider": "qoder", "product": _get_product(session_id),
                  "event": "todo_item_updated", "session_id": session_id,
                  "host": host_app(),
                  "cwd": payload.get("cwd") or os.getcwd(),
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"todo": {"id": todo_id, "content": content,
                                       "status": str(status)}}})


        def emit_status(session_id, event_name, title, body, payload):
            if not alerts_enabled("turn") or not os.path.exists(SOCKET_PATH):
                return
            text = " ".join(str(body or "").split())[:180]
            send({"provider": "qoder", "product": _get_product(session_id),
                  "event": event_name, "session_id": session_id,
                  "host": host_app(),
                  "cwd": payload.get("cwd") or os.getcwd(),
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"title": " ".join(str(title or "").split())[:80],
                              "body": text}})


        def _notice_details(payload):
            details = payload.get("details")
            return details if isinstance(details, dict) else {}


        def _is_question_tool(name):
            folded = str(name or "").lower().replace("_", "")
            return folded in ("askuserquestion", "question", "askfollowupquestion")


        def _tool_from_notice(payload, message):
            \"\"\"从 Notification 里取出工具名。

            Qoder.app 的 permission_prompt 把工具放在 details.toolName，
            文案是 "Tool <name> requires confirmation"。Claude 系只有
            "permission to use <name>"。
            \"\"\"
            details = _notice_details(payload)
            name = str(details.get("toolName") or details.get("tool_name") or "").strip()
            if name:
                return name, details
            text = message or ""
            marker = " requires confirmation"
            if text.startswith("Tool ") and marker in text:
                return text[len("Tool "):text.find(marker)].strip(), details
            lower = text.lower()
            token = "permission to use "
            idx = lower.find(token)
            if idx >= 0:
                rest = text[idx + len(token):]
                picked = []
                for ch in rest:
                    if ch.isalnum() or ch in "_.-":
                        picked.append(ch)
                    else:
                        break
                return "".join(picked), details
            return "", details


        def emit_question_notice(session_id, payload, title, body):
            # Notification 不等答复。只出提醒，stdout 保持空。
            # 岛上作答仍只走 PermissionRequest / AskUserQuestion。
            if not alerts_enabled("question") or not os.path.exists(SOCKET_PATH):
                return
            text = " ".join(str(body or "").split())[:180]
            headline = " ".join(str(title or "").split())[:80] or "需要你的回答"
            send({"provider": "qoder", "product": _get_product(session_id),
                  "event": "question_notice", "session_id": session_id,
                  "host": host_app(),
                  "cwd": payload.get("cwd") or os.getcwd(),
                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "payload": {"title": headline,
                              "body": text or "请在 Qoder 里回答",
                              "transcript_path": payload.get("transcript_path") or ""}})


        def emit_permission_notice_only(session_id, payload, tool_name, tool_input, detail):
            # 权限提醒不回 allow / deny / ask。Notification 的 stdout 印 JSON
            # 会被宿主当成决策，盖住 Qoder 自己的对话框。
            if not alerts_enabled("permission") or not os.path.exists(SOCKET_PATH):
                return
            details = _notice_details(payload)
            request_id = safe_id(details.get("toolUseId")
                                 or details.get("tool_use_id")
                                 or payload.get("tool_use_id")
                                 or ((tool_name or "tool") + "-" + str(int(time.time() * 1000))))
            send(permission_message(session_id, _get_product(session_id), "permission_notice",
                                    request_id, tool_name or "", tool_input or {},
                                    " ".join(str(detail or "").split())[:180],
                                    host_app(), payload.get("cwd") or ""))


        def handle_user_wait_notice(session_id, payload, kind, message):
            \"\"\"Qoder.app 等人时往往只发 Notification，不发 PermissionRequest。

            提问工具不能发 permission_notice：岛侧会把它当成「提问卡已经在问」
            而丢掉。桌面版有题面时发 question_requested；没有题面才退回提醒。
            其余确认发 permission_notice。elicitation_dialog 沿用「需要你的输入」。
            \"\"\"
            if kind == "elicitation_dialog":
                emit_status(session_id, "review_notice", "需要你的输入", message, payload)
                return
            tool_name, details = _tool_from_notice(payload, message)
            raw_input = details.get("input")
            if isinstance(raw_input, str):
                try:
                    raw_input = json.loads(raw_input)
                except Exception:
                    raw_input = {"input": raw_input}
            tool_input = raw_input if isinstance(raw_input, dict) else {}
            # 终端命令的三按钮卡由同时到达的 PermissionRequest 打开。
            # 这里再发 permission_notice 会排在卡后面，答完又弹出一条过期横幅。
            if shell_command(tool_input):
                return
            if kind == "ask_user_question" or _is_question_tool(tool_name):
                # 桌面版的提问卡由 PreToolUse 打开并等答案。这条 Notification
                # 超时只有 5 秒，不能在这里阻塞；卡已经开过就不再发提醒。
                if _desktop_qoder() and _question_card_recent(session_id):
                    return
                questions = _real_questions(tool_input)
                if questions and _desktop_qoder():
                    publish_question(payload, session_id, questions)
                    return
                if questions:
                    first = questions[0]
                    title = first.get("header") or "需要你的回答"
                    body = first.get("question") or message
                    if len(questions) > 1:
                        extra = "（共 %d 题）" % len(questions)
                        body = ((body + " " + extra) if body else extra)
                else:
                    title = "需要你的回答"
                    body = message or "请在 Qoder 里回答"
                emit_question_notice(session_id, payload, title, body)
                return
            reason = details.get("message")
            if isinstance(reason, str) and reason.strip():
                detail = reason.strip()
            else:
                detail = message
            emit_permission_notice_only(session_id, payload, tool_name, tool_input, detail)


        def main():
            try:
                payload = json.load(sys.stdin)
            except Exception:
                payload = {}
            if not isinstance(payload, dict):
                payload = {}
            session_id = payload.get("session_id") or payload.get("sessionId") or "unknown"
            event = payload.get("hook_event_name") or payload.get("hookEventName") or ""

            # 首次调用时识别 product 并持久化到会话状态文件。
            # 后续调用从 state 读取，保证同一会话 product 一致。
            product = _identify_product()
            _merge_state(session_id, product)

            # 工具调用失败不通知。旧安装里这条 hook 可能还在，进来就退出。
            if event == "PostToolUseFailure":
                return
            if event in ("StopFailure", "PermissionDenied"):
                detail = str(payload.get("error") or payload.get("message") or "")
                title = "自动模式拒绝了这次操作" if event == "PermissionDenied" else "这一轮没有完成"
                emit_status(session_id, "failure_notice", title, detail, payload)
                return
            if event == "SubagentStop":
                detail = str(payload.get("last_assistant_message") or payload.get("message") or "子任务已结束")
                emit_status(session_id, "subagent_finished", "子任务完成", detail, payload)
                return
            if event in ("PreCompact", "PostCompact"):
                title = "上下文已压缩" if event == "PostCompact" else "即将压缩上下文"
                emit_status(session_id, "compact_notice", title, "", payload)
                return
            if event == "Notification":
                kind = str(payload.get("notification_type") or "")
                message = str(payload.get("message") or "")
                if kind in ("document_review", "browser_interaction"):
                    title = "文档待审阅" if kind == "document_review" else "浏览器在等你"
                    emit_status(session_id, "review_notice", title, message, payload)
                elif kind == "auth_storage_failure" or kind.startswith("quota_"):
                    title = "登录状态失效" if kind == "auth_storage_failure" else "额度不足"
                    emit_status(session_id, "failure_notice", title, message, payload)
                elif kind in ("agent_needs_input", "elicitation_url_dialog"):
                    emit_status(session_id, "review_notice", "需要你的输入", message, payload)
                elif kind in ("permission_prompt", "ask_user_question", "elicitation_dialog"):
                    # Qoder.app 的 waiting-user 只到这里。stdout 保持空。
                    handle_user_wait_notice(session_id, payload, kind, message)
                return

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
                # 带 command 的权限申请会等岛上的三按钮卡。
                # 每次询问（accept_edits）仍会为终端命令发它，不能按这个模式提前放行。
                # 自动审批（auto）和完全访问（bypass_permissions）由 Qoder 自己处理，不开卡。
                # 其余仍只通知，立刻回 ask，让 Qoder 弹自己的对话框。
                if qoder_handles_approval(payload) and shell_command(_question_input(payload)):
                    emit("allow", "This Qoder session approves commands itself.")
                    return
                if not alerts_enabled("permission"):
                    emit("ask", "BetterFocusIDE permission notices are off; decide in Qoder's own dialog.")
                    return
                if not os.path.exists(SOCKET_PATH):
                    emit("ask", "BetterFocusIDE is not running; decide in Qoder's own dialog.")
                    return
                run_permission(payload, session_id)
                return

            if event == "PostToolUse":
                # 发后即忘：todo 之外的工具一律静默退出，不打印任何东西。
                tool_name = payload.get("tool_name") or payload.get("toolName") or ""
                if tool_name in TODO_TOOLS and os.path.exists(SOCKET_PATH):
                    emit_todo(session_id, payload)
                elif tool_name in TODO_UPSERT_TOOLS and os.path.exists(SOCKET_PATH):
                    emit_todo_upsert(session_id, payload)
                return

            if event == "PreToolUse":
                # IDE 上这条不等待，立刻退出。桌面版 Qoder.app 会等这条返回
                # 才进入 waiting-user，提问就在这里开卡并阻塞到答完。
                tool_name = payload.get("tool_name") or payload.get("toolName") or ""
                if _is_question_tool(tool_name) and _desktop_qoder():
                    if alerts_enabled("question") and os.path.exists(SOCKET_PATH):
                        questions = _real_questions(_question_input(payload))
                        if questions:
                            run_question(payload, session_id, questions, "PreToolUse")
                            return
                # 桌面版的终端权限在这里等卡片。PermissionRequest 要等检查结果已经是
                # ask 才会到，那时原生审批框已经画出来了。允许 / 拒绝在这里直接回，
                # 框就不会在等待期间出现。IDE 的 PreToolUse 不等待，不能在这里堵住。
                if (_desktop_qoder() and alerts_enabled("permission")
                        and os.path.exists(SOCKET_PATH)):
                    tool_input = _question_input(payload)
                    command = shell_command(tool_input)
                    if command:
                        if session_allows(session_id, command, tool_name):
                            emit("allow", "This command is allowed for the rest of this Qoder session.",
                                 "PreToolUse")
                            return
                        # 不回决策。Qoder 按当前会话的自动审批或完全访问自己放行。
                        if qoder_handles_approval(payload):
                            return
                        run_permission(payload, session_id, "PreToolUse")
                        return
                return


        if __name__ == "__main__":
            main()
        """
}
