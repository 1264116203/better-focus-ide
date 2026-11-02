// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// Reads a real session title out of the agent's transcript (`.jsonl`), the way
/// the Python `transcript.py` does. A "Qoder 回复完成" line says nothing when a
/// screen of five looks identical; the useful title is **the user's own first
/// prompt**. The Stop hook reports the transcript path; we pull two lines:
///
/// - `first_prompt` — the session's opening user turn (= the IDE's session title)
/// - `last_prompt`  — the most recent user turn (= what this finished round did)
///
/// plus the record's `entrypoint`, so a background `qodercli -p` session (whose
/// "user input" is a piped diff, not a human) can be told apart from the IDE
/// session the user is actually waiting on.
///
/// The file can be several MB, so we read only a **byte budget at the head and
/// the tail** — the title is always near the start, the current turn near the
/// end, the middle conversation is never touched. Every failure collapses to an
/// empty string so the caller can fall back to generic text; a missing title
/// must never stop a notification from firing.
enum Transcript {
    // Display limits (characters), matching the Python config.
    static let titleLimit = 40
    static let bodyLimit = 56
    // Read budgets (bytes).
    static let headBytes = 256 * 1024
    static let tailBytes = 4 * 1024 * 1024
    static let chunkBytes = 64 * 1024
    static let maxLineBytes = 128 * 1024
    /// `entrypoint` value written by the CLI; an interactive IDE session omits it.
    static let entrypointCLI = "cli"

    struct Session {
        let title: String
        let latest: String
        let entrypoint: String
        /// Written by `qodercli` (headless scripts) rather than a human in the IDE.
        var fromCLI: Bool { entrypoint == entrypointCLI }
        static let empty = Session(title: "", latest: "", entrypoint: "")
    }

    /// One open of the file returning title + latest turn + entrypoint.
    static func sessionSummary(path: String?, provider: String?) -> Session {
        guard let path, !path.isEmpty else { return .empty }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              !isDir.boolValue,
              let handle = FileHandle(forReadingAtPath: path) else { return .empty }
        defer { try? handle.close() }
        let (title, entrypoint) = first(handle: handle, limit: titleLimit, provider: provider)
        let latest = last(handle: handle, limit: bodyLimit, provider: provider)
        return Session(title: title, latest: latest, entrypoint: entrypoint)
    }

    // MARK: - Whitespace / truncation

    /// Collapse runs of whitespace to a single space and truncate to `limit`
    /// (the ellipsis counts toward the limit). History rows are single-line.
    static func shorten(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        if limit > 1 && collapsed.count > limit {
            return String(collapsed.prefix(limit - 1)) + "…"
        }
        return collapsed
    }

    // MARK: - Head scan (first user prompt + entrypoint)

    private static func first(handle: FileHandle, limit: Int,
                              provider: String?) -> (String, String) {
        handle.seek(toFileOffset: 0)
        var entrypoint = ""
        var spent = 0
        var carry = Data()
        while spent < headBytes {
            let toRead = min(chunkBytes, headBytes - spent)
            let data = handle.readData(ofLength: toRead)
            if data.isEmpty {
                // EOF: the trailing carry, if any, is a complete final line.
                if !carry.isEmpty {
                    let (prompt, seen) = lineUser(carry, provider: provider)
                    if entrypoint.isEmpty { entrypoint = seen }
                    if !prompt.isEmpty { return (shorten(prompt, limit: limit), entrypoint) }
                }
                return ("", entrypoint)
            }
            spent += data.count
            var combined = carry + data
            let lines = completeLines(&combined)   // remainder kept in combined
            carry = combined
            for line in lines {
                let (prompt, seen) = lineUser(line, provider: provider)
                if entrypoint.isEmpty { entrypoint = seen }
                if !prompt.isEmpty { return (shorten(prompt, limit: limit), entrypoint) }
            }
        }
        return ("", entrypoint)
    }

    // MARK: - Tail scan (most recent user prompt, reverse order)

