//
//  AttachmentNaming.swift
//  mail2md
//
//  Created by Anton Fillmann on 19.08.2026.
//

import Foundation

/// Renames an extracted attachment after a caller-supplied pattern.
///
/// The tool deliberately knows no naming scheme of its own. The scheme comes in
/// from the outside, so a vault can ask for `2026.08.18 07.52 ENCL Foto.JPG`
/// while mail2md stays agnostic: it only knows the mail's date, the attachment's
/// own name, and where the caller wants those to sit.
///
/// Four placeholders, and `date`/`time` take an optional `DateFormatter` pattern
/// after a colon (`{date:yyyy.MM.dd}`):
///
/// - `{name}` the attachment's filename without its extension
/// - `{ext}` its extension including the dot, or empty
/// - `{date}` the mail's date, `yyyy-MM-dd` by default
/// - `{time}` the mail's time, `HH-mm` by default
///
/// A pattern that does not place `{ext}` itself gets the extension appended, so
/// the common case stays short: `{date} {time} ENCL {name}`.
struct AttachmentNaming {
    let pattern: String

    /// The mail's own date, which is what the placeholders render. An
    /// attachment sorts behind the mail it came with, so the mail's timestamp is
    /// the one that belongs in its name, never the file's and never today's.
    ///
    /// Nil when the mail carries no parsable `Date:` header, in which case
    /// `{date}` and `{time}` render as nothing. The CLI refuses such a pattern
    /// before it gets here rather than writing a name with a hole in it; a
    /// library caller that allows it gets the empty rendering.
    let date: Date?

    /// The zone the timestamp renders in. Same default and same reasoning as
    /// `MarkdownRenderer`: local wall-clock, so the filename and the note's
    /// `created` cannot drift apart.
    let timeZone: TimeZone

    /// The parsed pattern, with every `{date}`/`{time}` already rendered into a
    /// literal. Parsing and formatting happen once here rather than per
    /// attachment, so `apply` is plain concatenation and a mail with nineteen
    /// attachments still builds a single `DateFormatter`.
    fileprivate let _segments: [Segment]

    init(pattern: String, date: Date?, timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        self.pattern = pattern
        self.date = date
        self.timeZone = timeZone
        self._segments = Self.segments(of: pattern).map { segment in
            guard case .placeholder(let placeholder, let format) = segment, let defaultFormat = placeholder.defaultFormat else {
                return segment
            }
            guard let date else {
                return .literal("")
            }
            formatter.dateFormat = format ?? defaultFormat
            return .literal(formatter.string(from: date))
        }
    }

    /// The placeholders a pattern may use.
    enum Placeholder: String {
        case name
        case ext
        case date
        case time

        /// The `DateFormatter` pattern used when the placeholder carries no
        /// explicit one. Both defaults are filesystem-safe: no colon, no slash.
        var defaultFormat: String? {
            switch self {
            case .date:
                return "yyyy-MM-dd"
            case .time:
                return "HH-mm"
            case .name, .ext:
                return nil
            }
        }
    }

    /// One piece of a parsed pattern.
    enum Segment {
        case literal(String)
        case placeholder(Placeholder, format: String?)
        /// A `{…}` token naming no known placeholder, kept so a caller can
        /// reject the typo instead of writing it into a filename.
        case unknown(String)
    }
}

// MARK: - Parsing
extension AttachmentNaming {

    /// Splits `pattern` into literals and placeholders, in order.
    ///
    /// A `{` without a closing `}` is a literal `{`, which keeps the parse total:
    /// every pattern yields segments, and no input can fail here.
    static func segments(of pattern: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var index = pattern.startIndex

        while index < pattern.endIndex {
            guard
                pattern[index] == "{",
                let close = pattern[index...].firstIndex(of: "}")
            else {
                literal.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }

            if literal.isEmpty == false {
                segments.append(.literal(literal))
                literal = ""
            }

            let token = String(pattern[pattern.index(after: index)..<close])
            segments.append(Self.segment(for: token))
            index = pattern.index(after: close)
        }

        if literal.isEmpty == false {
            segments.append(.literal(literal))
        }

        return segments
    }

