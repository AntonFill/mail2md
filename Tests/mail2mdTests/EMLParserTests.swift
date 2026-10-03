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

    /// Two folds whose joining space ended up at the edge of the value. Outlook
    /// folds a long subject right after its colon, so the value starts on the
    /// next line and the space joining it to the empty first one led it (found
    /// 2026-10-03 on a real mail); a line of only whitespace continues a header
    /// with nothing, and the space before it trailed.
    @Test(arguments: [
        "Subject:\r\n =?Windows-1252?Q?Einladung_zum_Gespr=E4ch?=\r\n\r\nBody",
        "Subject: Einladung zum Gespräch\r\n \r\n\r\nBody",
    ])
    func leavesNoSpaceAtTheEdgeOfAFoldedHeader(eml: String) {
        let message = EMLParser().parse(eml)

        #expect(message.subject == "Einladung zum Gespräch")
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

    /// RFC 2046 §5.1.4: the forms of an alternative stand in increasing
    /// faithfulness, and a client shows the last one it can. Outlook's plain
    /// form writes a link as its text and its address side by side, and only
    /// the HTML form says which is which.
    @Test func takesTheLastFormOfAnAlternative() {
        let eml = """
            Content-Type: multipart/alternative; boundary="b"\r
            \r
            --b\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Gesendet von Outlook für iOS<https://example.com/ios>\r
            --b\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><body><div>Gesendet von <a href="https://example.com/ios">Outlook für iOS</a></div></body></html>\r
            --b--\r
            """

        #expect(EMLParser().parse(eml).body == "Gesendet von [Outlook für iOS](https://example.com/ios)")
    }

    /// The order is the sender's word on faithfulness, not the media type: a
    /// plain form after the HTML one is the last, so it is the one taken.
    @Test func takesThePlainFormWhenItComesLast() {
        let eml = """
            Content-Type: multipart/alternative; boundary="b"\r
            \r
            --b\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><body><p>Hallo <b>Anton</b></p></body></html>\r
            --b\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Hallo Anton\r
            --b--\r
            """

        #expect(EMLParser().parse(eml).body == "Hallo Anton")
    }

    /// A calendar invitation adds its event as a third form, one this tool
    /// cannot show, so the HTML form before it is the last one it can.
    @Test func takesTheLastFormItCanShow() {
        let eml = """
            Content-Type: multipart/alternative; boundary="b"\r
            \r
            --b\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Einladung: Kennenlernen\r
            --b\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><body><p><b>Einladung:</b> Kennenlernen</p></body></html>\r
            --b\r
            Content-Type: text/calendar; charset=utf-8; method=REQUEST\r
            \r
            BEGIN:VCALENDAR\r
            END:VCALENDAR\r
            --b--\r
            """

        #expect(EMLParser().parse(eml).body == "**Einladung:** Kennenlernen")
    }

    /// An HTML form travels with its images in a `multipart/related`, which
    /// is then the last form. The image is no text and stays out of the body.
    @Test func readsTheLastFormFromARelatedContainer() {
        let eml = """
            Content-Type: multipart/alternative; boundary="alt"\r
            \r
            --alt\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Hallo Anton\r
            \r
            [cid:logo]\r
            --alt\r
            Content-Type: multipart/related; boundary="rel"\r
            \r
            --rel\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><body><p>Hallo <i>Anton</i></p><img src="cid:logo"></body></html>\r
            --rel\r
            Content-Type: image/png\r
            Content-ID: <logo>\r
            Content-Transfer-Encoding: base64\r
            \r
            iVBORw0KGgo=\r
            --rel--\r
            --alt--\r
            """

        #expect(EMLParser().parse(eml).body == "Hallo *Anton*")
    }

    /// Apple Mail sends a document placed in the middle of a mail as an HTML
    /// form in pieces, one on either side of the document. All pieces make up
    /// the last form, so all of them reach the note, and the plain form's
    /// placeholder for the document (U+FFFC) does not.
    @Test func joinsTheHTMLOnEitherSideOfAnAttachmentInTheLastForm() {
        let eml = """
            Content-Type: multipart/alternative; boundary="alt"\r
            \r
            --alt\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Guten Tag,\r
            \r
            hier das Formular:\r
            \u{FFFC}\r
            \r
            Freundliche Grüsse\r
            Anton\r
            --alt\r
            Content-Type: multipart/mixed; boundary="mix"\r
            \r
            --mix\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><head></head><body>Guten Tag,<div><br></div><div>hier das Formular:</div><div></div></body></html>\r
            --mix\r
            Content-Type: application/pdf; name="Formular.pdf"\r
            Content-Disposition: inline; filename="Formular.pdf"\r
            Content-Transfer-Encoding: base64\r
            \r
            JVBERi0xLjQK\r
            --mix\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><head></head><body><div></div><div><br></div><div>Freundliche Grüsse</div><div>Anton</div></body></html>\r
            --mix--\r
            --alt--\r
            """
        let message = EMLParser().parse(eml)

        #expect(message.body == "Guten Tag,\n\nhier das Formular:\n\nFreundliche Grüsse\nAnton")
        #expect(message.attachmentNames == ["Formular.pdf"])
    }

    /// A newsletter that is all images shows nothing once the images are gone,
    /// so the form before it, the plain one, is taken instead.
    @Test func fallsBackToThePlainFormWhenTheHTMLShowsNothing() {
        let eml = """
            Content-Type: multipart/alternative; boundary="b"\r
            \r
            --b\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Herbstaktion: alle Velos 20 % günstiger.\r
            --b\r
            Content-Type: text/html; charset=utf-8\r
            \r
            <html><body><a href="https://example.com/aktion"><img src="https://example.com/aktion.png" alt=""></a></body></html>\r
            --b--\r
            """

        #expect(EMLParser().parse(eml).body == "Herbstaktion: alle Velos 20 % günstiger.")
    }
}

