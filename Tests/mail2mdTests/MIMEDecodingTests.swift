//
//  MIMEDecodingTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct MIMEDecodingTests {

    @Test func decodesTheHTMLFormOfMultipartAlternative() {
        let message = EMLParser().parse(multipartEML)
        let expected = """
            Hallo Anton,

            wir freuen uns, dir eine Zusage machen zu können. Deine Unterlagen haben uns **voll überzeugt**.

            Willkommen im Team— wir freuen uns auf dich.

            Viele Grüße
            """

        #expect(message.body == expected)
    }

    @Test func decodesQuotedPrintableSoftBreaksAndMultiByte() {
        let message = EMLParser().parse(multipartEML)

        // Soft line break joins the word without inserting anything.
        #expect(message.body.contains("Deine Unterlagen haben uns **voll überzeugt**."))
        // 3-byte UTF-8 sequence =E2=80=94 decodes to an em dash.
        #expect(message.body.contains("Willkommen im Team—"))
        // No raw QP artefacts leak through.
        #expect(message.body.contains("=C3") == false)
        #expect(message.body.contains("__boundary_42__") == false)
        #expect(message.body.contains("<html>") == false)
    }

    @Test func decodesRFC2047EncodedHeaders() {
        let message = EMLParser().parse(multipartEML)

        #expect(message.subject == "Zusage: deine Bewerbung")
        #expect(message.from == "José García <jose@example.com>")
    }

    @Test func decodesBase64Body() {
        let message = EMLParser().parse(base64EML)

        #expect(message.body == "Hallo Welt!")
    }

    @Test func honoursNonUTF8Charset() {
        // 0xA4 is the euro sign in ISO-8859-15 (but the currency sign in
        // ISO-8859-1), proving the charset label drives decoding.
        let eml = """
            Subject: Preis\r
            Content-Type: text/plain; charset=iso-8859-15\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            Das kostet 10 =A4.\r
            """
        let message = EMLParser().parse(eml)

        #expect(message.body == "Das kostet 10 €.")
    }

    /// A file read byte for byte keeps the bytes of a part sent as raw binary.
    /// Taken back through UTF-8, every byte above ASCII would come out as two.
    @Test func keepsTheBytesOfABinaryPartInAFileThatIsNotUTF8() throws {
        let reading = try #require(EMLParser.reading(latin1AttachmentEML))
        let parts = reading.parser.attachmentParts(from: reading.raw)

        #expect(parts.map { decodeToBytes($0.entity) } == [Data([0xFF, 0xFE, 0xE4])])
    }

    @Test func convertsHTMLOnlyMailToMarkdown() {
        let message = EMLParser().parse(htmlOnlyEML)

        #expect(message.body.contains("## Neuigkeiten"))
        // Quoted-printable soft break joins the sentence across the two parts.
        #expect(message.body.contains("Hallo Anton, es gibt **Neues** zu berichten."))
        // No raw HTML leaks through.
        #expect(message.body.contains("<") == false)
    }
}

// MARK: -

/// ISO-8859-1, ASCII and windows-1252 are read as windows-1252, the way a mail
/// program reads them. A ticket system declared ISO-8859-1 and still sent „
/// and “ as the windows-1252 bytes 84 and 93, which ISO-8859-1 itself reads as
/// invisible control characters (five archive mails, found 2026-10-02).
struct Windows1252Tests {

    @Test func readsQuotationMarksInAQuotedPrintablePart() {
        let eml = """
            Subject: Status\r
            Content-Type: text/plain; charset=iso-8859-1\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            Das Ger=E4t l=E4uft wieder =84wie neu=93.\r
            """

        #expect(EMLParser().parse(eml).body == "Das Gerät läuft wieder „wie neu“.")
    }

    @Test func readsThemInABase64Part() {
        let eml = """
            Subject: Status\r
            Content-Type: text/plain; charset=iso-8859-1\r
            Content-Transfer-Encoding: base64\r
            \r
            RGFzIEdlcuR0IGzkdWZ0IHdpZWRlciCEd2llIG5ldZMu\r
            """

        #expect(EMLParser().parse(eml).body == "Das Gerät läuft wieder „wie neu“.")
    }

    @Test func readsThemInAnEncodedWord() {
        let eml = """
            Subject: =?iso-8859-1?Q?=84Wie_neu=93?=\r
            \r
            Hallo\r
            """

        #expect(EMLParser().parse(eml).subject == "„Wie neu“")
    }

    /// ASCII ends at 7F, yet a mailer that declares it may still send bytes
    /// beyond. Refused, such a quoted-printable part used to appear as its raw
    /// escapes.
    @Test func readsBytesBeyondASCIIInAPartThatDeclaresASCII() {
        let eml = """
            Subject: Status\r
            Content-Type: text/plain; charset=us-ascii\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            Sch=F6ne Gr=FC=DFe\r
            """

        #expect(EMLParser().parse(eml).body == "Schöne Grüße")
    }

    /// Foundation refuses the whole text at any of the five bytes windows-1252
    /// leaves unassigned. The standard reads each as the control character of
    /// the same number, and the text around it stays readable.
    @Test(arguments: [String.Encoding.isoLatin1, .windowsCP1252])
    func readsTheFiveUnassignedBytesAsControlCharacters(encoding: String.Encoding) {
        let bytes: [UInt8] = [0x84, 0x81, 0x8D, 0x8F, 0x90, 0x9D, 0x93]

        #expect(decodeText(bytes, encoding: encoding) == "„\u{81}\u{8D}\u{8F}\u{90}\u{9D}“")
    }

