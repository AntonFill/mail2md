//
//  MarkdownRendererTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct MarkdownRendererTests {

    @Test func rendersTemplateFrontmatterAndBody() {
        let message = EMLParser().parse(simpleEML)
        let expected = """
            ---
            created: 2026-06-15T09:41
            from: "Jane Doe <jane@example.com>"
            to: "Anton Fillmann <anton@example.com>"
            via:
            subject: "Projektanfrage iOS"
            attachments:
            ---

            Hallo Anton,

            das ist eine Testmail.

            """

        let renderer = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)
        #expect(renderer.render(message) == expected)
    }

    @Test func rendersCreatedInReaderLocalZoneNotSenderZone() {
        // simpleEML's Date: is 09:41 +0200 == the 07:41 UTC instant. The reader's
        // zone, not the sender's offset, decides the wall-clock: Europe/Zurich
        // (CEST, +0200) renders 09:41; UTC renders 07:41 for the same instant.
        let message = EMLParser().parse(simpleEML)

        let zurich = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)
        #expect(zurich.render(message).contains("created: 2026-06-15T09:41\n"))

        let utc = MarkdownRenderer(timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc.render(message).contains("created: 2026-06-15T07:41\n"))
    }

    /// Regression: the sender's offset must not leak into the rendered wall-clock.
    /// Both headers denote 10:01 UTC, so a Zurich reader (CEST, +0200) sees 12:01
    /// either way; the earlier bug echoed the header's digits instead.
    @Test(arguments: [
        "Tue, 28 Jul 2026 10:01:00 +0000",
        "Tue, 28 Jul 2026 15:01:00 +0500",
    ])
    func rendersSameInstantRegardlessOfSenderOffset(header: String) {
        let message = EMLParser().parse("Date: \(header)\r\nSubject: T\r\n\r\nBody")
        let renderer = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)

        #expect(renderer.render(message).contains("created: 2026-07-28T12:01\n"))
    }

    @Test func omitsHeadingAndMessageID() {
        let markdown = MarkdownRenderer().render(EMLParser().parse(simpleEML))

        #expect(markdown.contains("# Inhalt") == false)
        #expect(markdown.contains("message-id") == false)
    }

    @Test func rendersBareKeyForMissingHeader() {
        let markdown = MarkdownRenderer().render(
            EMLParser().parse("Subject: Only a subject\r\n\r\nBody"))

        #expect(markdown.contains("\nfrom:\n"))
        #expect(markdown.contains("\ncreated:\n"))
    }

    @Test func rendersAttachmentsAsFlowList() {
        let markdown = MarkdownRenderer().render(EMLParser().parse(mixedEML))

        #expect(
            markdown.contains("attachments: [\"Lebenslauf.pdf\", \"Prüfung.pdf\", \"Foto.png\"]\n"))
    }
}

// MARK: -

/// The closing attachment block, which only appears once the files exist
/// (`linksAttachments`). The renderer is fed hand-built messages here rather
/// than parsed fixtures: what is under test is the shape of the block, not the
/// selection of the parts, and a hand-built list can hold the three-image odd
/// case no fixture carries.
struct AttachmentBlockTests {

    static func message(_ attachments: [mail2md.Attachment], body: String = "Gesendet von Outlook für iOS") -> EmailMessage {
        return EmailMessage(
            from: "Christine <christine@example.com>",
            to: "Anton Fillmann <anton@example.com>",
            subject: "Fotos",
            date: nil,
            timeZone: nil,
            messageID: nil,
            body: body,
            attachments: attachments
        )
    }

    static func image(_ name: String, sourceName: String? = nil) -> mail2md.Attachment {
        return mail2md.Attachment(name: name, mediaType: "image/jpeg", sourceName: sourceName)
    }

    static func document(_ name: String, sourceName: String? = nil) -> mail2md.Attachment {
        return mail2md.Attachment(name: name, mediaType: "application/pdf", sourceName: sourceName)
    }

    static let linking = MarkdownRenderer(timeZone: TimeZone(identifier: "UTC")!, linksAttachments: true)

    /// An odd number of images, so the last row has to carry an empty cell.
    @Test func embedsImagesTwoPerRow() {
        let images = [Self.image("01 Erfassen.JPG"), Self.image("02 Liste.JPG"), Self.image("03 Statistik.JPG")]
        let markdown = Self.linking.render(Self.message(images))
        let expected = """

            |  |  |
            |---|---|
            | ![[01 Erfassen.JPG]] | ![[02 Liste.JPG]] |
            | ![[03 Statistik.JPG]] |  |

            """

        #expect(markdown.hasSuffix(expected))
    }

    /// No heading, no rule, no prose: the block starts one blank line after the
    /// body and consists of links only.
    @Test func closesTheBodyWithoutAnnouncingItself() {
        let markdown = Self.linking.render(Self.message([Self.image("Foto.JPG")]))

        #expect(markdown.contains("Gesendet von Outlook für iOS\n\n|  |  |\n"))
        #expect(markdown.contains("---\n\n|") == false)
        #expect(markdown.lowercased().contains("attachment\n") == false)
    }

    /// A renamed document keeps the sender's name as the link alias; one that
    /// was not renamed has nothing to alias.
    @Test func aliasesARenamedDocumentWithTheNameTheMailGaveIt() {
        let renamed = Self.document("2026.08.18 07.51 ENCL Auftrag.pdf", sourceName: "Auftrag Webdesigner.pdf")
        let markdown = Self.linking.render(Self.message([renamed, Self.document("Beilage.pdf")]))

        #expect(markdown.contains("\n[[2026.08.18 07.51 ENCL Auftrag.pdf|Auftrag Webdesigner.pdf]]\n"))
        #expect(markdown.contains("\n[[Beilage.pdf]]\n"))
    }

    /// Images first, then the documents, each its own paragraph so a run of
    /// links cannot fold into one line.
    @Test func separatesDocumentsFromTheImageTable() {
        let markdown = Self.linking.render(Self.message([Self.document("Doc.pdf"), Self.image("Foto.JPG")]))
        let expected = """

            |  |  |
            |---|---|
            | ![[Foto.JPG]] |  |

            [[Doc.pdf]]

            """

        #expect(markdown.hasSuffix(expected))
    }

    @Test func listsAttachmentsAsWikilinkBlockInTheFrontmatter() {
        let markdown = Self.linking.render(Self.message([Self.image("Foto.JPG"), Self.document("Doc.pdf")]))

        #expect(markdown.contains("attachments:\n  - \"[[Foto.JPG]]\"\n  - \"[[Doc.pdf]]\"\n---\n"))
    }

    /// Without extraction there are no files, and a link to a file nobody wrote
    /// is a dead link. So the note only names them, exactly as before v1.1.0.
    @Test func staysSilentWhenTheFilesWereNotWritten() {
        let renderer = MarkdownRenderer(timeZone: TimeZone(identifier: "UTC")!)
        let markdown = renderer.render(Self.message([Self.image("Foto.JPG"), Self.document("Doc.pdf")]))

        #expect(markdown.contains("attachments: [\"Foto.JPG\", \"Doc.pdf\"]\n"))
        #expect(markdown.contains("[[") == false)
        #expect(markdown.hasSuffix("Gesendet von Outlook für iOS\n"))
    }

    @Test func writesNoBlockForAMailWithoutAttachments() {
        let markdown = Self.linking.render(Self.message([]))

        #expect(markdown.contains("\nattachments:\n---\n"))
        #expect(markdown.hasSuffix("Gesendet von Outlook für iOS\n"))
    }
}
