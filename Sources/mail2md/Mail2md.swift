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
    static let version = "1.0.0"

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

    @Flag(name: .long, help: "Write attachment files (next to the output, or into --attachments-dir).")
    var extractAttachments = false

    @Option(name: .long, help: "Directory for extracted attachments; implies --extract-attachments. Defaults next to the output.")
    var attachmentsDir: String?

    @Argument(help: "Path to an .eml file.")
    var path: String

    mutating func run() throws {
        let inputURL = URL(fileURLWithPath: self.path)

        guard FileManager.default.fileExists(atPath: self.path) else {
            printIf(true, "mail2md: \(self.path): No such file")
            throw ExitCode.failure
        }

        let raw = try String(contentsOf: inputURL, encoding: .utf8)
        let message = EMLParser().parse(raw)
        let outputPath = self.output ?? inputURL.deletingPathExtension().appendingPathExtension("md").path

        // An empty `created` is silent data loss in the vault: warn unconditionally
        // rather than only under --verbose.
        if message.date == nil {
            printIf(true, "mail2md: \(self.path): missing or unparsable Date header (created left empty)")
        }

        // One .eml converts to exactly one Markdown file. A quoted reply chain
        // stays in that single file (as the mail itself keeps it); the semantic
        // per-message split is the consumer's job, not this stateless converter's.
        let document = MarkdownWriter.Document(
            url: URL(fileURLWithPath: outputPath),
            content: MarkdownRenderer().render(message)
        )

        do {
            let written = try MarkdownWriter(force: self.force).writeAll([document])
            printIf(self.verbose, "mail2md: \(self.path) → \(outputPath) (\(written.isEmpty ? "unchanged" : "written"))")
        }
        catch let conflict as MarkdownWriter.Conflict {
            printIf(true, "mail2md: \(conflict.path): differs from generated output (use --force to overwrite)")
            throw ExitCode.failure
        }

        if self.extractAttachments || self.attachmentsDir != nil {
            try self.extract(from: raw, outputPath: outputPath)
        }
    }

    /// Writes the message's attachments, either into `--attachments-dir` or
    /// alongside the output Markdown.
    private func extract(from raw: String, outputPath: String) throws {
        let parts = EMLParser().attachmentParts(from: raw)
        let directory = self.attachmentsDir.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: outputPath).deletingLastPathComponent()

        let written = try AttachmentExtractor(directory: directory).extract(parts)
        printIf(self.verbose, "mail2md: extracted \(written.count) attachment(s) to \(directory.path)")
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