// MARK: -

/// What a reader never sees stays out of the note, in the headers as in the
/// body, and what is left in for a second look is counted.
struct InvisibleTextTests {

    @Test func dropsThePreviewTextAndItsFiller() {
        let message = EMLParser().parse(hiddenTextEML)

        #expect(message.body.contains("Preview text") == false)
        #expect(message.body.unicodeScalars.contains { $0.value == 0x200C } == false)
        #expect(message.body.hasPrefix("Hello there,"))
    }

    @Test func cleansTheSubjectAndTheBodyAlike() {
        let message = EMLParser().parse(hiddenTextEML)

        #expect(message.subject == "API versioning")
        // One zero-width space each in subject and body; the joiner between
        // two letters stays and is reported.
        #expect(message.invisibleCharacters == InvisibleCharacters.Report(zeroWidthSpaces: 2, joiners: 1))
    }

    @Test func readsTheSpacesOfACodeBlockAsSpaces() {
        let message = EMLParser().parse(hiddenTextEML)

        #expect(message.body.hasSuffix("```\ncurl -i\n```"))
    }

    @Test func reportsNothingForAnOrdinaryMail() {
        #expect(EMLParser().parse(simpleEML).invisibleCharacters.isEmpty)
    }
}

// MARK: -

/// A file that is not UTF-8 is read byte for byte, every part in the charset
/// it declares. A UTF-8 file is read as it always was.
struct CharsetFallbackTests {

    @Test func readsAUTF8FileAsText() throws {
        let reading = try #require(EMLParser.reading(Data(simpleEML.utf8)))

        #expect(reading.parser.source == .utf8)
        #expect(reading.raw == simpleEML)
    }

    @Test func readsALatin1FileInTheCharsetItDeclares() throws {
        let reading = try #require(EMLParser.reading(latin1EML))
        let message = reading.parser.parse(reading.raw)

        #expect(message.subject == "Freischaltung Ihrer Bestellung bestätigt")
        #expect(message.body == "Sehr geehrter Herr Fillmann,\n\nIhr Ticket ist freigeschaltet und gültig ab Montag.\n\nFreundliche Grüße")
    }

