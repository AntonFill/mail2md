//
//  AttachmentExtractorTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct AttachmentExtractionTests {

    /// A fresh unique temp directory; removed when the test process exits.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mail2md-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bytes(_ name: String, in directory: URL) throws -> Data {
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    @Test func writesDecodedBytesForNamedAttachment() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // "JVBERi0xLjQK" base64-decodes to "%PDF-1.4\n", written verbatim.
        #expect(written.contains("Doc.pdf"))
        #expect(try self.bytes("Doc.pdf", in: dir) == Data("%PDF-1.4\n".utf8))
    }

    @Test func suffixesCollidingFilenames() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // Two parts share "Doc.pdf"; the second becomes "Doc-1.pdf".
        #expect(written.filter { $0.hasPrefix("Doc") } == ["Doc.pdf", "Doc-1.pdf"])
        #expect(try self.bytes("Doc-1.pdf", in: dir) == Data("Hello".utf8))
    }

    @Test func stripsPathTraversalFromFilename() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // "../evil.bin" is reduced to its bare last component, inside `dir`.
        #expect(written.contains("evil.bin"))
        #expect(written.contains { $0.contains("..") } == false)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.bin").path))
        let escaped = dir.deletingLastPathComponent().appendingPathComponent("evil.bin").path
        #expect(FileManager.default.fileExists(atPath: escaped) == false)
    }

    @Test func keepsPunctuationInAttachmentNames() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: punctuationNameEML))

        // A URL parser would cut at the `#` and the `?` and decode the `%20`,
        // leaving files without their extension. The `#` itself becomes `-`,
        // see the test below.
        #expect(written.contains("Rechnung -123.pdf"))
        #expect(written.contains("Bericht%20final.pdf"))
        #expect(written.contains("Wann? Jetzt.pdf"))

        for name in ["Rechnung -123.pdf", "Bericht%20final.pdf", "Wann? Jetzt.pdf"] {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
        }
    }

    /// The note links every file it writes, and Obsidian's wikilink reaches no
    /// file whose name holds `#` or `|`, nor one whose name holds `[[` or `]]`
    /// or ends in `]` (measured 2026-10-26): `#` makes the rest of the name a
    /// heading, `|` an alias, the brackets end the link early. Each becomes
    /// `-`, as a `/` does, and in such a name every bracket; a single bracket
    /// inside a name links and stays. Until 1.5.0 the note linked a file it
    /// could not reach.
    @Test(arguments: [
        ("Rechnung #123.pdf", "Rechnung -123.pdf"),
        ("Angebot A|B.pdf", "Angebot A-B.pdf"),
        ("Scan [[1]].pdf", "Scan --1--.pdf"),
        ("Scan [1]", "Scan -1-"),
        ("Rechnung [Kopie].pdf", "Rechnung [Kopie].pdf"),
        ("Plan ^2: final.pdf", "Plan ^2: final.pdf"),
    ])
    func writesANameTheNoteCanLink(name: String, expected: String) {
        #expect(AttachmentExtractor.linkable(name) == expected)
    }

    /// The pattern's own text is held to the same rule.
    @Test func makesThePatternsNameLinkableToo() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let naming = AttachmentNaming(pattern: "#{name}", date: nil)

        let written = try AttachmentExtractor(directory: dir, naming: naming)
            .extract(EMLParser().attachmentParts(from: inlineDocumentEML))

        #expect(written == ["-Ausweis.pdf"])
    }

    @Test func rejectsDotAsAttachmentName() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: punctuationNameEML))

        // A lone "." must fall back to the unnamed name rather than reaching the
        // filesystem: resolving it as a path would yield the working directory's
        // own name.
        #expect(written.contains(".") == false)
        #expect(written.contains { $0.hasPrefix("unnamed") })
    }

    @Test func preservesNonUTF8Bytes() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // "//4AAQ==" decodes to bytes FF FE 00 01, invalid as UTF-8: proof that
        // extraction writes raw bytes and never round-trips through a string.
        #expect(try self.bytes("logo.bin", in: dir) == Data([0xFF, 0xFE, 0x00, 0x01]))
    }

    @Test func fallsBackToUnnamedWithExtension() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // A nameless application/pdf part becomes "unnamed.pdf".
        #expect(written.contains("unnamed.pdf"))
        #expect(try self.bytes("unnamed.pdf", in: dir) == Data("x".utf8))
    }

    @Test func excludesInlineAndSMIMEParts() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // The inline pixel is never written.
        #expect(written.contains("pixel.png") == false)

        // The S/MIME signature is excluded just like in the listing.
        let signed = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: signedEML))
        #expect(signed == ["Vertrag.pdf"])
    }

    @Test func writesNothingWhenNoAttachments() throws {
        let dir = try makeTempDirectory()
        try FileManager.default.removeItem(at: dir)  // ensure absent

        let written = try AttachmentExtractor(directory: dir)
            .extract(EMLParser().attachmentParts(from: simpleEML))

        // No attachments → no writes, and no directory conjured up.
        #expect(written.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }

    // MARK: - Naming

    @Test func writesEachFileUnderTheNamingPattern() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let message = EMLParser().parse(extractEML)
        let naming = AttachmentNaming(pattern: "{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}", date: message.date, timeZone: TimeZone(identifier: "UTC")!)

        let written = try AttachmentExtractor(directory: dir, naming: naming)
            .extract(EMLParser().attachmentParts(from: extractEML))

        // extractEML is dated 22 Jul 2026 10:00 +0200, so 08:00 in UTC.
        #expect(written.contains("2026.07.22 08.00 ENCL Doc.pdf"))
        #expect(try self.bytes("2026.07.22 08.00 ENCL Doc.pdf", in: dir) == Data("%PDF-1.4\n".utf8))
    }

    /// The note is written before the files are, so it links them by planned
    /// names. A plan that disagreed with the write would produce dead links,
    /// including in the case that makes the two hardest to keep in step: two
    /// parts colliding on one name.
    @Test func planNamesTheFilesThatExtractionThenWrites() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let parts = EMLParser().attachmentParts(from: extractEML)
        let extractor = AttachmentExtractor(directory: dir)

        let planned = extractor.plannedNames(parts)
        let written = try extractor.extract(parts)

        #expect(planned == written)
        #expect(planned.filter { $0.hasPrefix("Doc") } == ["Doc.pdf", "Doc-1.pdf"])
    }

    /// Planning must not touch the disk: the directory it names files in may not
    /// even exist yet, and a run that aborts on a note conflict has to leave
    /// nothing behind.
    @Test func planningWritesNothing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("attachments")

        let planned = AttachmentExtractor(directory: target).plannedNames(EMLParser().attachmentParts(from: extractEML))

        #expect(planned.isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: target.path) == false)
    }
}
