//
//  Mail2mdTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 17.08.2026.
//

import Foundation
import Testing
@testable import mail2md

/// Acceptance level of the test pyramid: every test here launches the built
/// binary as a subprocess (see `CommandRunner`), so what is under test is the
/// command a user types. Exit codes, the stdout/stderr split and the file that
/// actually lands on disk are only visible from here; the library suites next
/// to this file cannot see any of it. How a command line is read is a function
/// since 1.4.0, so `InvocationTests` below covers it in process.
///
/// The suite stays thin on purpose. The top layer is the second line of defence,
/// not the first: body decoding, attachment selection and rendering details are
/// covered in-process, and each test here pins one user-visible contract.
struct Mail2mdTests {

    // MARK: - Converting

    @Test func convertsFixtureToMarkdownNextToInput() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "Projektanfrage.eml")

        let run = try command.run([input.path])

        #expect(run.exitCode == 0)
        // The product is the file, so a plain run says nothing on either stream.
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.isEmpty)

        let expected = """
            ---
            created: 2026-06-15T07:41
            from: "Jane Doe <jane@example.com>"
            to: "Anton Fillmann <anton@example.com>"
            cc:
            via:
            subject: "Projektanfrage iOS"
            attachments:
            ---

            Hallo Anton,

            das ist eine Testmail.

            """

        #expect(try command.read("Projektanfrage.md") == expected)
    }

    @Test func writesToTheExplicitOutputPath() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "mail.eml")
        let output = command.path("Anfrage von Jane.md")

        let run = try command.run(["--output", output.path, input.path])

        #expect(run.exitCode == 0)
        #expect(try command.read("Anfrage von Jane.md").contains("subject: \"Projektanfrage iOS\""))
        // The default target next to the input must stay untouched.
        #expect(command.exists("mail.md") == false)
    }

    @Test func extractsOnlyRealAttachmentsIntoTheGivenDirectory() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")
        let attachments = command.path("files")

        // --attachments-dir alone implies extraction; --extract-attachments is not passed.
        let run = try command.run(["--attachments-dir", attachments.path, input.path])

        #expect(run.exitCode == 0)
        // Extracting means the files exist, so the note links them instead of
        // only naming them: a block list in the frontmatter, and the document
        // closing the body.
        #expect(try command.read("gesuch.md").contains("attachments:\n  - \"[[Ausweis.pdf]]\"\n"))
        #expect(try command.read("gesuch.md").hasSuffix("\n[[Ausweis.pdf]]\n"))
        #expect(try Data(contentsOf: attachments.appendingPathComponent("Ausweis.pdf")) == Data("%PDF-1.4\n".utf8))
        // Body furniture stays out of the directory, as it stays out of the listing.
        #expect(command.exists("files/logo.png") == false)
        #expect(command.exists("files/embedded.pdf") == false)
    }

    @Test func namesExtractedAttachmentsAfterThePattern() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")
        let attachments = command.path("files")

        let run = try command.run([
            "--attachments-dir", attachments.path,
            "--attachment-name", "{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}",
            input.path,
        ])

        // The mail is dated 22 Jul 2026 11:00 +0200, and TZ is pinned to UTC.
        #expect(run.exitCode == 0)
        #expect(command.exists("files/2026.07.22 09.00 ENCL Ausweis.pdf"))
        // The note links the file that was really written, under the name the
        // mail gave it.
        #expect(try command.read("gesuch.md").hasSuffix("\n[[2026.07.22 09.00 ENCL Ausweis.pdf|Ausweis.pdf]]\n"))
    }

    /// A typo in the pattern is a command line the tool cannot use, refused
    /// before the mail is read. Until 1.5.0 the run found it and exited 1.
    @Test func rejectsAnUnknownPlaceholderWithoutWritingAnything() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")

        let run = try command.run(["--attachment-name", "{date} {stem}", input.path])

        #expect(run.exitCode == 64)
        #expect(run.standardError == "mail2md: {stem}: unknown placeholder in --attachment-name\n\(Mail2md.usage)\n")
        #expect(command.exists("gesuch.md") == false)
    }

    /// The note is checked before the attachments are written, so a note that
    /// would be overwritten has to stop the run while the directory is still
    /// untouched. Without that order the run would leave files behind for a
    /// note that was never written.
    @Test func conflictingNoteStopsTheRunBeforeAnyAttachmentIsWritten() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")
        try "hand-edited in the vault".write(to: command.path("gesuch.md"), atomically: true, encoding: .utf8)
        let attachments = command.path("files")

        let run = try command.run(["--attachments-dir", attachments.path, input.path])

        #expect(run.exitCode == 1)
        #expect(try command.read("gesuch.md") == "hand-edited in the vault")
        #expect(FileManager.default.fileExists(atPath: attachments.path) == false)
    }

    /// A card the mail sets apart stands between rules in the note, and as a
    /// callout where `--format obsidian` asks for Obsidian's Markdown.
    @Test func setsACardApartAsTheFormatAsksFor() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(cardEML, named: "karte.eml")

        let markdown = try command.run(["-o", "-", input.path])
        let obsidian = try command.run(["--format", "obsidian", "-o", "-", input.path])

        #expect(markdown.exitCode == 0)
        #expect(markdown.standardOutput.hasSuffix("---\n\nDavor\n\n---\n\n**Jane Doe**\nBetrag: CHF 100\n\n---\n\nDanach\n"))
        #expect(obsidian.exitCode == 0)
        #expect(obsidian.standardOutput.hasSuffix("---\n\nDavor\n\n> [!quote] Jane Doe\n> Betrag: CHF 100\n\nDanach\n"))
    }

    // MARK: - Inline images

    /// A picture the note leaves out is named on stderr with the size it is
    /// shown at, so a screenshot is not lost without a word. The icon's size
    /// comes from its file, since the HTML gives none.
    @Test func namesTheInlineImagesItLeavesOut() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineImageEML, named: "profil.eml")

        let run = try command.run([input.path])

        #expect(run.exitCode == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(input.path): inline images left out: image001.png 474×464, image002.png 1×1 (use --inline-images to include them)\n")
        #expect(try command.read("profil.md").contains("![[") == false)
    }

    /// `--inline-images` writes each picture as a file and embeds it where the
    /// mail shows it, under the naming pattern like any attachment.
    @Test func embedsInlineImagesWhereTheMailShowsThem() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineImageEML, named: "profil.eml")
        let files = command.path("files")

        let run = try command.run([
            "--inline-images",
            "--attachments-dir", files.path,
            "--attachment-name", "{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}",
            input.path,
        ])

        // The mail is dated 7 Sep 2026 10:00 +0200, and TZ is pinned to UTC.
        #expect(run.exitCode == 0)
        #expect(run.standardError.isEmpty)
        #expect(command.exists("files/2026.09.07 08.00 ENCL image001.png"))
        #expect(command.exists("files/2026.09.07 08.00 ENCL image002.png"))
        let note = try command.read("profil.md")
        #expect(note.contains("attachments:\n  - \"[[2026.09.07 08.00 ENCL image001.png]]\"\n  - \"[[2026.09.07 08.00 ENCL image002.png]]\"\n---\n"))
        #expect(note.hasSuffix("Portal:\n\n![[2026.09.07 08.00 ENCL image001.png]]\n\nGruss\nJane\n![[2026.09.07 08.00 ENCL image002.png|LinkedIn]]\n"))
    }

    /// A picture whose part is an attachment as well is written once, next to
    /// the note by default, embedded where the mail shows it and not repeated
    /// below the text.
    @Test func writesAPictureThatIsAnAttachmentOnce() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(referencedAttachmentEML, named: "adresse.eml")

        let run = try command.run(["--inline-images", input.path])

        #expect(run.exitCode == 0)
        #expect(run.standardError.isEmpty)
        let entries = try FileManager.default.contentsOfDirectory(atPath: command.workspace.path).filter { $0 != "streams" }
        #expect(entries.sorted() == ["adresse.eml", "adresse.md", "logo.png"])
        let note = try command.read("adresse.md")
        #expect(note.contains("attachments:\n  - \"[[logo.png]]\"\n---\n"))
        #expect(note.hasSuffix("Ihre Adresse wurde geändert.\n\n![[logo.png]]\n"))
    }

    // MARK: - Writing twice

    @Test func secondRunReportsUnchanged() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "mail.eml")

        let first = try command.run(["--verbose", input.path])
        let second = try command.run(["--verbose", input.path])

        #expect(first.exitCode == 0)
        #expect(second.exitCode == 0)
        #expect(first.standardError.contains("(written)"))
        // Re-running is a no-op, not an overwrite: the writer compares first.
        #expect(second.standardError.contains("(unchanged)"))
        // Even --verbose keeps stdout free, so a note written there arrives untouched.
        #expect(second.standardOutput.isEmpty)
    }

    @Test func divergingOutputFailsAndLeavesTheFileAlone() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "mail.eml")
        let output = command.path("mail.md")
        try "hand-edited in the vault".write(to: output, atomically: true, encoding: .utf8)

        let run = try command.run([input.path])

        #expect(run.exitCode == 1)
        #expect(run.standardError == "mail2md: \(output.path): differs from generated output (use --force to overwrite)\n")
        #expect(try command.read("mail.md") == "hand-edited in the vault")
    }

    @Test func forceOverwritesDivergingOutput() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "mail.eml")
        try "hand-edited in the vault".write(to: command.path("mail.md"), atomically: true, encoding: .utf8)

        let run = try command.run(["--force", input.path])

        #expect(run.exitCode == 0)
        #expect(try command.read("mail.md").hasPrefix("---\ncreated: 2026-06-15T07:41\n"))
    }

    // MARK: - Pipes

    @Test func readsTheMailFromStandardInputAndLeavesNoFile() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        let run = try command.run(["-"], standardInput: Data(simpleEML.utf8))

        #expect(run.exitCode == 0)
        #expect(run.standardError.isEmpty)
        // A filter leaves nothing behind but its output.
        #expect(try FileManager.default.contentsOfDirectory(atPath: command.workspace.path) == ["streams"])

        // The note is the one a file would hold.
        let input = try command.write(simpleEML, named: "mail.eml")
        _ = try command.run([input.path])
        #expect(try command.read("mail.md") == run.standardOutput)
    }

    /// The note on stdout is byte for byte the file, and the diagnostics stay
    /// on stderr, the same lines either way.
    @Test func writesTheNoteToStandardOutputAsTheFileWouldHoldIt() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineImageEML, named: "profil.eml")

        let file = try command.run([input.path])
        let piped = try command.run(["-o", "-", input.path])

        #expect(piped.exitCode == 0)
        #expect(try command.read("profil.md") == piped.standardOutput)
        #expect(piped.standardError == file.standardError)
        #expect(piped.standardError.isEmpty == false)
    }

    @Test func writesAMailFromStandardInputToTheFileItIsGiven() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        let run = try command.run(["-", "-o", "note.md"], standardInput: Data(simpleEML.utf8))

        #expect(run.exitCode == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(try command.read("note.md").hasPrefix("---\ncreated: 2026-06-15T07:41\n"))
    }

    /// Nothing on stdin is an empty mail, as an empty file is: the note with its
    /// keys and nothing in them, and the warning about the date, which names
    /// stdin the way messages name it.
    @Test func takesNothingOnStandardInputAsAnEmptyMail() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write("", named: "empty.eml")

        let file = try command.run([input.path])
        let piped = try command.run(["-"])

        #expect(piped.exitCode == 0)
        #expect(try command.read("empty.md") == piped.standardOutput)
        #expect(piped.standardError == "mail2md: (standard input): missing or unparsable Date header (created left empty)\n")
        #expect(file.standardError == "mail2md: \(input.path): missing or unparsable Date header (created left empty)\n")
    }

    @Test func refusesAttachmentsOnStandardOutputWithoutADirectory() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")

        let run = try command.run(["-o", "-", "--extract-attachments", input.path])

        // The working directory would be a guess, so the line is refused
        // before anything is read.
        #expect(run.exitCode == 64)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.hasPrefix("mail2md: attachments need --attachments-dir when the note goes to standard output\n"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: command.workspace.path).sorted() == ["gesuch.eml", "streams"])
    }

    @Test func writesAttachmentsIntoTheGivenDirectoryWhenTheNoteGoesToStandardOutput() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let files = command.path("files")

        let run = try command.run(["-", "--attachments-dir", files.path], standardInput: Data(inlineDocumentEML.utf8))

        #expect(run.exitCode == 0)
        #expect(run.standardOutput.hasSuffix("\n[[Ausweis.pdf]]\n"))
        #expect(command.exists("files/Ausweis.pdf"))
    }

    // MARK: - Failing

    @Test func missingInputFailsWithUnixStyleError() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let missing = command.path("absent.eml")

        let run = try command.run([missing.path])

        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(missing.path): No such file\n")
    }

    @Test func directoryInputFailsWithUnixStyleError() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        // A directory exists, so the existence check alone would let it through
        // and the read would fail with Foundation's own wording (v1.0.2).
        let run = try command.run([command.workspace.path])

        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(command.workspace.path): Is a directory\n")
    }

    @Test func undecodableInputFailsWithoutWritingMarkdown() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        // `From: <0xFF>`: the byte is not valid UTF-8, and the file declares no
        // charset it could be read in instead.
        let input = try command.write(Data([0x46, 0x72, 0x6F, 0x6D, 0x3A, 0x20, 0xFF, 0x0D, 0x0A]), named: "broken.eml")

        let run = try command.run([input.path])

        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(input.path): not valid UTF-8 text, nor in a charset it declares\n")
        #expect(command.exists("broken.md") == false)
    }

    @Test func convertsAFileThatIsNotUTF8InTheCharsetItDeclares() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(latin1EML, named: "bestellung.eml")

        let run = try command.run([input.path])

        // Until v1.2.0 an old mail in Latin-1 was refused as not valid UTF-8.
        #expect(run.exitCode == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.isEmpty)
        let note = try command.read("bestellung.md")
        #expect(note.contains("subject: \"Freischaltung Ihrer Bestellung bestätigt\""))
        #expect(note.contains("\nFreundliche Grüße"))
    }

    @Test func unreadableInputKeepsFoundationsWordingForVerbose() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "locked.eml")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: input.path)

        let run = try command.run(["--verbose", input.path])

        // The tool's own wording is unconditional; Foundation's localized reason
        // is a detail and stays behind --verbose.
        let lines = run.standardError.split(separator: "\n")
        let detail = try #require(lines.last)

        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(lines.count == 2)
        #expect(lines.first == "mail2md: \(input.path): cannot be read")
        // Only the shape of the detail line is pinned: the reason is localized.
        #expect(detail.hasPrefix("mail2md: \(input.path): "))
        #expect(command.exists("locked.md") == false)
    }

    @Test func warnsAboutUnparsableDateAndStillSucceeds() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(unparsableDateEML, named: "kein-datum.eml")

        let run = try command.run([input.path])

        // An empty `created` is silent data loss in the vault, so the warning is
        // unconditional, but it is a warning: the file is still written.
        #expect(run.exitCode == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(input.path): missing or unparsable Date header (created left empty)\n")
        #expect(try command.read("kein-datum.md").contains("\ncreated:\n"))
    }

    @Test func reportsInvisibleCharactersAndStillSucceeds() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(hiddenTextEML, named: "newsletter.eml")

        let run = try command.run([input.path])

        // Removing characters changes the text, so the run says so without
        // being asked, and it names what it left in for a second look.
        #expect(run.exitCode == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(input.path): invisible characters: removed 2 (ZWSP 2), kept 1 (ZWJ 1)\n")
        #expect(try command.read("newsletter.md").contains("subject: \"API versioning\""))
    }

    @Test func noteThatCannotBeWrittenFailsWithUnixStyleError() throws {
        let command = try CommandRunner()
        let locked = command.path("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            command.removeWorkspace()
        }
        let input = try command.write(simpleEML, named: "mail.eml")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let output = locked.appendingPathComponent("mail.md")

        let run = try command.run(["--output", output.path, input.path])

        // Until 1.4.0 ArgumentParser printed Foundation's localized sentence as
        // `Error: …`, which names the folder but not the path.
        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(output.path): cannot be written\n")
    }

    @Test func attachmentsThatCannotBeWrittenFailWithUnixStyleError() throws {
        let command = try CommandRunner()
        let locked = command.path("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            command.removeWorkspace()
        }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)

        let run = try command.run(["--attachments-dir", locked.path, input.path])

        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "mail2md: \(locked.path): cannot be written\n")
        // Until 1.5.0 the note was written first and linked files that were
        // never written.
        #expect(command.exists("gesuch.md") == false)
    }

    /// A note that cannot be written stops the run before any attachment is,
    /// as a conflicting one does: the attachments would stand without it.
    @Test func noteThatCannotBeWrittenLeavesNoAttachmentBehind() throws {
        let command = try CommandRunner()
        let locked = command.path("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            command.removeWorkspace()
        }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let output = locked.appendingPathComponent("gesuch.md")
        let attachments = command.path("files")

        let run = try command.run(["--output", output.path, "--attachments-dir", attachments.path, input.path])

        #expect(run.exitCode == 1)
        #expect(run.standardError == "mail2md: \(output.path): cannot be written\n")
        #expect(FileManager.default.fileExists(atPath: attachments.path) == false)
    }

    // MARK: - Refusing the command line

    @Test func refusesToRunWithoutAPath() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        let run = try command.run([])

        // 64 is EX_USAGE from sysexits(3), what rm and cp exit with on a usage
        // error; ArgumentParser used it too.
        #expect(run.exitCode == 64)
        #expect(run.standardOutput.isEmpty)
        // The whole stream, so the shape is pinned too: the tool's own line, then
        // the usage.
        #expect(run.standardError == "mail2md: missing path\n\(Mail2md.usage)\n")
    }

    @Test func rejectsAnUnknownOptionWithoutWritingAnything() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(simpleEML, named: "mail.eml")

        let run = try command.run(["--bogus", input.path])

        #expect(run.exitCode == 64)
        #expect(run.standardError.hasPrefix("mail2md: unknown option '--bogus'\n"))
        #expect(command.exists("mail.md") == false)
    }

    // MARK: - Reporting itself

    @Test func printsItsHelpWrappedToColumns() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        let wide = try command.run(["--help"], environment: ["COLUMNS": "120"])
        // Standard output is a file here, so without COLUMNS there is no window
        // to measure, and the help falls back to 80 columns.
        let plain = try command.run(["--help"], environment: ["COLUMNS": nil])

        // Help that was asked for is data, hence stdout and exit 0.
        #expect(wide.exitCode == 0)
        #expect(wide.standardError.isEmpty)
        #expect(wide.standardOutput == Mail2md.helpPage.rendered(width: 120) + "\n")
        #expect(plain.standardOutput == Mail2md.helpPage.rendered(width: 80) + "\n")
        // The two only differ if the width actually reached the layout.
        #expect(wide.standardOutput != plain.standardOutput)
    }

    @Test func reportsItsVersionOnStandardOutput() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }

        let run = try command.run(["--version"])

        // A version query is data, not diagnostics, hence stdout. It also proves
        // the constant is wired into the command configuration.
        #expect(run.exitCode == 0)
        #expect(run.standardOutput == Mail2md.version + "\n")
        #expect(run.standardError.isEmpty)
    }
}

