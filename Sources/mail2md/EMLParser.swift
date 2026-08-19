//
//  EMLParser.swift
//  mail2md
//
//  Created by Anton Fillmann on 07.07.2026.
//

import Foundation

/// A parsed email message with the headers relevant for archiving.
struct EmailMessage {
    let from: String?
    let to: String?
    let subject: String?
    let date: Date?
    // The sender's declared UTC offset: a parsed fact, kept for completeness.
    // `created` renders in the reader's local zone, not in this one.
    let timeZone: TimeZone?
    let messageID: String?
    let body: String
    let attachments: [Attachment]  // attachment parts, in document order
}

// MARK: -

/// An attachment as the note refers to it: the filename it is listed and linked
/// under, plus the media type that decides whether it can be embedded.
///
/// The name is the mail's own filename until the attachment is actually written
/// to disk; from then on it is the name on disk, which is what a link has to
/// point at. `EmailMessage.replacingAttachments` performs that swap.
struct Attachment {
    let name: String
    let mediaType: String

    /// The filename the mail itself carried. It equals `name` until extraction
    /// renames the file, and a link then carries it as its alias, so the note
    /// still says what the sender called the thing.
    let sourceName: String

    init(name: String, mediaType: String, sourceName: String? = nil) {
        self.name = name
        self.mediaType = mediaType
        self.sourceName = sourceName ?? name
    }

    /// Whether the attachment is an image, and can therefore be shown rather
    /// than only linked.
    var isImage: Bool {
        return self.mediaType.hasPrefix("image/")
    }
}

// MARK: -
extension EmailMessage {

    /// The same message with its attachments renamed, keeping their order and
    /// media types. Used after extraction, so the note lists and links the
    /// files that were really written instead of the names the mail carried.
    func replacingAttachments(withNames names: [String]) -> EmailMessage {
        let renamed = zip(self.attachments, names).map { attachment, name in
            return Attachment(name: name, mediaType: attachment.mediaType, sourceName: attachment.sourceName)
        }

        return EmailMessage(
            from: self.from,
            to: self.to,
            subject: self.subject,
            date: self.date,
            timeZone: self.timeZone,
            messageID: self.messageID,
            body: self.body,
            attachments: renamed
        )
    }
}

/// An attachment part located in the MIME tree: its resolved filename (nil when
/// the part carries none), the media type (for an extension fallback), and the
/// still-encoded leaf entity (so its bytes can be decoded on demand).
struct AttachmentPart {
    let filename: String?
    let mediaType: String
    let entity: MIMEEntity
}

/// Parses RFC 5322 (.eml) files.
///
/// Scope: single-part and `multipart/alternative` messages; quoted-printable
/// and base64 transfer encodings; RFC 2047 encoded-word headers.
struct EMLParser {

    func parse(_ raw: String) -> EmailMessage {
        let (headerBlock, rawBody) = self.splitHeadersAndBody(raw)
        let headers = self.parseHeaders(headerBlock)
        let body = self.extractBody(headers: headers, rawBody: rawBody)
        let parsedDate = headers["date"].flatMap { self.parseDate($0) }

        return EmailMessage(
            from: headers["from"].map(decodeRFC2047Header),
            to: headers["to"].map(decodeRFC2047Header),
            subject: headers["subject"].map(decodeRFC2047Header),
            date: parsedDate?.date,
            timeZone: parsedDate?.timeZone,
            messageID: headers["message-id"],
            body: BodyCleaner.clean(body),
            attachments: self.attachments(headers: headers, rawBody: rawBody)
        )
    }
}

// MARK: - MIME body selection
extension EMLParser {

    /// Selects and decodes the best plain-text body for a message.
    func extractBody(headers: [String: String], rawBody: String) -> String {
        return self.plainText(headers: headers, rawBody: rawBody) ?? rawBody
    }

    /// Returns a renderable text body, descending into multipart containers and
    /// preferring `text/plain`; an HTML part is converted to Markdown.
    func plainText(headers: [String: String], rawBody: String) -> String? {
        let contentType = parseContentType(headers["content-type"])

        guard contentType.mediaType.hasPrefix("multipart/") else {
            return self.renderedText(MIMEEntity(headers: headers, rawBody: rawBody))
        }

        guard let boundary = contentType.boundary else {
            return nil
        }
        let entities = self.splitParts(rawBody, boundary: boundary).map { self.parseEntity($0) }

        // 1. Prefer a text/plain part at this level.
        for entity in entities where parseContentType(entity.headers["content-type"]).mediaType == "text/plain" {
            return self.renderedText(entity)
        }

        // 2. Descend into nested multipart containers (e.g. multipart/related).
        for entity in entities where parseContentType(entity.headers["content-type"]).mediaType.hasPrefix("multipart/") {
            if let nested = self.plainText(headers: entity.headers, rawBody: entity.rawBody) {
                return nested
            }
        }

        // 3. Fall back to an HTML part, converted to Markdown.
        for entity in entities where parseContentType(entity.headers["content-type"]).mediaType == "text/html" {
            return self.renderedText(entity)
        }

        return nil
    }