    /// Foundation's windows-1252 reads every byte the encoding assigns, and it
    /// does so without the table, so no slip in the table can hide.
    @Test func agreesWithFoundationOnEveryByteTheEncodingAssigns() {
        let unassigned: Set<UInt8> = [0x81, 0x8D, 0x8F, 0x90, 0x9D]
        let assigned = (UInt8.min...UInt8.max).filter { unassigned.contains($0) == false }
        let differing = assigned.filter { decodeText([$0], encoding: .windowsCP1252) != String(bytes: [$0], encoding: .windowsCP1252) }

        #expect(assigned.count == 251)
        #expect(differing.isEmpty)
    }
}

// MARK: -

/// An address header as a reader wants it. What a mail program needs and a
/// reader does not goes: the quotes around a plain name, the brackets around
/// an address without one, and a name that is only the address again, which
/// Outlook writes for everybody not in its contacts (223 of 1'500 address
/// headers in the archive, measured 2026-10-03).
struct AddressListTests {

    @Test(arguments: [
        "\"anna@example.com\" <anna@example.com>",
        "\"'anna@example.com'\" <anna@example.com>",
        "\"Anna@Example.com\" <anna@example.com>",
        "<anna@example.com>",
        "anna@example.com",
    ])
    func writesTheBareAddressWhereTheNameAddsNothing(header: String) {
        #expect(normalizeAddressList(header) == "anna@example.com")
    }

    @Test func dropsTheQuotesAroundANameWithoutAComma() {
        #expect(normalizeAddressList("\"Muster AG\"  <info@example.com>") == "Muster AG <info@example.com>")
    }

    @Test func keepsTheQuotesAroundANameWithACommaOrBrackets() {
        let header = "\"Muster, Jana\" <jana@example.com>, \"Team <Support>\" <team@example.com>"

        #expect(normalizeAddressList(header) == header)
    }

    @Test func quotesANameWhoseCommaOnlyDecodingReveals() {
        // Decoding the whole header used to set the comma bare, and the list
        // read as three mailboxes instead of two.
        let header = "\"Muster, Jana\" <jana@example.com>, =?iso-8859-1?Q?M=FCller=2C_J=F6rg?= <joerg@example.com>"

        #expect(normalizeAddressList(header) == "\"Muster, Jana\" <jana@example.com>, \"Müller, Jörg\" <joerg@example.com>")
    }

    @Test func decodesAName() {
        #expect(normalizeAddressList("=?utf-8?Q?Andr=C3=A9_Muster?= <andre@example.com>") == "André Muster <andre@example.com>")
    }

    @Test func trimsTheSpacesAnEncodedNameCarriesAtItsEdges() {
        #expect(normalizeAddressList("=?utf-8?Q?_Jana_Muster_?= <jana@example.com>") == "Jana Muster <jana@example.com>")
    }

    @Test func dropsTheQuotesAMailerEncodedWithTheName() {
        let header = "=?iso-8859-1?Q?=22Jana_M=FCller_=7C_Muster_AG=22?= <jana@example.com>"

        #expect(normalizeAddressList(header) == "Jana Müller | Muster AG <jana@example.com>")
    }

    @Test func keepsTheQuotesOfANameMadeOfTwoQuotedStrings() {
        #expect(normalizeAddressList("\"Muster\" \"AG\" <info@example.com>") == "\"Muster\" \"AG\" <info@example.com>")
    }

    @Test func unescapesAQuotedName() {
        #expect(normalizeAddressList("\"Jana \\\"JM\\\" Muster\" <jana@example.com>") == "Jana \"JM\" Muster <jana@example.com>")
    }

    @Test func keepsAnEscapedQuoteFromEndingTheName() {
        // The comma after the escaped quote still stands inside the name.
        let header = "\"Jana \\\"JM, Team\" <jana@example.com>, \"anna@example.com\" <anna@example.com>"

        #expect(normalizeAddressList(header) == "\"Jana \\\"JM, Team\" <jana@example.com>, anna@example.com")
    }

    @Test func writesEveryMailboxOfAListPlain() {
        let header = "\"anna@example.com\" <anna@example.com>, jana@example.com, <team@example.com>"

        #expect(normalizeAddressList(header) == "anna@example.com, jana@example.com, team@example.com")
    }

    @Test func keepsAListThatIsAlreadyPlain() {
        let header = "anna@example.com, Jana Muster <jana@example.com>"

        #expect(normalizeAddressList(header) == header)
    }

    /// A group, or a name with a bare comma, is no list of mailboxes. Guessing
    /// at it could lose an address, so it comes out as before, only decoded.
    @Test(arguments: [
        "Undisclosed recipients: ;",
        "Muster, Jana <jana@example.com>",
        "jana@example.com (Jana Muster), \"anna@example.com\" <anna@example.com>",
        "<>",
        ",",
    ])
    func leavesAHeaderThatIsNoListOfMailboxesAsItWas(header: String) {
        #expect(normalizeAddressList(header) == header)
    }
}