    /// Quoted-printable allows no raw bytes beyond ASCII, but an insurer's web
    /// form sends them. They are read in the part's charset like the escaped
    /// one, and byte A4 is the euro sign there, not Latin-1's currency sign.
    /// The real mail sends an HTML form after this part, which is the one
    /// read, so the part stands alone here.
    @Test func readsRawBytesInAQuotedPrintablePartInItsCharset() throws {
        let eml = latin1("""
            Subject: Ihre Anfrage\r
            Content-Type: text/plain; charset=ISO-8859-15\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            Grüße aus M=FCnchen, der Beitrag beträgt 12 \u{00A4} im Monat.\r
            """)
        let reading = try #require(EMLParser.reading(eml))
        let message = reading.parser.parse(reading.raw)

        #expect(message.body == "Grüße aus München, der Beitrag beträgt 12 € im Monat.")
    }

    /// The insurer's whole mail: a file that is not UTF-8 because of its plain
    /// form, read from its HTML form, which writes every umlaut as an entity.
    @Test func readsTheHTMLFormOfAFileThatIsNotUTF8() throws {
        let reading = try #require(EMLParser.reading(latin9QuotedPrintableEML))
        let message = reading.parser.parse(reading.raw)

        #expect(message.body == "Grüße aus München, der [Beitrag](https://example.com/beitrag) beträgt 12 € im Monat.")
    }

    /// Each part is read in the charset it declares itself, not in the first
    /// one the mail declares: byte A4 in the second part is the euro sign.
    @Test func readsEachPartInItsOwnCharset() throws {
        let eml = latin1("""
            Content-Type: multipart/mixed; boundary="b"\r
            \r
            --b\r
            Content-Type: text/plain; charset=iso-8859-1\r
            Content-Transfer-Encoding: 8bit\r
            \r
            Grüße\r
            --b\r
            Content-Type: text/plain; charset=iso-8859-15\r
            Content-Transfer-Encoding: 8bit\r
            \r
            12 \u{00A4}\r
            --b--\r
            """)
        let reading = try #require(EMLParser.reading(eml))

        #expect(reading.parser.parse(reading.raw).body == "Grüße\n\n12 €")
    }

    @Test func readsAHeaderInUTF8AboveABodyInLatin1() throws {
        let reading = try #require(EMLParser.reading(utf8HeaderLatin1BodyEML))
        let message = reading.parser.parse(reading.raw)

        #expect(message.from == "Jörg Müller <joerg@example.com>")
        #expect(message.subject == "Grüße aus Zürich")
        #expect(message.body == "Schöne Grüße")
    }

    /// Raw bytes declared ISO-8859-1 are read as windows-1252 too, in the
    /// header as in the body: bytes 84 and 93 are „ and “ there.
    @Test func readsRawLatin1BytesAsWindows1252() throws {
        let eml = latin1("""
            Subject: \u{84}Wie neu\u{93}\r
            Content-Type: text/plain; charset=iso-8859-1\r
            Content-Transfer-Encoding: 8bit\r
            \r
            Das Gerät läuft wieder \u{84}wie neu\u{93}.\r
            """)
        let reading = try #require(EMLParser.reading(eml))
        let message = reading.parser.parse(reading.raw)

        #expect(message.subject == "„Wie neu“")
        #expect(message.body == "Das Gerät läuft wieder „wie neu“.")
    }

    /// Without a charset that could stand for its bytes nothing says what they
    /// mean, so the file is refused rather than guessed at. UTF-8 is no such
    /// charset for a file that is not UTF-8, and ASCII declares that there are
    /// no such bytes: a part that sends them anyway is read as windows-1252,
    /// but says nothing about the bytes elsewhere in the mail.
    @Test(arguments: ["", "Content-Type: text/plain; charset=utf-8\r\n", "Content-Type: text/plain; charset=us-ascii\r\n"])
    func refusesAFileThatDeclaresNoCharsetForItsBytes(contentType: String) {
        let data = latin1("Subject: Grüße\r\n\(contentType)\r\nSchöne Grüße\r\n")

        #expect(EMLParser.reading(data) == nil)
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

        // Body still comes from the nested multipart/alternative, its last form.
        #expect(message.body == "Hallo Anton, im Anhang finden Sie die **Unterlagen**.")
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
