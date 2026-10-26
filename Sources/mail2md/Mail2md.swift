//
//  Mail2md.swift
//  mail2md
//
//  Created by Anton Fillmann on 07.07.2026.
//

import CommandLineOptions
import Foundation

@main
struct Mail2md: Equatable {
    static let appname = "mail2md"
    static let abstract = "Convert .eml files to Markdown with YAML frontmatter."
    static let version = "1.5.0"

    // What each option does is said once, in `helpPage`.
    var output: String? = nil
    var verbose = false
    var force = false
    var extractAttachments = false
    var attachmentsDir: String? = nil
    var attachmentName: String? = nil
    var inlineImages = false
    var format = OutputFormat.markdown
    var path: String

    /// A planned extraction: which parts go where, and under which names.
    ///
    /// Planned rather than performed, because the note has to link the files by
    /// the names they will carry while still being written first: a conflicting
    /// note aborts the run, and it must do so before anything lands on disk.
    private struct Extraction {
        let parts: [AttachmentPart]
        let extractor: AttachmentExtractor

        /// What the note lists, in the order of `parts`, under the names the
        /// files will carry.
        let attachments: [Attachment]

        /// The file each picture the body shows is embedded from, by the
        /// `Content-ID` of its part.
        let imageNames: [String: String]
    }

    func run() throws {
        let (reader, raw) = try self.read()
        let parser = EMLParser(source: reader.source, format: self.format)
        let reading = parser.parse(raw)

        // An empty `created` is silent data loss in the vault: warn unconditionally
        // rather than only under --verbose.
        if reading.date == nil {
            printIf(true, "mail2md: \(self.inputName): missing or unparsable Date header (created left empty)")
        }

        // Extraction is only planned here. The note is written first, so a
        // conflict aborts before any attachment file exists, but it already
        // links the attachments by the names the plan gives them. A picture
        // the body shows is embedded under the name of its file, and the first
        // reading is what says which pictures it shows, so the body is read
        // once more with those names.
        let extraction = try self.planExtraction(from: raw, parser: parser, message: reading)
        let imageNames = extraction?.imageNames ?? [:]
        let message = imageNames.isEmpty ? reading : EMLParser(source: parser.source, imageNames: imageNames, format: self.format).parse(raw)
        let noted = extraction.map { message.replacingAttachments(with: $0.attachments) } ?? message

        // Removing characters changes what the note says, and what was kept may
        // still hide something, so both are reported without being asked.
        if message.invisibleCharacters.isEmpty == false {
            printIf(true, "mail2md: \(self.inputName): \(message.invisibleCharacters.summary)")
        }

        // A picture left out of the note may be its point, a screenshot, and
        // only a reader can tell it from a logo, so each one is named.
        let omissions = self.inlineImages ? [] : self.omissions(of: message, raw: raw, parser: parser)
        if omissions.isEmpty == false {
            printIf(true, "mail2md: \(self.inputName): \(InlineImage.summary(omissions)) (use --inline-images to include them)")
        }

        // One .eml converts to exactly one Markdown file. A quoted reply chain
        // stays in that single file (as the mail itself keeps it); the semantic
        // per-message split is the consumer's job, not this stateless converter's.
        let renderer = MarkdownRenderer(linksAttachments: extraction != nil)
        try self.write(renderer.render(noted))

        if let extraction {
            do {
                let written = try extraction.extractor.extract(extraction.parts)
                printIf(self.verbose, "mail2md: extracted \(written.count) attachment(s) to \(extraction.extractor.directory.path)")
            }
            catch {
                self.reportWriteFailure(at: extraction.extractor.directory.path, error)
                throw Failure()
            }
        }
    }

    /// Writes the note where `destination` says: into its file, unless that
    /// already holds something else, or to stdout.
    private func write(_ content: String) throws {
        let writer = MarkdownWriter(force: self.force)

        switch self.destination {
        case .file(let outputPath):
            let document = MarkdownWriter.Document(url: URL(fileURLWithPath: outputPath), content: content)

            do {
                let written = try writer.writeAll([document])
                printIf(self.verbose, "mail2md: \(self.inputName) → \(outputPath) (\(written.isEmpty ? "unchanged" : "written"))")
            }
            catch let conflict as MarkdownWriter.Conflict {
                printIf(true, "mail2md: \(conflict.path): differs from generated output (use --force to overwrite)")
                throw Failure()
            }
            catch {
                // Named the way the conflict above names it, so one file is not
                // reported under two paths.
                self.reportWriteFailure(at: document.url.path, error)
                throw Failure()
            }
        case .standardOutput:
            do {
                try writer.writeToStandardOutput(content)
                printIf(self.verbose, "mail2md: \(self.inputName) → (standard output)")
            }
            catch {
                self.reportWriteFailure(at: "(standard output)", error)
                throw Failure()
            }
        }
    }

