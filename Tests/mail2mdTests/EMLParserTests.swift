//
//  EMLParserTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct EMLParserTests {

    @Test func parsesHeadersFromSimpleMessage() {
        let message = EMLParser().parse(simpleEML)

        #expect(message.from == "Jane Doe <jane@example.com>")
        #expect(message.to == "Anton Fillmann <anton@example.com>")
        #expect(message.subject == "Projektanfrage iOS")
        #expect(message.messageID == "<abc123@example.com>")
    }

    @Test func parsesBodyFromSimpleMessage() {
        let message = EMLParser().parse(simpleEML)

        #expect(message.body == "Hallo Anton,\n\ndas ist eine Testmail.")
    }

    @Test func parsesRFC5322Date() {
        let message = EMLParser().parse(simpleEML)

        // 09:41 +0200 == 07:41 UTC
        let expected = ISO8601DateFormatter().date(from: "2026-06-15T07:41:00Z")
        #expect(message.date == expected)
    }

    /// The date-header shapes real mailers emit beyond the canonical one. All of
    /// them denote the same instant, 10:01 UTC.
    @Test(arguments: [
        "Tue, 28 Jul 2026 10:01:00 +0000",
        "Tue, 28 Jul 2026 10:01:00 +0000 (UTC)",  // RFC 5322 comment
        "Tue, 28 Jul 2026 12:01:00 +0200 (CEST)",  // comment plus real offset
        "Tue, 28 Jul 2026 10:01 +0000",  // seconds omitted
        "28 Jul 2026 10:01:00 +0000",  // weekday omitted
        "28 Jul 2026 10:01 +0000",
        "Tue, 28 Jul 2026 10:01:00 GMT",  // obsolete alphabetic zones
        "Tue, 28 Jul 2026 05:01:00 EST",
        "Tue,  28 Jul 2026 10:01:00  +0000",  // sloppy whitespace
    ])
    func parsesRealWorldDateHeaderShapes(header: String) {
        let message = EMLParser().parse("Date: \(header)\r\nSubject: T\r\n\r\nBody")

        #expect(message.date == ISO8601DateFormatter().date(from: "2026-07-28T10:01:00Z"))
    }

    @Test func leavesDateNilForUnparsableHeader() {
        // A wrong instant is worse than a missing one: no guessing, no fallback.
        let message = EMLParser().parse("Date: sometime last week\r\nSubject: T\r\n\r\nBody")

        #expect(message.date == nil)
    }

    @Test func unfoldsFoldedHeaders() {
        let eml = "Subject: A very long\r\n subject line\r\n\r\nBody"
        let message = EMLParser().parse(eml)

        #expect(message.subject == "A very long subject line")
    }

    @Test func handlesMissingHeadersGracefully() {
        let message = EMLParser().parse("X-Custom: nothing useful\r\n\r\nJust a body")

        #expect(message.from == nil)
        #expect(message.cc == nil)
        #expect(message.subject == nil)
        #expect(message.date == nil)
        #expect(message.body == "Just a body")
    }

    /// Several recipients, a folded header and an encoded display name, all
    /// in one `Cc` line, as the mail that showed the field missing had them.
    @Test func parsesCcWithSeveralRecipients() {
        let message = EMLParser().parse(ccEML)

        #expect(message.to == "Anton Fillmann <anton@example.com>, Jane Doe <jane@example.com>")
        #expect(message.cc == "Müller Anna <anna@example.com>, Team Lead <lead@example.com>")
    }

    /// Header names are case-insensitive, and mailers differ in how they spell
    /// this one.
    @Test(arguments: ["Cc", "CC", "cc"])
    func readsCcWhateverTheCaseOfItsName(name: String) {
        let message = EMLParser().parse("\(name): Team <team@example.com>\r\nSubject: T\r\n\r\nBody")

        #expect(message.cc == "Team <team@example.com>")
    }
}

// MARK: -

/// Which parts of the MIME tree become the body. A text part is not body just
/// because it is text: a file can be `text/plain` too, and a body can arrive in
/// several parts.
struct BodySelectionTests {

    @Test func neverTakesAnAttachedTextFileForTheBody() {
        let message = EMLParser().parse(textAttachmentEML)

        #expect(message.body == "Hallo Anton, die Notizen hängen an.")
        #expect(message.body.contains("Inhalt der angehängten Datei") == false)
        // It is still an attachment, only no longer the body as well.
        #expect(message.attachmentNames == ["Notizen.txt"])
    }

