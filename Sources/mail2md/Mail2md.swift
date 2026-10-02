//
//  Mail2md.swift
//  mail2md
//
//  Created by Anton Fillmann on 07.07.2026.
//

import ArgumentParser
import Foundation

@main
struct Mail2md: ParsableCommand {
    static let appname = "mail2md"
    static let abstract = "Convert .eml files to Markdown with YAML frontmatter."
    static let version = "1.2.0"

    static let configuration = CommandConfiguration(
        commandName: Self.appname,
        abstract: Self.abstract,
        version: Self.version
    )

    @Option(name: .shortAndLong, help: "Output file path. Defaults to the input path with .md extension.")
    var output: String?

    @Flag(name: .shortAndLong, help: "Show detailed information.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Overwrite existing output files that differ from the generated Markdown.")
    var force = false

    @Flag(name: .long, help: "Write attachment files (next to the output, or into --attachments-dir) and link them from the note.")
    var extractAttachments = false

    @Option(name: .long, help: "Directory for extracted attachments; implies --extract-attachments. Defaults next to the output.")
    var attachmentsDir: String?

    @Option(name: .long, help: "Rename extracted attachments after a pattern, e.g. \"{date} {time} ENCL {name}\"; placeholders are {name}, {ext}, {date} and {time}, the latter two with an optional format ({date:yyyy.MM.dd}). Implies --extract-attachments.")
    var attachmentName: String?

    @Argument(help: "Path to an .eml file.")
    var path: String

    /// A planned extraction: which parts go where, and under which names.
    ///
    /// Planned rather than performed, because the note has to link the files by
    /// the names they will carry while still being written first: a conflicting
    /// note aborts the run, and it must do so before anything lands on disk.
    private struct Extraction {
        let parts: [AttachmentPart]
        let extractor: AttachmentExtractor
        let names: [String]
    }

    mutating func run() throws {
        let inputURL = URL(fileURLWithPath: self.path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: self.path, isDirectory: &isDirectory)

        guard exists else {
            printIf(true, "mail2md: \(self.path): No such file")
            throw ExitCode.failure
        }

        guard isDirectory.boolValue == false else {
            printIf(true, "mail2md: \(self.path): Is a directory")
            throw ExitCode.failure
        }

        let (parser, raw) = try self.read(inputURL)
        let message = parser.parse(raw)
        let outputPath = self.output ?? inputURL.deletingPathExtension().appendingPathExtension("md").path

        // An empty `created` is silent data loss in the vault: warn unconditionally
        // rather than only under --verbose.
        if message.date == nil {
            printIf(true, "mail2md: \(self.path): missing or unparsable Date header (created left empty)")
        }

        // Removing characters changes what the note says, and what was kept may
        // still hide something, so both are reported without being asked.
        if message.invisibleCharacters.isEmpty == false {
            printIf(true, "mail2md: \(self.path): \(message.invisibleCharacters.summary)")
        }

        // Extraction is only planned here. The note is written first, so a
        // conflict aborts before any attachment file exists, but it already
        // links the attachments by the names the plan gives them.
        let extraction = try self.planExtraction(from: raw, parser: parser, date: message.date, outputPath: outputPath)
        let noted = extraction.map { message.replacingAttachments(withNames: $0.names) } ?? message

        // One .eml converts to exactly one Markdown file. A quoted reply chain
        // stays in that single file (as the mail itself keeps it); the semantic
        // per-message split is the consumer's job, not this stateless converter's.
        let renderer = MarkdownRenderer(linksAttachments: extraction != nil)
        let document = MarkdownWriter.Document(
            url: URL(fileURLWithPath: outputPath),
            content: renderer.render(noted)
        )

        do {
            let written = try MarkdownWriter(force: self.force).writeAll([document])
            printIf(self.verbose, "mail2md: \(self.path) → \(outputPath) (\(written.isEmpty ? "unchanged" : "written"))")
        }
        catch let conflict as MarkdownWriter.Conflict {
            printIf(true, "mail2md: \(conflict.path): differs from generated output (use --force to overwrite)")
            throw ExitCode.failure
        }

        if let extraction {
            let written = try extraction.extractor.extract(extraction.parts)
            printIf(self.verbose, "mail2md: extracted \(written.count) attachment(s) to \(extraction.extractor.directory.path)")
        }
    }