    /// Reports a file that could not be written, in the shape `read()` reports
    /// one that could not be read, and for the same reason: Foundation's own text
    /// names no path the way this tool does and is localized, so it stays behind
    /// `--verbose`. Until 1.4.0 ArgumentParser printed it as `Error: …`.
    private func reportWriteFailure(at path: String, _ error: Error) {
        printIf(true, "mail2md: \(path): cannot be written")
        printIf(self.verbose, "mail2md: \(path): \(error.localizedDescription)")
    }

    /// Reads the mail, from its file or from stdin: as UTF-8 text when it is,
    /// otherwise byte for byte in the charsets it declares (`EMLParser.reading`).
    ///
    /// Foundation's own failure is unusable as CLI output: it names no path, it is
    /// localized, and it does not follow this tool's `mail2md: <path>: <message>`
    /// shape. So every way this can fail is translated into that shape, and the
    /// underlying reason stays available under `--verbose` (v1.0.2, found by the
    /// acceptance tests: no library test can see what the command prints).
    private func read() throws -> (parser: EMLParser, raw: String) {
        let data: Data
        if self.readsStandardInput {
            data = try self.standardInputData()
        }
        else {
            data = try self.fileData()
        }

        guard let reading = EMLParser.reading(data) else {
            printIf(true, "mail2md: \(self.inputName): not valid UTF-8 text, nor in a charset it declares")
            throw Failure()
        }
        if reading.parser.source != .utf8 {
            printIf(self.verbose, "mail2md: \(self.inputName): not UTF-8, read byte for byte in the charsets it declares")
        }

        return reading
    }

    /// The bytes of the input file, after the two checks Foundation would
    /// answer in its own words: that the file exists, and that it is no directory.
    private func fileData() throws -> Data {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: self.path, isDirectory: &isDirectory)

        guard exists else {
            printIf(true, "mail2md: \(self.path): No such file")
            throw Failure()
        }

        guard isDirectory.boolValue == false else {
            printIf(true, "mail2md: \(self.path): Is a directory")
            throw Failure()
        }

        do {
            return try Data(contentsOf: URL(fileURLWithPath: self.path))
        }
        catch {
            self.reportReadFailure(error)
            throw Failure()
        }
    }

    /// Everything on stdin, up to its end. Nothing at all is an empty mail, as an
    /// empty file is.
    private func standardInputData() throws -> Data {
        do {
            return try FileHandle.standardInput.readToEnd() ?? Data()
        }
        catch {
            self.reportReadFailure(error)
            throw Failure()
        }
    }

    private func reportReadFailure(_ error: Error) {
        printIf(true, "mail2md: \(self.inputName): cannot be read")
        printIf(self.verbose, "mail2md: \(self.inputName): \(error.localizedDescription)")
    }

    /// Plans the attachment extraction, or nil when none was asked for.
    ///
    /// The three attachment options and `--inline-images` all ask for
    /// extraction: naming or a target directory is meaningless without it, and
    /// so is a picture embedded from a file nobody wrote. Throws when the
    /// pattern names a placeholder that does not exist, since that would
    /// otherwise end up verbatim in a filename.
    ///
    /// The pictures are planned after the attachments, so where two files
    /// would collide, an attachment keeps the name it has without them. A
    /// picture whose part is an attachment of its own is planned once, as that
    /// attachment, and embedded all the same.
    private func planExtraction(from raw: String, parser: EMLParser, message: EmailMessage) throws -> Extraction? {
        guard self.extractsAttachments else {
            return nil
        }

        let shown = self.inlineImages ? Set(message.inlineImages.map { $0.contentID }) : []
        let pictureParts = self.inlineImages ? parser.inlineImageParts(of: message.inlineImages, from: raw).map { $0.part } : []
        let parts = parser.attachmentParts(from: raw) + pictureParts
        let directory = try self.attachmentsDirectory()
        let extractor = AttachmentExtractor(directory: directory, naming: try self.naming(for: message.date))
        let names = extractor.plannedNames(parts)

        var attachments: [Attachment] = []
        var imageNames: [String: String] = [:]
        for (part, name) in zip(parts, names) {
            let isEmbedded = part.contentID.map { shown.contains($0) } ?? false
            let attachment = Attachment(name: name, mediaType: part.mediaType, sourceName: part.filename ?? "unnamed", isEmbedded: isEmbedded)
            attachments.append(attachment)

            if isEmbedded, let contentID = part.contentID {
                imageNames[contentID] = name
            }
        }

        return Extraction(parts: parts, extractor: extractor, attachments: attachments, imageNames: imageNames)
    }

    /// The directory extracted files go to: the one `--attachments-dir` names,
    /// else the one the note is written to.
    ///
    /// A note on stdout is written to no directory, so `invocation(from:)`
    /// refuses extraction there without `--attachments-dir`. The check stands
    /// here as well, so that no command writes files into a directory nobody
    /// named.
    private func attachmentsDirectory() throws -> URL {
        if let attachmentsDir = self.attachmentsDir {
            return URL(fileURLWithPath: attachmentsDir)
        }
        guard case .file(let outputPath) = self.destination else {
            printIf(true, "mail2md: \(Self.attachmentsNeedDirectory)")
            throw Failure()
        }
        return URL(fileURLWithPath: outputPath).deletingLastPathComponent()
    }

    /// The pictures from parts of the mail that the body shows and the note
    /// leaves out, each with the size a browser shows it at.
    private func omissions(of message: EmailMessage, raw: String, parser: EMLParser) -> [InlineImage.Omission] {
        return parser.inlineImageParts(of: message.inlineImages, from: raw).map { image, part in
            // The picture's own size counts only for a side the HTML leaves
            // open, and reading it decodes the whole picture.
            let isOpen = image.width == nil || image.height == nil
            let natural = isOpen ? PixelSize(of: decodeToBytes(part.entity)) : nil

            return InlineImage.Omission(name: part.filename ?? "unnamed", size: image.displaySize(natural: natural))
        }
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
            throw Failure()
        }

        if date == nil, AttachmentNaming.requiresDate(pattern) {
            printIf(true, "mail2md: \(self.inputName): --attachment-name needs the mail's date (attachments keep their own names)")
            return nil
        }

        return AttachmentNaming(pattern: pattern, date: date)
    }
}

