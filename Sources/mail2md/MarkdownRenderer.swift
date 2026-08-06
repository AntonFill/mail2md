//
//  MarkdownRenderer.swift
//  mail2md
//
//  Created by Anton Fillmann on 07.07.2026.
//

import Foundation

/// Renders an `EmailMessage` as Markdown with YAML frontmatter.
///
/// Frontmatter follows the EMAIL note template
/// (`created` / `from` / `to` / `via` / `subject` / `attachments`); the body is
/// the plain mail text with no heading. `attachments` lists the raw filenames
/// of the mail's attachment parts (a YAML flow list, or empty scaffolding when
/// there are none). `via` stays empty scaffolding, because a stateless single-message
/// converter cannot populate a thread predecessor.
struct MarkdownRenderer {

    /// Zone in which `created` is rendered as a local wall-clock time. Defaults
    /// to the system zone (a CLI naturally shows local time); tests and a future
    /// `--timezone` option inject an explicit zone. The sender's own offset
    /// (`EmailMessage.timeZone`) is deliberately not used here: a mail sent from
    /// another zone must still read in the reader's local time.
    init(timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        self._dateFormatter = formatter
    }

    fileprivate let _dateFormatter: DateFormatter

    func render(_ message: EmailMessage) -> String {
        var lines: [String] = []

        lines.append("---")
        lines.append(self.field("created", message.date.map { self.timestamp($0) }, quoted: false))
        lines.append(self.field("from", message.from))
        lines.append(self.field("to", message.to))
        lines.append(self.field("via", nil))
        lines.append(self.field("subject", message.subject))
        lines.append(self.listField("attachments", message.attachments))
        lines.append("---")
        lines.append("")
        lines.append(message.body)
        lines.append("")

        return lines.joined(separator: "\n")
    }
}

// MARK: -
extension MarkdownRenderer {

    /// A frontmatter line. Non-empty string values are quoted (safe for colons
    /// in subjects and addresses); empty values render as a bare `key:`.
    func field(_ name: String, _ value: String?, quoted: Bool = true) -> String {
        guard let value, value.isEmpty == false else {
            return "\(name):"
        }
        return quoted ? "\(name): \(self.quoted(value))" : "\(name): \(value)"
    }

    /// A frontmatter line holding a YAML flow list of quoted strings, e.g.
    /// `attachments: ["a.pdf", "b.pdf"]`. An empty list renders as a bare `key:`
    /// (matching the empty-scaffolding convention of the other fields).
    func listField(_ name: String, _ values: [String]) -> String {
        guard values.isEmpty == false else {
            return "\(name):"
        }
        let items = values.map { self.quoted($0) }.joined(separator: ", ")
        return "\(name): [\(items)]"
    }

    /// Local wall-clock timestamp `YYYY-MM-DDTHH:mm` in the renderer's zone.
    func timestamp(_ date: Date) -> String {
        return self._dateFormatter.string(from: date)
    }

    /// Double-quotes a value for safe use in YAML frontmatter.
    func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
