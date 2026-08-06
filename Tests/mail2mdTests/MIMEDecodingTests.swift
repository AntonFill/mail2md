//
//  MIMEDecodingTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Testing
@testable import mail2md

struct MIMEDecodingTests {

    @Test func picksTextPlainFromMultipartAlternative() {
        let message = EMLParser().parse(multipartEML)
        let expected = """
            Hallo Anton,

            wir freuen uns, dir eine Zusage machen zu können. Deine Unterlagen haben uns voll überzeugt.

            Willkommen im Team— wir freuen uns auf dich.

            Viele Grüße
            """

        #expect(message.body == expected)
    }

    @Test func decodesQuotedPrintableSoftBreaksAndMultiByte() {
        let message = EMLParser().parse(multipartEML)

        // Soft line break joins the sentence without inserting a newline.
        #expect(message.body.contains("Deine Unterlagen haben uns voll überzeugt."))
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

    @Test func convertsHTMLOnlyMailToMarkdown() {
        let message = EMLParser().parse(htmlOnlyEML)

        #expect(message.body.contains("## Neuigkeiten"))
        // Quoted-printable soft break joins the sentence across the two parts.
        #expect(message.body.contains("Hallo Anton, es gibt **Neues** zu berichten."))
        // No raw HTML leaks through.
        #expect(message.body.contains("<") == false)
    }
}