// MARK: - Input and output
extension Mail2md {

    /// Where the note goes.
    enum Destination: Equatable {
        case file(String)
        case standardOutput
    }

    /// `-` as the path reads the mail from stdin, as `cat -` and `tar -f -` do.
    /// Only the dash does: run by an agent, stdin can be an open socket that
    /// never ends (measured in Claude Code's shell on 2026-10-19), and a tool
    /// that read stdin whenever the path is missing would wait there instead of
    /// saying that the path is missing.
    var readsStandardInput: Bool {
        return self.path == "-"
    }

    /// How messages name the input: its path, or `(standard input)`, the name
    /// POSIX gives it in the output of `grep`.
    var inputName: String {
        if self.readsStandardInput {
            return "(standard input)"
        }
        return self.path
    }

    /// The file `--output` names, else the input's path with `.md`; stdout for
    /// `--output -`, and for a mail read from stdin unless `--output` names a file.
    var destination: Destination {
        if let output = self.output {
            if output == "-" {
                return .standardOutput
            }
            return .file(output)
        }
        if self.readsStandardInput {
            return .standardOutput
        }
        return .file(URL(fileURLWithPath: self.path).deletingPathExtension().appendingPathExtension("md").path)
    }

    /// Whether the run writes files besides the note. Each of the four options
    /// asks for it: naming files, a directory for them or pictures embedded from
    /// them are meaningless without the files.
    var extractsAttachments: Bool {
        return self.extractAttachments || self.attachmentsDir != nil || self.attachmentName != nil || self.inlineImages
    }

    /// Why a note on stdout cannot take attachments along without being told
    /// where: it is written to no directory they could go next to, and the
    /// working directory would be a guess.
    static let attachmentsNeedDirectory = "attachments need --attachments-dir when the note goes to standard output"
}

// MARK: - Command line
extension Mail2md {

    /// What a command line asks for.
    enum Invocation: Equatable {
        case help
        case version
        case run(Mail2md)
    }

    /// A command line the command refuses before anything ran. It ends in exit code 64.
    struct UsageError: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    /// The run failed. What went wrong is already on stderr, so this only carries
    /// the outcome to the exit code, which is 1.
    struct Failure: Error {}

    static let optionParser = OptionParser([
        .value("output", short: "o"),
        .flag("verbose", short: "v"),
        .flag("force", short: "f"),
        .flag("extract-attachments"),
        .value("attachments-dir"),
        .value("attachment-name"),
        .flag("inline-images"),
        .value("format"),
        .flag("version"),
        .flag("help", short: "h"),
    ])