    private static func last(handle: FileHandle, limit: Int, provider: String?) -> String {
        let fileSize = handle.seekToEndOfFile()
        var position = fileSize
        var head = Data()
        var spent = 0
        let chunk = UInt64(chunkBytes)
        while position > 0 && spent < tailBytes {
            // Guard the subtraction: `position` is UInt64 and underflows when the
            // remaining file is smaller than a chunk (Python's signed `max(0, …)`
            // would clamp, but unsigned arithmetic traps first).
            let start = position > chunk ? position - chunk : 0
            handle.seek(toFileOffset: start)
            let data = handle.readData(ofLength: Int(position - start))
            spent += data.count
            position = start
            let combined = data + head
            if position > 0 {
                // The first component may be a partial line whose front lives in
                // the previous (earlier) chunk; carry it forward.
                let lines = splitByNewline(combined)
                head = lines.first ?? Data()
                if head.count > maxLineBytes { head = Data("{".utf8) } // too long to be a prompt
                let emit = Array(lines.dropFirst())
                if let hit = scanReversed(emit, limit: limit, provider: provider) { return hit }
            } else {
                // Reached the file head: the earlier partial is now complete.
                head = Data()
                let lines = splitByNewline(combined)
                if let hit = scanReversed(lines, limit: limit, provider: provider) { return hit }
            }
        }
        return ""
    }

    private static func scanReversed(_ lines: [Data], limit: Int, provider: String?) -> String? {
        for line in lines.reversed() where !line.isEmpty {
            let (prompt, _) = lineUser(line, provider: provider)
            if !prompt.isEmpty { return shorten(prompt, limit: limit) }
        }
        return nil
    }

    // MARK: - Line splitting

    /// Split on `\n`, dropping the trailing (possibly partial) component back
    /// into `buffer` and returning the complete lines before it.
    private static func completeLines(_ buffer: inout Data) -> [Data] {
        let all = splitByNewline(buffer)
        if let lastPartial = all.last {
            buffer = lastPartial
        }
        return Array(all.dropLast())
    }

    /// All `\n`-separated components (including empty ones and a trailing partial).
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

    // MARK: - Record parsing

    /// One jsonl line → (user prompt, entrypoint). Skips oversized lines, broken
    /// JSON at chunk boundaries, and anything that isn't a human utterance.
    private static func lineUser(_ raw: Data, provider: String?) -> (String, String) {
        if raw.isEmpty || raw.count > maxLineBytes { return ("", "") }
        guard let obj = try? JSONSerialization.jsonObject(with: raw),
              let record = obj as? [String: Any] else { return ("", "") }
        return (prompt(of: record, provider: provider), entrypoint(of: record))
    }

    private static func prompt(of record: [String: Any], provider: String?) -> String {
        provider?.lowercased() == "cursor" ? cursorPrompt(record) : qoderPrompt(record)
    }

    /// Qoder shape: top-level `type == "user"`; the human utterance is a `str`,
    /// a tool result is a `list` (not human speech — skip it or the title becomes
    /// a wall of command output).
    private static func qoderPrompt(_ record: [String: Any]) -> String {
        guard record["type"] as? String == "user",
              let message = record["message"] as? [String: Any] else { return "" }
        return text(from: message["content"])
    }

    /// Cursor shape: top-level `role == "user"` (not `type`); content is always a
    /// list of text blocks with the utterance wrapped in `<user_query>`.
    private static func cursorPrompt(_ record: [String: Any]) -> String {
        guard record["role"] as? String == "user",
              let message = record["message"] as? [String: Any] else { return "" }
        let text = text(from: message["content"])
        if let query = captureUserQuery(text) { return query }
        return stripNoise(text)
    }

    /// `content` as a `str` used directly, or a list of blocks joined by their
    /// `text` (only `type == "text"` blocks — `tool_result` is not speech).
    private static func text(from content: Any?) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            let parts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            return parts.joined(separator: " ")
        }
        return ""
    }

    private static func entrypoint(of record: [String: Any]) -> String {
        guard record["type"] as? String == "user" else { return "" }
        return record["entrypoint"] as? String ?? ""
    }

    // MARK: - Cursor noise regexes

    private static func captureUserQuery(_ text: String) -> String? {
        regex(#"<user_query>(.*?)</user_query>"#)?.firstMatch(text)
    }

    private static func stripNoise(_ text: String) -> String {
        let pattern = #"<timestamp>.*?</timestamp>|<image_files>.*?</image_files>"#
        guard let re = regex(pattern) else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let out = re.replaceAll(in: text, with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern,
                                 options: [.dotMatchesLineSeparators, .caseInsensitive])
    }
}

private extension NSRegularExpression {
    func firstMatch(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = firstMatch(in: text, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replaceAll(in text: String, with replacement: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return stringByReplacingMatches(in: text, options: [], range: range,
                                        withTemplate: replacement)
    }
}