// MARK: - Invocation

/// How a command line turns into a command, in process. The getopt rules
/// themselves are pinned in `OptionParserTests`; this suite pins what mail2md
/// makes of them. Until 1.4.0 ArgumentParser read the line, and the cases it
/// answered differently are noted where they stand.
struct InvocationTests {

    @Test func pathAloneGivesTheDefaults() throws {
        #expect(try Mail2md.invocation(from: ["mail.eml"]) == .run(Mail2md(path: "mail.eml")))
    }

    @Test func readsEveryOptionBeforeOrAfterThePath() throws {
        let expected = Mail2md(output: "note.md", verbose: true, force: true, extractAttachments: true, attachmentsDir: "files", attachmentName: "ENCL {name}", inlineImages: true, format: .obsidian, path: "mail.eml")

        #expect(try Mail2md.invocation(from: ["-vf", "-o", "note.md", "--extract-attachments", "--attachments-dir", "files", "--attachment-name", "ENCL {name}", "--inline-images", "--format", "obsidian", "mail.eml"]) == .run(expected))
        #expect(try Mail2md.invocation(from: ["mail.eml", "--output=note.md", "--verbose", "--force", "--extract-attachments", "--attachments-dir=files", "--attachment-name=ENCL {name}", "--inline-images", "--format=obsidian"]) == .run(expected))
    }