    /// Reads the input file as a mail: as UTF-8 text when it is, otherwise byte
    /// for byte in the charsets it declares (`EMLParser.reading`).
    ///
    /// Foundation's own failure is unusable as CLI output: it names no path, it is
    /// localized, and it does not follow this tool's `mail2md: <path>: <message>`
    /// shape. So both ways this can fail are translated into that shape, and the
    /// underlying reason stays available under `--verbose` (v1.0.2, found by the
    /// acceptance tests: no library test can see what the command prints).
    private func read(_ url: URL) throws -> (parser: EMLParser, raw: String) {
        let data: Data

        do {
            data = try Data(contentsOf: url)
        }
        catch {
            printIf(true, "mail2md: \(self.path): cannot be read")
            printIf(self.verbose, "mail2md: \(self.path): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        guard let reading = EMLParser.reading(data) else {
            printIf(true, "mail2md: \(self.path): not valid UTF-8 text, nor in a charset it declares")
            throw ExitCode.failure
        }
        if reading.parser.source != .utf8 {
            printIf(self.verbose, "mail2md: \(self.path): not UTF-8, read byte for byte in the charsets it declares")
        }

        return reading
    }

    /// Plans the attachment extraction, or nil when none was asked for.
    ///
    /// The three attachment options all ask for extraction: naming or a target
    /// directory is meaningless without it. Throws when the pattern names a
    /// placeholder that does not exist, since that would otherwise end up
    /// verbatim in a filename.
    private func planExtraction(from raw: String, parser: EMLParser, date: Date?, outputPath: String) throws -> Extraction? {
        guard self.extractAttachments || self.attachmentsDir != nil || self.attachmentName != nil else {
            return nil
        }

        let parts = parser.attachmentParts(from: raw)
        let directory = self.attachmentsDir.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: outputPath).deletingLastPathComponent()
        let extractor = AttachmentExtractor(directory: directory, naming: try self.naming(for: date))

        return Extraction(parts: parts, extractor: extractor, names: extractor.plannedNames(parts))
    }

    /// The naming built from `--attachment-name`, or nil when no pattern was
    /// given or the mail cannot supply what the pattern asks for.
    ///
    /// A pattern that renders the mail's date needs one, and a mail without a
    /// parsable `Date:` header has none. Rather than writing a filename with a
    /// hole in it, the run says so and falls back to the attachments' own names.
    private func naming(for date: Date?) throws -> AttachmentNaming? {
        guard let pattern = self.attachmentName else {
            return nil
        }

        let unknown = AttachmentNaming.unknownPlaceholders(in: pattern)
        guard unknown.isEmpty else {
            printIf(true, "mail2md: {\(unknown.joined(separator: "}, {"))}: unknown placeholder in --attachment-name")
            throw ExitCode.failure
        }

        if date == nil, AttachmentNaming.requiresDate(pattern) {
            printIf(true, "mail2md: \(self.path): --attachment-name needs the mail's date (attachments keep their own names)")
            return nil
        }

        return AttachmentNaming(pattern: pattern, date: date)
    }
}

// MARK: -

/// The stream a message is written to.
enum MessageStream {
    case standardOutput
    case standardError
}

/// Prints `message` when `condition` holds.
///
/// The default stream is stderr, because everything this tool prints is
/// diagnostics: the actual product is the Markdown file it writes. Keeping
/// stdout empty means `2>/dev/null` silences the noise and nothing else, and it
/// leaves the channel free for the planned stdout piping (`cat x.eml | mail2md`).
func printIf(_ condition: Bool, _ message: String, to stream: MessageStream = .standardError) {
    guard condition else {
        return
    }

    switch stream {
    case .standardOutput:
        print(message)
    case .standardError:
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
