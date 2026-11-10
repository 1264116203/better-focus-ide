// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 从智能体的会话记录（`.jsonl`）里读出真实标题，方式对齐 Python 的 `transcript.py`。
///
/// "Qoder 回复完成"这行在一屏五条一模一样时毫无信息量；真正有用的标题是**用户自己的
/// 首条提问**。Stop hook 会上报 transcript 路径，我们从中取两行：
///
/// - `first_prompt` —— 会话开场的用户轮次（= IDE 的会话标题）
/// - `last_prompt`  —— 最近一次用户轮次（= 这一轮完成的事）
///
/// 外加记录里的 `entrypoint` 与 `humanInput`，从而能把后台的 `qodercli -p` 会话（其"用户输入"
/// 是被管道进来的 diff、并非人类）与用户真正在等的 IDE 会话区分开。
///
/// 新版 Qoder 内核对 GUI 会话也统一写 `entrypoint: "cli"`（transcript 落在 `~/.qoder/projects/`），
/// 单看 entrypoint 会把真人会话误当无头脚本。真人 UI 输入（含粘贴）的记录带 `humanInput`
/// 标记；管道输入没有——两者组合才是可靠的判据。
///
/// 文件可能有几 MB，故只读**头部与尾部各自的字节预算**——标题总在开头附近、当前轮次
/// 总在结尾附近，中间对话从不触碰。任何失败都坍缩为空串，让调用方回退到通用文案；
/// 标题缺失绝不能阻止通知弹出。
enum Transcript {
    // 展示长度上限（字符），与 Python config 对齐。
    static let titleLimit = 40
    static let bodyLimit = 56
    /// 卡片详情展开后能看到的正文上限。折叠态仍只显示 `bodyLimit`。
    static let detailLimit = 480
    // 读取字节预算。
    static let headBytes = 256 * 1024
    static let tailBytes = 4 * 1024 * 1024
    static let chunkBytes = 64 * 1024
    static let maxLineBytes = 128 * 1024
    /// CLI 写入的 `entrypoint` 值；交互式 IDE 会话不带此字段。
    static let entrypointCLI = "cli"

    struct Session {
        let title: String
        let latest: String
        /// 最近一轮用户输入的较长版本，供通知详情展开。单行标题仍用 `latest`。
        let latestDetail: String
        let entrypoint: String
        /// 首条人类发言记录是否带 `humanInput` 标记（真人 UI 输入，含粘贴）。
        let hasHumanInput: Bool
        /// 由 `qodercli`（无头脚本）而非 IDE 里的人写出。
        ///
        /// 新版 Qoder 内核对 GUI 会话也写 `entrypoint: "cli"`，但真人 UI 输入的记录
        /// 带 `humanInput` 标记；只有 entrypoint=cli 且无该标记的才是真正的管道会话。
        var fromCLI: Bool { entrypoint == entrypointCLI && !hasHumanInput }
        static let empty = Session(title: "", latest: "", latestDetail: "",
                                   entrypoint: "", hasHumanInput: false)
    }

    /// 打开文件一次，返回标题 + 最新轮次 + entrypoint + 人类输入标记。
    static func sessionSummary(path: String?, provider: String?) -> Session {
        guard let path, !path.isEmpty else { return .empty }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              !isDir.boolValue,
              let handle = FileHandle(forReadingAtPath: path) else { return .empty }
        defer { try? handle.close() }
        let (title, entrypoint, human) = first(handle: handle, limit: titleLimit, provider: provider)
        let latestDetail = last(handle: handle, limit: detailLimit, provider: provider)
        let latest = shorten(latestDetail, limit: bodyLimit)
        return Session(title: title, latest: latest, latestDetail: latestDetail,
                       entrypoint: entrypoint, hasHumanInput: human)
    }

    // MARK: - 空白折叠 / 截断

    /// 把连续空白折叠成单个空格并截断到 `limit`（省略号计入上限）。历史行是单行的。
    static func shorten(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        if limit > 1 && collapsed.count > limit {
            return String(collapsed.prefix(limit - 1)) + "…"
        }
        return collapsed
    }

    // MARK: - 头部扫描（首条用户提问 + entrypoint）