    /// The segment a `{…}` token denotes: a placeholder with its optional
    /// format, or `unknown` when the name is not one of the four.
    private static func segment(for token: String) -> Segment {
        guard let colon = token.firstIndex(of: ":") else {
            guard let placeholder = Placeholder(rawValue: token) else {
                return .unknown(token)
            }
            return .placeholder(placeholder, format: nil)
        }

        let name = String(token[token.startIndex..<colon])
        let format = String(token[token.index(after: colon)...])
        guard let placeholder = Placeholder(rawValue: name) else {
            return .unknown(token)
        }

        return .placeholder(placeholder, format: format.isEmpty ? nil : format)
    }

    /// Every `{…}` token in `pattern` that names no known placeholder, in the
    /// order it appears. A caller uses this to reject a typo before it becomes
    /// a filename.
    static func unknownPlaceholders(in pattern: String) -> [String] {
        return Self.segments(of: pattern).compactMap { segment in
            guard case .unknown(let token) = segment else {
                return nil
            }
            return token
        }
    }

    /// Whether `pattern` renders the mail's date, and therefore cannot be used
    /// on a mail whose `Date:` header is missing or unparsable.
    static func requiresDate(_ pattern: String) -> Bool {
        return Self.segments(of: pattern).contains { segment in
            guard case .placeholder(let placeholder, _) = segment else {
                return false
            }
            return placeholder == .date || placeholder == .time
        }
    }
}

// MARK: - Applying
extension AttachmentNaming {

    /// The pattern filled in for `filename`.
    ///
    /// The result is a bare filename: any `/` a pattern smuggles in becomes `-`,
    /// because a name is never allowed to steer the write into another
    /// directory. Unknown placeholders survive verbatim; `Mail2md` rejects them
    /// before extraction starts, so they cannot reach a real file.
    func apply(to filename: String) -> String {
        let (stem, fileExtension) = self.split(filename)
        var result = ""

        for segment in self._segments {
            switch segment {
            case .literal(let text):
                result += text
            case .placeholder(.ext, _):
                result += self.dotted(fileExtension)
            case .placeholder:
                // Only `{name}` reaches here: `{date}`/`{time}` became literals
                // in `init`, and `{ext}` is handled above.
                result += stem
            case .unknown(let token):
                result += "{\(token)}"
            }
        }

        if self.placesExtension() == false {
            result += self.dotted(fileExtension)
        }

        return result.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
    }

    /// Whether the pattern positions `{ext}` itself. When it does not, `apply`
    /// appends the extension, so `{date} {time} ENCL {name}` still yields a
    /// file the Finder and Obsidian can open.
    private func placesExtension() -> Bool {
        return self._segments.contains { segment in
            guard case .placeholder(.ext, _) = segment else {
                return false
            }
            return true
        }
    }

    /// An extension with its leading dot, or the empty string.
    private func dotted(_ fileExtension: String) -> String {
        guard fileExtension.isEmpty == false else {
            return ""
        }
        return ".\(fileExtension)"
    }

    /// Splits a filename into its stem and its extension (without the dot).
    ///
    /// Cut from the string rather than through a `URL`, for the reason spelled
    /// out in `AttachmentExtractor.safeName`: `URL(string:)` swallows a `#`, and
    /// `URL(fileURLWithPath:)` resolves relative names against the working
    /// directory. A leading dot stays part of the stem, so `.gitignore` keeps
    /// its name instead of turning into a bare extension.
    private func split(_ filename: String) -> (stem: String, ext: String) {
        guard
            let dot = filename.lastIndex(of: "."),
            dot != filename.startIndex,
            dot != filename.index(before: filename.endIndex)
        else {
            return (filename, "")
        }

        let stem = String(filename[filename.startIndex..<dot])
        let fileExtension = String(filename[filename.index(after: dot)...])

        return (stem, fileExtension)
    }
}
