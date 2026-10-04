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
/// (`created` / `from` / `to` / `cc` / `via` / `subject` / `attachments`). Every
/// key is written even when empty, so the key set is fixed: a header the mail
/// lacks shows as an empty key, never as a missing one. The body is the plain
/// mail text with no heading. `attachments` lists the mail's
/// attachment parts (a YAML flow list of filenames, or empty scaffolding when
/// there are none). `via` stays empty scaffolding, because a stateless single-message
/// converter cannot populate a thread predecessor.
///
/// `linksAttachments` turns the listing into wikilinks and closes the body with
/// the attachments themselves. See its own documentation for when that is
/// allowed to happen.
struct MarkdownRenderer {

    /// Whether the attachment files exist beside the note.
    ///
    /// Off, the note can only name them: `attachments` is a flow list of the
    /// filenames the mail carried, and the body says nothing about them, because
    /// a link to a file nobody wrote is a dead link.
    ///
    /// On (the CLI sets it when it extracts), the files are real, so the note
    /// points at them: `attachments` becomes a block list of wikilinks, and the
    /// body ends with the attachments themselves, images shown, documents
    /// linked. The CLI owns this decision; the renderer only obeys it.
    let linksAttachments: Bool

    /// - Parameter timeZone: Zone in which `created` is rendered as a local
    ///   wall-clock time. Defaults to the system zone (a CLI naturally shows
    ///   local time); tests and a future `--timezone` option inject an explicit
    ///   zone. The sender's own offset (`EmailMessage.timeZone`) is deliberately
    ///   not used here: a mail sent from another zone must still read in the
    ///   reader's local time.
    init(timeZone: TimeZone = .current, linksAttachments: Bool = false) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        self._dateFormatter = formatter
        self.linksAttachments = linksAttachments
    }

    fileprivate let _dateFormatter: DateFormatter

    func render(_ message: EmailMessage) -> String {
        var lines: [String] = []

        lines.append("---")
        lines.append(self.field("created", message.date.map { self.timestamp($0) }, quoted: false))
        lines.append(self.field("from", message.from))
        lines.append(self.field("to", message.to))
        lines.append(self.field("cc", message.cc))
        lines.append(self.field("via", nil))
        lines.append(self.field("subject", message.subject))
        lines.append(contentsOf: self.attachmentsField(message.attachments))
        lines.append("---")
        lines.append("")
        lines.append(message.body)
        lines.append(contentsOf: self.attachmentBlock(message.attachments))
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

    /// The `attachments` frontmatter, as one or more lines.
    ///
    /// A flow list of plain filenames while the files are only named, a block
    /// list of wikilinks once they exist on disk. The block form is what makes
    /// each attachment a node of its own; the flow form would have to quote the
    /// brackets and reads worse the longer the names get, and vault-schema names
    /// are long.
    func attachmentsField(_ attachments: [Attachment]) -> [String] {
        guard self.linksAttachments, attachments.isEmpty == false else {
            return [self.listField("attachments", attachments.map { $0.name })]
        }

        let items = attachments.map { attachment in
            return "  - \(self.quoted(self.wikilink(attachment.name)))"
        }

        return ["attachments:"] + items
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

// MARK: - The attachment block
extension MarkdownRenderer {

    /// The attachments as the body's closing block: the images in a two-column
    /// table, the documents linked below them. Empty unless the files are on
    /// disk, because a link to a file nobody wrote is a dead link.
    ///
    /// No heading and no rule: a mail client shows the attachments below the
    /// text without announcing them, and the frontmatter has already named them.
    /// No connecting prose either, since the links carry their own labels and
    /// the body takes no commentary.
    ///
    /// A picture the body embeds where the mail placed it is not shown here a
    /// second time.
    func attachmentBlock(_ attachments: [Attachment]) -> [String] {
        let enclosed = attachments.filter { $0.isEmbedded == false }
        guard self.linksAttachments, enclosed.isEmpty == false else {
            return []
        }

        let images = enclosed.filter { $0.isImage }
        let documents = enclosed.filter { $0.isImage == false }
        var lines: [String] = []

        if images.isEmpty == false {
            lines.append("")
            lines.append(contentsOf: self.imageTable(images))
        }

        // Blank-line separated rather than a bullet list: a run of bare
        // wikilinks would fold into one paragraph, and the block is a list of
        // enclosures, not of points.
        for document in documents {
            lines.append("")
            lines.append(self.link(document))
        }

        return lines
    }

    /// The images embedded, two per row.
    ///
    /// Two columns because a phone screenshot series otherwise fills ten
    /// screens, and a table because it is the only way Markdown places two
    /// embeds side by side. The header row is empty on purpose: the columns
    /// carry no meaning, they are a grid.
    func imageTable(_ images: [Attachment]) -> [String] {
        var lines = ["|  |  |", "|---|---|"]

        for index in stride(from: 0, to: images.count, by: 2) {
            let left = self.embed(images[index])
            let right = index + 1 < images.count ? self.embed(images[index + 1]) : ""
            lines.append("| \(left) | \(right) |")
        }

        return lines
    }

    /// An image, shown in place.
    func embed(_ attachment: Attachment) -> String {
        return "!\(self.wikilink(attachment.name))"
    }

    /// A document, linked. It keeps the name the sender gave it as the link's
    /// alias whenever extraction renamed the file, so the note reads as the mail
    /// meant it while the link points where the file actually is.
    func link(_ attachment: Attachment) -> String {
        guard attachment.name != attachment.sourceName else {
            return self.wikilink(attachment.name)
        }
        return self.wikilink(attachment.name, alias: attachment.sourceName)
    }

    /// An Obsidian wikilink, optionally aliased.
    func wikilink(_ target: String, alias: String? = nil) -> String {
        guard let alias else {
            return "[[\(target)]]"
        }
        return "[[\(target)|\(alias)]]"
    }
}