    /// Collects the filenames of attachment parts across the MIME tree.
    ///
    /// Selection rules live in `isUserAttachment`: `Content-Disposition:
    /// attachment`, plus a named `inline` binary that is neither text nor
    /// image and carries no `Content-ID`. S/MIME cryptographic parts are
    /// excluded. The filename comes from the disposition's `filename`
    /// parameter, falling back to the content type's `name`; an attachment
    /// without either is listed as `unnamed` so its presence is not silently
    /// lost.
    func attachments(headers: [String: String], rawBody: String) -> [Attachment] {
        return self.attachmentParts(headers: headers, rawBody: rawBody).map { part in
            return Attachment(name: part.filename ?? "unnamed", mediaType: part.mediaType)
        }
    }

    /// Locates every attachment part in the MIME tree, keeping the encoded leaf
    /// so its bytes can be extracted. Same selection rules as `attachments`
    /// (see `isUserAttachment`), with S/MIME cryptographic parts excluded.
    /// Returned in document order.
    func attachmentParts(headers: [String: String], rawBody: String) -> [AttachmentPart] {
        let contentType = parseContentType(headers["content-type"])
        guard
            contentType.mediaType.hasPrefix("multipart/"),
            let boundary = contentType.boundary
        else {
            return []
        }

        let entities = self.splitParts(rawBody, boundary: boundary).map { self.parseEntity($0) }
        var found: [AttachmentPart] = []
        for entity in entities {
            let entityType = parseContentType(entity.headers["content-type"])

            if entityType.mediaType.hasPrefix("multipart/") {
                found += self.attachmentParts(headers: entity.headers, rawBody: entity.rawBody)
                continue
            }

            // S/MIME signatures/envelopes are attachment-disposed but are
            // cryptographic machinery, not user attachments.
            if entityType.isSMIMEArtifact {
                continue
            }

            let disposition = parseContentDisposition(entity.headers["content-disposition"])
            let filename = disposition.filename ?? entityType.parameters["name"].map(decodeRFC2047Header)
            guard
                self.isUserAttachment(
                    disposition: disposition.type,
                    type: entityType,
                    filename: filename,
                    headers: entity.headers
                )
            else {
                continue
            }

            let attachmentPart = AttachmentPart(filename: filename, mediaType: entityType.mediaType, entity: entity)
            found.append(attachmentPart)
        }

        return found
    }

    /// Decides whether a leaf part is a user attachment.
    ///
    /// `Content-Disposition: attachment` always qualifies. `inline` qualifies
    /// too, but only for a named binary that is not an image: Apple Mail sends
    /// genuine document attachments as `inline; filename="….pdf"`, and such a
    /// part used to vanish from both the listing and the extraction without a
    /// word (the PDF sent to the immigration office, 2026-07-22).
    ///
    /// Images stay out even when they are named. Inline images are body
    /// furniture, signature logos and tracking pixels, and `signature.png` has
    /// a regression test saying so since v0.5.0. The cost is a known one: a
    /// photo dragged into an Apple Mail body also arrives as a named inline
    /// image and is still not listed.
    ///
    /// `Content-ID` excludes on top of that, for the rarer mailer that embeds a
    /// non-image part and references it from the HTML via `cid:`.
    func isUserAttachment(disposition: String, type: ContentType, filename: String?, headers: [String: String]) -> Bool {
        if disposition == "attachment" {
            return true
        }
        guard disposition == "inline", filename != nil else {
            return false
        }
        guard headers["content-id"] == nil else {
            return false
        }

        return ["text/", "multipart/", "image/"].contains { type.mediaType.hasPrefix($0) } == false
    }

    /// Locates the attachment parts of a whole raw message, for extraction.
    func attachmentParts(from raw: String) -> [AttachmentPart] {
        let (headerBlock, rawBody) = self.splitHeadersAndBody(raw)
        return self.attachmentParts(headers: self.parseHeaders(headerBlock), rawBody: rawBody)
    }

    /// Decodes a leaf entity and, if it is `text/html`, converts it to Markdown.
    func renderedText(_ entity: MIMEEntity) -> String {
        let decoded = self.decodeLeaf(entity)
        if parseContentType(entity.headers["content-type"]).mediaType == "text/html" {
            return HTMLToMarkdown.convert(decoded)
        }
        return decoded
    }