    /// 从头按块读取，返回遇到的第一条用户提问、其 entrypoint 与人类输入标记。
    private static func first(handle: FileHandle, limit: Int,
                              provider: String?) -> (String, String, Bool) {
        handle.seek(toFileOffset: 0)
        var entrypoint = ""
        var human = false
        var spent = 0
        var carry = Data()
        while spent < headBytes {
            let toRead = min(chunkBytes, headBytes - spent)
            let data = handle.readData(ofLength: toRead)
            if data.isEmpty {
                // EOF：尾部残留（若有）就是一条完整的最后一行。
                if !carry.isEmpty {
                    let (prompt, seen, seenHuman) = lineUser(carry, provider: provider)
                    if entrypoint.isEmpty { entrypoint = seen }
                    if !prompt.isEmpty { return (shorten(prompt, limit: limit), seen, seenHuman) }
                }
                return ("", entrypoint, human)
            }
            spent += data.count
            var combined = carry + data
            let lines = completeLines(&combined)   // 余下部分保留在 combined 里
            carry = combined
            for line in lines {
                let (prompt, seen, seenHuman) = lineUser(line, provider: provider)
                if entrypoint.isEmpty {
                    entrypoint = seen
                    human = seenHuman
                }
                if !prompt.isEmpty { return (shorten(prompt, limit: limit), seen, seenHuman) }
            }
        }
        return ("", entrypoint, human)
    }

    // MARK: - 尾部扫描（最近一条用户提问，逆序）

    /// 从尾按块反向读取，返回最近一条用户提问。
    private static func last(handle: FileHandle, limit: Int, provider: String?) -> String {
        let fileSize = handle.seekToEndOfFile()
        var position = fileSize
        var head = Data()
        var spent = 0
        let chunk = UInt64(chunkBytes)
        while position > 0 && spent < tailBytes {
            // 保护减法：`position` 是 UInt64，当剩余文件小于一块时会下溢（Python 的
            // 有符号 `max(0, …)` 会钳位，但无符号算术会先 trap）。
            let start = position > chunk ? position - chunk : 0
            handle.seek(toFileOffset: start)
            let data = handle.readData(ofLength: Int(position - start))
            spent += data.count
            position = start
            let combined = data + head
            if position > 0 {
                // 首个组件可能是残缺行，其前半段落在更早（前面）那块里；把它 carry 下去。
                let lines = splitByNewline(combined)
                head = lines.first ?? Data()
                if head.count > maxLineBytes { head = Data("{".utf8) } // 太长了不可能是提问
                let emit = Array(lines.dropFirst())
                if let hit = scanReversed(emit, limit: limit, provider: provider) { return hit }
            } else {
                // 已到文件头：先前那段残缺现在是完整的了。
                head = Data()
                let lines = splitByNewline(combined)
                if let hit = scanReversed(lines, limit: limit, provider: provider) { return hit }
            }
        }
        return ""
    }

    /// 逆序扫描给定行，返回第一条非空用户提问（截断后）。
    private static func scanReversed(_ lines: [Data], limit: Int, provider: String?) -> String? {
        for line in lines.reversed() where !line.isEmpty {
            let (prompt, _, _) = lineUser(line, provider: provider)
            if !prompt.isEmpty { return shorten(prompt, limit: limit) }
        }
        return nil
    }

    // MARK: - 行切分

    /// 按 `\n` 切分，把尾部（可能残缺）的组件退回 `buffer`，返回其之前的完整行。
    private static func completeLines(_ buffer: inout Data) -> [Data] {
        let all = splitByNewline(buffer)
        if let lastPartial = all.last {
            buffer = lastPartial
        }
        return Array(all.dropLast())
    }