    /// Plain Markdown unless the line asks for Obsidian's.
    @Test func writesMarkdownUnlessTheFormatSaysOtherwise() throws {
        #expect(try Mail2md.invocation(from: ["mail.eml"]) == .run(Mail2md(format: .markdown, path: "mail.eml")))
        #expect(try Mail2md.invocation(from: ["--format", "markdown", "mail.eml"]) == .run(Mail2md(path: "mail.eml")))
        #expect(try Mail2md.invocation(from: ["--format", "obsidian", "mail.eml"]) == .run(Mail2md(format: .obsidian, path: "mail.eml")))
    }

    @Test func refusesAFormatItDoesNotKnow() throws {
        #expect(throws: Mail2md.UsageError(description: "--format takes markdown or obsidian, not 'html'")) {
            try Mail2md.invocation(from: ["mail.eml", "--format", "html"])
        }
    }

    /// Every unknown placeholder is named, in the order of the pattern; a known
    /// one with a format passes.
    @Test func refusesAPatternWithAPlaceholderItDoesNotKnow() throws {
        #expect(throws: Mail2md.UsageError(description: "{stem}, {datum:yyyy}: unknown placeholder in --attachment-name")) {
            try Mail2md.invocation(from: ["mail.eml", "--attachment-name", "{date:yyyy} {stem} {datum:yyyy}"])
        }
        #expect(try Mail2md.invocation(from: ["mail.eml", "--attachment-name", "{date:yyyy} {name}"]) == .run(Mail2md(attachmentName: "{date:yyyy} {name}", path: "mail.eml")))
    }

    @Test func takesTheOutputAttachedToItsShortForm() throws {
        // getopt's `-ofile`. ArgumentParser refused it and asked for the path.
        #expect(try Mail2md.invocation(from: ["-onote.md", "mail.eml"]) == .run(Mail2md(output: "note.md", path: "mail.eml")))
    }

    @Test func countsTheLastValueOfARepeatedOption() throws {
        #expect(try Mail2md.invocation(from: ["-o", "a.md", "-o", "b.md", "mail.eml"]) == .run(Mail2md(output: "b.md", path: "mail.eml")))
    }

    @Test func reachesAPathThatStartsWithADashAfterADoubleDash() throws {
        #expect(try Mail2md.invocation(from: ["--", "-mail.eml"]) == .run(Mail2md(path: "-mail.eml")))
    }

    @Test func readsADashAsStandardInputAndWritesTheNoteToStandardOutput() throws {
        let command = Mail2md(path: "-")

        #expect(try Mail2md.invocation(from: ["-"]) == .run(command))
        #expect(command.readsStandardInput)
        #expect(command.inputName == "(standard input)")
        #expect(command.destination == .standardOutput)
        // A file that --output names still takes the note.
        #expect(Mail2md(output: "note.md", path: "-").destination == .file("note.md"))
    }

    @Test func writesTheNoteToStandardOutputForADashAsOutput() throws {
        #expect(try Mail2md.invocation(from: ["mail.eml", "-o", "-"]) == .run(Mail2md(output: "-", path: "mail.eml")))
        // Until 1.4.0, `-o -` wrote a file named `-`.
        #expect(Mail2md(output: "-", path: "mail.eml").destination == .standardOutput)
        #expect(Mail2md(path: "/mail/Anfrage.eml").destination == .file("/mail/Anfrage.md"))
    }

    @Test(arguments: [
        ["-", "--extract-attachments"],
        ["mail.eml", "-o", "-", "--inline-images"],
        ["-", "--attachment-name", "ENCL {name}"],
    ])
    func refusesAttachmentsWithoutADirectoryForANoteOnStandardOutput(arguments: [String]) throws {
        #expect(throws: Mail2md.UsageError(description: Mail2md.attachmentsNeedDirectory)) {
            try Mail2md.invocation(from: arguments)
        }
    }

    @Test func takesAttachmentsAlongWhereTheyHaveADirectory() throws {
        #expect(try Mail2md.invocation(from: ["-", "--attachments-dir", "files"]) == .run(Mail2md(attachmentsDir: "files", path: "-")))
        #expect(try Mail2md.invocation(from: ["-", "-o", "note.md", "--extract-attachments"]) == .run(Mail2md(output: "note.md", extractAttachments: true, path: "-")))
    }

    @Test func needsNoPathForHelpOrTheVersion() throws {
        #expect(try Mail2md.invocation(from: ["--help"]) == .help)
        #expect(try Mail2md.invocation(from: ["-h"]) == .help)
        #expect(try Mail2md.invocation(from: ["--version"]) == .version)
        #expect(try Mail2md.invocation(from: ["mail.eml", "--version"]) == .version)
    }

    @Test func refusesACommandLineWithoutAPathOrWithTwo() throws {
        #expect(throws: Mail2md.UsageError(description: "missing path")) {
            try Mail2md.invocation(from: ["-v"])
        }
        // What a glob with two matches produces; the shell, not the user, typed the second.
        #expect(throws: Mail2md.UsageError(description: "unexpected argument 'b.eml'")) {
            try Mail2md.invocation(from: ["a.eml", "b.eml"])
        }
    }

    @Test func passesTheParsersRefusalOnInTheToolsWords() throws {
        #expect(throws: Mail2md.UsageError(description: "unknown option '--bogus'")) {
            try Mail2md.invocation(from: ["--bogus", "mail.eml"])
        }
        #expect(throws: Mail2md.UsageError(description: "option '-o' needs a value")) {
            try Mail2md.invocation(from: ["mail.eml", "-o"])
        }
        // A wrong command line is refused whatever else it holds, as in realdate.
        // ArgumentParser showed the help here.
        #expect(throws: Mail2md.UsageError(description: "unknown option '--bogus'")) {
            try Mail2md.invocation(from: ["-h", "--bogus"])
        }
    }
}

// MARK: -

/// An HTML mail with a card framed on all four sides, a name in bold above an
/// amount, between two lines of text. Local to this suite, like the fixture
/// below, because the emitter's suites build their cards from HTML alone.
private let cardEML = """
    From: Versicherung <info@example.com>\r
    To: Jane Doe <jane@example.com>\r
    Subject: Bestaetigung\r
    Date: Sun, 25 Oct 2026 22:07:00 +0100\r
    MIME-Version: 1.0\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><div>Davor</div><div style="border:2px solid #cccccc"><div style="font-weight:bold">Jane Doe</div>\r
    <div>Betrag: CHF 100</div></div><div>Danach</div></body></html>\r
    """

/// A `Date` header no parser can read, for the warning path of the command.
/// Local to this suite rather than shared in `EMLFixtures.swift`, because only
/// the acceptance level cares about the warning.
private let unparsableDateEML = """
    From: Jane Doe <jane@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Kein Datum\r
    Date: irgendwann\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton,\r
    \r
    diese Mail trägt kein lesbares Datum.\r
    """
