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
/// The transforms never drop an address or URL: a `mailto:` wrapper collapses
/// onto the plain twin that precedes it, or is unwrapped to the bare address.
enum BodyCleaner {

    static func clean(_ body: String) -> String {
        // Normalize line endings first: quoted-printable decoding reintroduces
        // `\r\n` (from `=0D=0A`) after the parser's initial normalization, so
        // blank-line runs would otherwise arrive as `\r\n\r\n…` and escape the
        // `\n{3,}` collapse below. Done with plain replacement, not a regex:
        // Swift regex matches at grapheme-cluster level by default, where
        // `\r\n` is a *single* cluster, so a `\r`/`\n` pattern would miss it.
        var text = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A plain token immediately followed by its own `mailto:` wrapper, e.g.
        // `foo@example.com<mailto:foo@example.com>` and the nested attribution
        // form `<foo@example.com<mailto:foo@example.com>>`, collapses to the
        // plain token.
        text = text.replacing(/([^\s<>]+)<mailto:\1>/) { $0.1 }

        // Any remaining standalone `<mailto:addr>` is unwrapped to the address,
        // so the address survives even when it appears only wrapped.
        text = text.replacing(/<mailto:([^\s<>]+)>/) { $0.1 }

        // A URL immediately followed by its own angle-wrapped duplicate.
        text = text.replacing(/(https?:\/\/[^\s<>]+)<\1>/) { $0.1 }

        // Inline `cid:` image references (footer logos, tracking artifacts).
        text = text.replacing(/[\[<]cid:[^\]>]*[\]>]/, with: "")

        // Trailing whitespace per line, then collapse blank-line runs to one.
        text = text.replacing(/[ \t]+\n/, with: "\n")
        text = text.replacing(/\n{3,}/, with: "\n\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
