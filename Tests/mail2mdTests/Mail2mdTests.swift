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
/// command a user types. Argument parsing, exit codes, the stdout/stderr split
/// and the file that actually lands on disk are only visible from here; the
/// library suites next to this file cannot see any of it.
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

    @Test func rejectsAnUnknownPlaceholderWithoutWritingAnything() throws {
        let command = try CommandRunner()
        defer { command.removeWorkspace() }
        let input = try command.write(inlineDocumentEML, named: "gesuch.eml")

        let run = try command.run(["--attachment-name", "{date} {stem}", input.path])

        #expect(run.exitCode == 1)
        #expect(run.standardError == "mail2md: {stem}: unknown placeholder in --attachment-name\n")
        #expect(command.exists("gesuch.md") == false)
    }

    /// The note is written before the attachments, so a note that would be
    /// overwritten has to stop the run while the directory is still untouched.
    /// Without that order the run would leave files behind for a note that was
    /// never written.
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
        // Even --verbose keeps stdout free for the planned piping.
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

    // MARK: - Reporting itself

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

// MARK: -

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
