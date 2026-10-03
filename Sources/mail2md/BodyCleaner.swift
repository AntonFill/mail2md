//
//  BodyCleaner.swift
//  mail2md
//
//  Created by Anton Fillmann on 23.07.2026.
//

import Foundation

/// Post-decode cleanup of a mail body: removes ballast a reader never wants
/// (angle-bracket `mailto:`/URL duplicates, `cid:` image references) and
/// normalizes whitespace.
///
/// It deliberately leaves untouched the quote structure the source already
/// carries, meaning `>` prefixes and converted HTML blockquotes. Synthesizing
/// depth from flat client separators (`Von:`/`Am … schrieb:`) would need the
/// splitting heuristic removed in v0.9.0, so a flat cascade stays flat.
///
/// Code is left alone as well: a fenced block passes through character for
/// character, blank lines and trailing spaces included, and only the text
/// around it is cleaned.
///
/// The transforms never drop an address or URL: a `mailto:` wrapper collapses
/// onto the plain twin that precedes it, or is unwrapped to the bare address.
enum BodyCleaner {

    static func clean(_ body: String) -> String {
        // Normalize line endings first: quoted-printable decoding reintroduces
        // `\r\n` (from `=0D=0A`) after the parser's initial normalization, so
        // blank-line runs would otherwise arrive as `\r\n\r\n…` and escape the
        // collapse below. Done with plain replacement, not a regex: Swift regex
        // matches at grapheme-cluster level by default, where `\r\n` is a
        // *single* cluster, so a `\r`/`\n` pattern would miss it.
        let text = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        let segments = self.segments(of: text.components(separatedBy: "\n"))
        for segment in segments {
            lines += segment.isCode ? segment.lines : self.tidy(segment.lines)
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: -
extension BodyCleaner {

    /// Cleans text that is not code.
    fileprivate static func tidy(_ lines: [String]) -> [String] {
        var text = lines.joined(separator: "\n")

        // A `mailto:` wrapper right after its own plain twin collapses onto the
        // twin, e.g. `foo@example.com<mailto:foo@example.com>` and the nested
        // attribution form `<foo@example.com<mailto:foo@example.com>>`. Any
        // other is unwrapped to the address, so the address survives even when
        // it appears only wrapped. One pass from the wrapper: the backreference
        // `([^\s<>]+)<mailto:\1>` it replaces started at every character of a
        // long token and backtracked through all of it, 1.3 s for a mail with
        // a few links of 1'000 characters (measured 2026-10-03).
        let wrapped = text
        text = wrapped.replacing(/<mailto:([^\s<>]+)>/) { wrapper in
            let followsTwin = wrapped[..<wrapper.range.lowerBound].hasSuffix(wrapper.1)
            return followsTwin ? "" : wrapper.1
        }

        // A URL immediately followed by its own angle-wrapped duplicate.
        text = text.replacing(/(https?:\/\/[^\s<>]+)<\1>/) { $0.1 }

        // Inline `cid:` image references (footer logos, tracking artifacts).
        text = text.replacing(/[\[<]cid:[^\]>]*[\]>]/, with: "")

        // Trailing whitespace per line, then collapse blank-line runs to one.
        var tidied: [String] = []
        let tidiedLines = text.components(separatedBy: "\n")
        for line in tidiedLines {
            let trimmed = line.replacing(/[ \t]+$/, with: "")
            if trimmed.isEmpty, tidied.last?.isEmpty == true {
                continue
            }
            tidied.append(trimmed)
        }

        return tidied
    }

    /// Splits the lines into runs of text and fenced code blocks. Only a fence
    /// that closes makes code; a lone fence line is a stray line of text.
    fileprivate static func segments(of lines: [String]) -> [(lines: [String], isCode: Bool)] {
        var segments: [(lines: [String], isCode: Bool)] = []
        var text: [String] = []

        var index = 0
        while index < lines.count {
            if let fence = self.fence(opening: lines[index]),
               let end = lines[(index + 1)...].firstIndex(where: { self.closes(fence, $0) }) {
                segments.append((text, false))
                segments.append((Array(lines[index...end]), true))
                text = []
                index = end + 1
                continue
            }
            text.append(lines[index])
            index += 1
        }
        segments.append((text, false))

        return segments
    }

    /// The fence a line opens, as its character and its length: three or more
    /// backticks or tildes at the start of the line.
    fileprivate static func fence(opening line: String) -> (character: Character, count: Int)? {
        guard
            let first = line.first,
            first == "`" || first == "~"
        else {
            return nil
        }

        let count = line.prefix { $0 == first }.count
        return count >= 3 ? (first, count) : nil
    }

    /// Whether a line closes the fence: the same character at least as often,
    /// and nothing after it but spaces.
    fileprivate static func closes(_ fence: (character: Character, count: Int), _ line: String) -> Bool {
        let run = line.prefix { $0 == fence.character }.count
        return run >= fence.count && line.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }
}