    @Test func joinsTheTextOnEitherSideOfAnInlineAttachment() {
        let message = EMLParser().parse(splitBodyEML)

        #expect(message.body == "Guten Tag, hier das Formular:\n\nFreundliche Grüsse\nAnton Fillmann")
        #expect(message.attachmentNames == ["Formular.pdf"])
    }

    @Test func leavesTheBodyEmptyForAMailOfAttachmentsOnly() {
        let message = EMLParser().parse(attachmentOnlyEML)

        #expect(message.body.isEmpty)
        #expect(message.attachmentNames == ["Scan.pdf"])
    }

    /// A container without a boundary cannot be split, so its raw text is all
    /// there is. Shown raw, a malformed mail stays visible instead of vanishing.
    @Test func keepsTheRawBodyOfAContainerThatCannotBeSplit() {
        let message = EMLParser().parse("Content-Type: multipart/mixed\r\nSubject: T\r\n\r\nNur Text")

        #expect(message.body == "Nur Text")
    }
}

// MARK: -
struct AttachmentsTests {

    @Test func collectsAttachmentFilenamesAcrossMixedTree() {
        let message = EMLParser().parse(mixedEML)

        // Plain filename, RFC 2047-decoded filename, and Content-Type `name`
        // fallback, in document order. The inline image part is excluded.
        #expect(message.attachmentNames == ["Lebenslauf.pdf", "Prüfung.pdf", "Foto.png"])
        #expect(message.attachmentNames.contains("signature.png") == false)
    }

    @Test func extractsBodyFromNestedAlternativeAlongsideAttachments() {
        let message = EMLParser().parse(mixedEML)

        // Body still comes from the nested multipart/alternative's text/plain.
        #expect(message.body == "Hallo Anton, im Anhang finden Sie die Unterlagen.")
    }

    @Test func listsNoAttachmentsForSinglePartMail() {
        #expect(EMLParser().parse(simpleEML).attachments.isEmpty)
    }

    @Test func listsNamedInlineDocumentAsAttachment() {
        let message = EMLParser().parse(inlineDocumentEML)

        // Apple Mail dispositions a real PDF attachment as `inline`. Excluding
        // every inline part dropped it from the listing without a word.
        #expect(message.attachmentNames == ["Ausweis.pdf"])
    }

    @Test func stillExcludesNamedInlineImage() {
        let message = EMLParser().parse(inlineDocumentEML)

        // The rule reaches documents, not body furniture: a named inline image
        // is a signature logo far more often than an attachment (v0.5.0).
        #expect(message.attachmentNames.contains("logo.png") == false)
    }

    @Test func excludesInlineDocumentReferencedByContentID() {
        let message = EMLParser().parse(inlineDocumentEML)

        // A part the HTML pulls in via `cid:` is embedded content, whatever its
        // media type, so `Content-ID` vetoes the inline rule.
        #expect(message.attachmentNames.contains("embedded.pdf") == false)
    }

    @Test func extractsNamedInlineDocument() throws {
        let parts = EMLParser().attachmentParts(from: inlineDocumentEML)

        // Listing and extraction share one traversal, so the fix has to reach
        // the bytes too: the earlier bug lost the PDF in both places.
        #expect(parts.map { $0.filename } == ["Ausweis.pdf"])
    }

    @Test func excludesSMIMESignatureFromAttachments() {
        let message = EMLParser().parse(signedEML)

        // The genuine attachment is listed; the detached S/MIME signature
        // (smime.p7s) is cryptographic machinery and must not appear.
        #expect(message.attachmentNames == ["Vertrag.pdf"])
        #expect(message.attachmentNames.contains("smime.p7s") == false)
        // Body still comes from the signed content's text/plain part.
        #expect(message.body == "Hallo Anton, im Anhang der Vertrag.")
    }

    @Test func recognizesAllSMIMEArtifactTypes() {
        // Both the modern and the legacy Outlook (`x-`) spellings, for the
        // detached signature and the PKCS#7 envelope.
        #expect(parseContentType("application/pkcs7-signature").isSMIMEArtifact)
        #expect(parseContentType("application/x-pkcs7-signature").isSMIMEArtifact)
        #expect(
            parseContentType("application/pkcs7-mime; smime-type=enveloped-data").isSMIMEArtifact)
        #expect(parseContentType("application/x-pkcs7-mime").isSMIMEArtifact)
        // A real attachment type is not an S/MIME artifact.
        #expect(parseContentType("application/pdf").isSMIMEArtifact == false)
    }
}

// MARK: -
extension EmailMessage {

    /// The attachment filenames, which is the shape the assertions here care
    /// about: selection and naming are what `EMLParser` decides, the media type
    /// only rides along for the renderer.
    var attachmentNames: [String] {
        return self.attachments.map { $0.name }
    }
}
