// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import Foundation

/// 在 TOML 文件里维护一段「带界标的受管区块」。
///
/// Codex 与 Kimi 的 hook 配置都是 `config.toml`，而且两家都**没有**稳定的
/// 「只加一条」的 JSON 式入口：Codex 用顶层 `notify = [...]`（单值键，重复即报错），
/// Kimi 用 `[[hooks]]` 数组表。用 TOML 库去解析-重写会把用户的注释、顺序、
/// 行内表全部改写成另一种排版，风险远大于收益。
///
/// 因此这里改用最保守的做法：只在文件尾部维护一段被注释界标包起来的文本，
/// 界标之外一个字节都不碰。卸载 = 删掉这段；重装 = 原地替换这段。
enum ManagedTOML {
    static let beginMarker = "# >>> betterfocus (managed block, do not edit) >>>"
    static let endMarker = "# <<< betterfocus <<<"

    /// 生成受管区块（`lines` 为已排好的 TOML 行）。
    static func block(_ lines: [String]) -> String {
        ([beginMarker] + lines + [endMarker]).joined(separator: "\n") + "\n"
    }

    /// 插入了受管区块之后的完整文件内容。
    ///
    /// 已有区块 → 原地替换；没有 → 追加到文件末尾（保留原有换行习惯）。
    static func applying(_ block: String, to text: String) -> String {
        if let range = existingBlockRange(in: text) {
            var out = text
            out.replaceSubrange(range, with: block)
            return out
        }
        var out = text
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty { out += "\n" }
        return out + block
    }

    /// 删除受管区块（卸载）。
    static func removing(from text: String) -> String {
        guard let range = existingBlockRange(in: text) else { return text }
        var out = text
        out.removeSubrange(range)
        // 收尾：别留下两行以上连续空行。
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out
    }

    /// 受管区块在原文中的范围（含结尾换行）。
    static func existingBlockRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: beginMarker),
              let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex)
        else { return nil }
        var upper = end.upperBound
        if upper < text.endIndex, text[upper] == "\n" {
            upper = text.index(after: upper)
        }
        return start.lowerBound..<upper
    }

    /// 界标之外是否已存在某个键 / 表头。
    ///
    /// 用于「用户自己已经配了 `notify`」这种冲突：此时再追加一个 `notify` 会让
    /// 整份 config.toml 解析失败（TOML 不允许重复键），所以宁可跳过安装并如实上报，
    /// 也不能把人家的配置改坏。
    static func hasKeyOutsideBlock(_ key: String, in text: String) -> Bool {
        let body: String
        if let range = existingBlockRange(in: text) {
            body = text.replacingCharacters(in: range, with: "")
        } else {
            body = text
        }
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // 跳过注释与空行。
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix(key), line.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                return true
            }
        }
        return false
    }

    /// 文件尾部是否已有我们的区块。
    static func hasBlock(in text: String) -> Bool {
        existingBlockRange(in: text) != nil
    }
}