    /// 所有以 `\n` 分隔的组件（含空组件与尾部残缺段）。
    private static func splitByNewline(_ data: Data) -> [Data] {
        let nl = UInt8(ascii: "\n")
        var result: [Data] = []
        var start = data.startIndex
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == nl {
                result.append(Data(data[start..<i]))
                start = data.index(after: i)
            }
            i = data.index(after: i)
        }
        result.append(Data(data[start..<data.endIndex]))
        return result
    }

    // MARK: - 记录解析

    /// 一行 jsonl →（用户提问，entrypoint，人类输入标记）。跳过超大行、块边界处的
    /// 畸形 JSON，以及一切并非人类发言的内容。
    private static func lineUser(_ raw: Data, provider: String?) -> (String, String, Bool) {
        if raw.isEmpty || raw.count > maxLineBytes { return ("", "", false) }
        guard let obj = try? JSONSerialization.jsonObject(with: raw),
              let record = obj as? [String: Any] else { return ("", "", false) }
        return (prompt(of: record, provider: provider),
                entrypoint(of: record),
                hasHumanInput(of: record))
    }

    /// 按提供方选择解析器：cursor 走 Cursor 形态，workbuddy 走 WorkBuddy 形态，其余走 Qoder 形态。
    private static func prompt(of record: [String: Any], provider: String?) -> String {
        switch provider?.lowercased() {
        case "cursor":
            return cursorPrompt(record)
        case "workbuddy":
            return workbuddyPrompt(record)
        default:
            return qoderPrompt(record)
        }
    }

    /// Qoder 形态：顶层 `type == "user"`；人类发言是 `str`，工具结果是 `list`
    /// （并非人话——必须跳过，否则标题会变成一大片命令输出）。
    private static func qoderPrompt(_ record: [String: Any]) -> String {
        guard record["type"] as? String == "user",
              let message = record["message"] as? [String: Any] else { return "" }
        return text(from: message["content"])
    }

    /// WorkBuddy 形态：顶层 `role == "user"`，`content` 直接在顶层（不在 message 里），
    /// 是块列表、块类型 `input_text`，真正的用户输入包在 `<user_query>` 里。
    private static func workbuddyPrompt(_ record: [String: Any]) -> String {
        guard record["role"] as? String == "user" else { return "" }
        let text = text(from: record["content"])
        if let query = captureUserQuery(text) { return query }
        return stripNoise(text)
    }

    /// Cursor 形态：顶层 `role == "user"`（不是 `type`）；content 恒为文本块列表，
    /// 发言被包在 `<user_query>` 里。
    private static func cursorPrompt(_ record: [String: Any]) -> String {
        guard record["role"] as? String == "user",
              let message = record["message"] as? [String: Any] else { return "" }
        let text = text(from: message["content"])
        if let query = captureUserQuery(text) { return query }
        return stripNoise(text)
    }

    /// `content` 为 `str` 时直接用；为块列表时拼接各块的 `text`（仅取 `type == "text"`
    /// 或 WorkBuddy 的 `type == "input_text"` 的块——`tool_result` 不是发言）。
    private static func text(from content: Any?) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            let parts = blocks.compactMap { block -> String? in
                let type = block["type"] as? String
                guard type == "text" || type == "input_text" else { return nil }
                return block["text"] as? String
            }
            return parts.joined(separator: " ")
        }
        return ""
    }

    /// 取用户轮次记录里的 `entrypoint`（非 user 记录返回空）。
    private static func entrypoint(of record: [String: Any]) -> String {
        guard record["type"] as? String == "user" else { return "" }
        return record["entrypoint"] as? String ?? ""
    }

    /// 用户轮次记录是否带 `humanInput` 标记。新版 Qoder 内核给真人 UI 输入（含粘贴）
    /// 写这个字段；`qodercli -p` 管道输入没有，显式 null 同样视为无。
    private static func hasHumanInput(of record: [String: Any]) -> Bool {
        guard record["type"] as? String == "user" else { return false }
        guard let value = record["humanInput"] else { return false }
        return !(value is NSNull)
    }

    // MARK: - Cursor 噪声正则

    /// 抽取 `<user_query>…</user_query>` 内的内容。
    private static func captureUserQuery(_ text: String) -> String? {
        regex(#"<user_query>(.*?)</user_query>"#)?.firstMatch(text)
    }

    /// 剥离 `<timestamp>` / `<image_files>` 等噪声块后 trim。
    private static func stripNoise(_ text: String) -> String {
        let pattern = #"<timestamp>.*?</timestamp>|<image_files>.*?</image_files>"#
        guard let re = regex(pattern) else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let out = re.replaceAll(in: text, with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 构造大小写不敏感、点匹配换行的正则。
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern,
                                 options: [.dotMatchesLineSeparators, .caseInsensitive])
    }
}

private extension NSRegularExpression {
    /// 返回首个匹配的第 1 捕获组（trim 后）；无捕获组返回 nil。
    func firstMatch(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = firstMatch(in: text, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 全局替换所有匹配为 `replacement`。
    func replaceAll(in text: String, with replacement: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return stringByReplacingMatches(in: text, options: [], range: range,
                                        withTemplate: replacement)
    }
}