    /// Reads the arguments after the command's name.
    ///
    /// An option given twice counts with its last value, as it did under
    /// ArgumentParser.
    static func invocation(from arguments: [String]) throws -> Invocation {
        let parsed: ParsedArguments
        do {
            parsed = try Self.optionParser.parse(arguments)
        }
        catch {
            throw UsageError(description: "\(error)")
        }

        // Help and the version need nothing else on the line, not even a path.
        if parsed.isSet("help") {
            return .help
        }
        if parsed.isSet("version") {
            return .version
        }

        guard let path = parsed.operands.first else {
            throw UsageError(description: "missing path")
        }
        guard parsed.operands.count == 1 else {
            throw UsageError(description: "unexpected argument '\(parsed.operands[1])'")
        }

        let name = parsed.value(of: "format") ?? OutputFormat.markdown.rawValue
        guard let format = OutputFormat(rawValue: name) else {
            throw UsageError(description: "--format takes markdown or obsidian, not '\(name)'")
        }

        let command = Mail2md(
            output: parsed.value(of: "output"),
            verbose: parsed.isSet("verbose"),
            force: parsed.isSet("force"),
            extractAttachments: parsed.isSet("extract-attachments"),
            attachmentsDir: parsed.value(of: "attachments-dir"),
            attachmentName: parsed.value(of: "attachment-name"),
            inlineImages: parsed.isSet("inline-images"),
            format: format,
            path: path
        )

        if command.destination == .standardOutput, command.extractsAttachments, command.attachmentsDir == nil {
            throw UsageError(description: Self.attachmentsNeedDirectory)
        }
        return .run(command)
    }
}

// MARK: - Help
extension Mail2md {

    /// The command line in brief, shared by the help and the usage error.
    static let synopsis = "mail2md [--output <output>] [--verbose] [--force] [--extract-attachments] [--attachments-dir <attachments-dir>] [--attachment-name <attachment-name>] [--inline-images] [--format <format>] <path>"

    /// What follows a usage error, the way `rm` and `cp` print theirs.
    static let usage = """
        usage: \(Mail2md.synopsis)
        See 'mail2md --help' for more information.
        """

    /// Laid out in ArgumentParser's layout and wrapped to the window, as the help
    /// was up to 1.3.1.
    static let helpPage = HelpPage(
        overview: Mail2md.abstract,
        usage: Mail2md.synopsis,
        sections: [
            HelpPage.Section("ARGUMENTS", [
                HelpPage.Entry("<path>", "Path to an .eml file, or - to read the mail from standard input."),
            ]),
            HelpPage.Section("OPTIONS", [
                HelpPage.Entry("-o, --output <output>", "Output file path, or - for standard output. Defaults to the input path with .md extension, and to standard output when the mail comes from standard input."),
                HelpPage.Entry("-v, --verbose", "Show detailed information."),
                HelpPage.Entry("-f, --force", "Overwrite existing output files that differ from the generated Markdown."),
                HelpPage.Entry("--extract-attachments", "Write attachment files (next to the output, or into --attachments-dir) and link them from the note."),
                HelpPage.Entry("--attachments-dir <attachments-dir>", "Directory for extracted attachments; implies --extract-attachments. Defaults next to the output, and is needed when the output is standard output."),
                HelpPage.Entry("--attachment-name <attachment-name>", "Rename extracted attachments after a pattern, e.g. \"{date} {time} ENCL {name}\"; placeholders are {name}, {ext}, {date} and {time}, the latter two with an optional format ({date:yyyy.MM.dd}). Implies --extract-attachments."),
                HelpPage.Entry("--inline-images", "Write the pictures the mail shows from its own parts (cid:) as files too, and embed each where it stands. Implies --extract-attachments."),
                HelpPage.Entry("--format <format>", "The Markdown to write: markdown, which any reader shows, or obsidian, which sets a card the mail draws apart as a callout instead of between rules. (default: markdown)"),
                HelpPage.Entry("--version", "Show the version."),
                HelpPage.Entry("-h, --help", "Show help information."),
            ]),
        ]
    )
}

// MARK: - Entry point
extension Mail2md {

    static func main() {
        let invocation: Invocation
        do {
            invocation = try Self.invocation(from: Array(CommandLine.arguments.dropFirst()))
        }
        catch {
            // EX_USAGE, the code `rm` and `cp` exit with on a command line they cannot use.
            printIf(true, "mail2md: \(error)")
            printIf(true, Self.usage)
            exit(EX_USAGE)
        }

        switch invocation {
        case .help:
            printIf(true, Self.helpPage.rendered(width: HelpPage.screenWidth), to: .standardOutput)
        case .version:
            printIf(true, Self.version, to: .standardOutput)
        case .run(let command):
            do {
                try command.run()
            }
            catch is Failure {
                exit(EXIT_FAILURE)
            }
            catch {
                // Every failure the run knows of is reported where it happens and
                // arrives here as `Failure`. Anything else would end without a word.
                printIf(true, "mail2md: \(error.localizedDescription)")
                exit(EXIT_FAILURE)
            }
        }
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
/// diagnostics: the actual product is the note. Keeping stdout to the note, the
/// help and the version means `2>/dev/null` silences the noise and nothing else,
/// and a note written to stdout (`mail2md - < x.eml`) arrives in a pipe untouched.
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