    /// Decodes a leaf entity's body according to its transfer encoding and charset.
    func decodeLeaf(_ entity: MIMEEntity) -> String {
        let encoding = (entity.headers["content-transfer-encoding"] ?? "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let charset = stringEncoding(for: parseContentType(entity.headers["content-type"]).charset)

        switch encoding {
        case "quoted-printable":
            return decodeQuotedPrintable(entity.rawBody, encoding: charset)
        case "base64":
            return decodeBase64(entity.rawBody, encoding: charset)
        default:  // 7bit, 8bit, binary, or absent
            return entity.rawBody
        }
    }

    /// Splits a multipart body into its parts, dropping preamble and epilogue.
    func splitParts(_ body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        var parts: [String] = []
        var current: [String]?

        let lines = body.components(separatedBy: "\n")
        for line in lines {
            let marker = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))

            if marker == delimiter {
                if let current {
                    parts.append(current.joined(separator: "\n"))
                }
                current = []
                continue
            }
            if marker == delimiter + "--" {
                if let current {
                    parts.append(current.joined(separator: "\n"))
                }
                current = nil
                break
            }
            current?.append(line)
        }

        return parts
    }

    /// Parses one MIME part into headers and its still-encoded body.
    func parseEntity(_ raw: String) -> MIMEEntity {
        let (headerBlock, body) = self.splitHeadersAndBody(raw)
        return MIMEEntity(headers: self.parseHeaders(headerBlock), rawBody: body)
    }
}

// MARK: -
extension EMLParser {

    /// Splits the raw message at the first empty line into header block and body.
    func splitHeadersAndBody(_ raw: String) -> (headers: String, body: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")

        guard let separatorRange = normalized.range(of: "\n\n") else {
            return (normalized, "")
        }

        let headers = String(normalized[..<separatorRange.lowerBound])
        let body = String(normalized[separatorRange.upperBound...])
        return (headers, body)
    }

    /// Parses the header block into a dictionary with lowercased header names.
    /// Folded headers (continuation lines starting with whitespace) are unfolded.
    func parseHeaders(_ headerBlock: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentName: String?

        let lines = headerBlock.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation of the previous header (RFC 5322 folding)
                if let name = currentName, let value = headers[name] {
                    headers[name] = value + " " + line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }

            let name = String(line[..<colonIndex]).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
            currentName = name
        }

        return headers
    }

    /// Numeric offsets for the obsolete alphabetic zone names of RFC 5322 §4.3.
    /// Real mailers still emit them, and `DateFormatter` only understands a few;
    /// mapping them to offsets keeps a single set of `Z` formats sufficient.
    static let obsoleteZoneOffsets: [String: String] = [
        "UT":  "+0000", "GMT": "+0000",
        "EST": "-0500", "EDT": "-0400",
        "CST": "-0600", "CDT": "-0500",
        "MST": "-0700", "MDT": "-0600",
        "PST": "-0800", "PDT": "-0700",
    ]

    /// Parses an RFC 5322 date header (e.g. "Mon, 15 Jun 2026 09:41:00 +0200"),
    /// returning both the absolute instant and the sender's UTC offset.
    ///
    /// Tolerates the shapes real mail servers emit beyond the canonical one: a
    /// trailing comment (`+0000 (UTC)`), a missing weekday, a missing seconds
    /// field, and the obsolete alphabetic zone names. A header that still fails
    /// to parse yields nil rather than a guessed instant: a wrong timestamp is
    /// worse than a missing one.
    func parseDate(_ value: String) -> (date: Date, timeZone: TimeZone)? {
        let normalized = self.normalizedDateValue(value)

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm Z",
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format

            if let date = formatter.date(from: normalized) {
                return (date, self.timeZone(from: normalized) ?? .current)
            }
        }

        return nil
    }

    /// Reduces a date header to the canonical shape the formats expect: comments
    /// removed (they may carry digits that would confuse the offset scan),
    /// whitespace collapsed, and a trailing alphabetic zone replaced by its
    /// numeric offset.
    func normalizedDateValue(_ value: String) -> String {
        var text = value
            .replacing(/\([^)]*\)/, with: " ")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)

        if let match = text.firstMatch(of: /\s([A-Za-z]{1,3})$/),
           let offset = Self.obsoleteZoneOffsets[String(match.output.1).uppercased()] {
            text.replaceSubrange(match.range, with: " " + offset)
        }

        return text
    }

    /// Extracts the numeric UTC offset (e.g. "+0200") from a date header.
    func timeZone(from value: String) -> TimeZone? {
        guard let match = value.firstMatch(of: /[+-]\d{4}/) else {
            return nil
        }

        let token = String(match.output)
        let sign = token.hasPrefix("-") ? -1 : 1
        let digits = token.dropFirst()
        let hours = Int(digits.prefix(2)) ?? 0
        let minutes = Int(digits.suffix(2)) ?? 0
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}
