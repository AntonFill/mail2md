//
//  EMLFixtures.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

// Anonymized inline fixtures shared by the test suites. Addresses are
// @example.com by convention, bodies are neutral, and the \r line endings are
// load-bearing: they are what a real .eml carries and what the parser unfolds.

let simpleEML = """
    From: Jane Doe <jane@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Projektanfrage iOS\r
    Date: Mon, 15 Jun 2026 09:41:00 +0200\r
    Message-ID: <abc123@example.com>\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton,\r
    \r
    das ist eine Testmail.\r
    """

/// Anonymised real-world shape: multipart/alternative with a quoted-printable
/// text/plain part (soft line breaks, multi-byte `=XX` sequences) plus a
/// text/html part saying the same, and RFC 2047 encoded-word From/Subject
/// headers. The HTML part is the one read, so it carries the soft break in the
/// middle of a word, where collapsing whitespace cannot hide a broken one.
let multipartEML = """
    From: =?utf-8?Q?Jos=C3=A9_Garc=C3=ADa?= <jose@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: =?utf-8?Q?Zusage=3A_deine_Bewerbung?=\r
    Date: Wed, 09 Jul 2026 14:22:31 +0200\r
    Message-ID: <xyz789@example.com>\r
    MIME-Version: 1.0\r
    Content-Type: multipart/alternative; boundary="__boundary_42__"\r
    \r
    This is a multipart message in MIME format.\r
    \r
    --__boundary_42__\r
    Content-Type: text/plain; charset=utf-8\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    Hallo Anton,\r
    \r
    wir freuen uns, dir eine Zusage machen zu k=C3=B6nnen. Deine=\r
     Unterlagen haben uns voll =C3=BCberzeugt.\r
    \r
    Willkommen im Team=E2=80=94 wir freuen uns auf dich.\r
    \r
    Viele Gr=C3=BC=C3=9Fe\r
    \r
    --__boundary_42__\r
    Content-Type: text/html; charset=utf-8\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    <html><body><p>Hallo Anton,</p><p>wir freuen uns, dir eine Zusage machen zu k=C3=B6nnen. Deine Unter=\r
    lagen haben uns <strong>voll =C3=BCberzeugt</strong>.</p><p>Willkommen im Team=E2=80=94 wir freuen uns auf=\r
     dich.</p><p>Viele Gr=C3=BC=C3=9Fe</p></body></html>\r
    \r
    --__boundary_42__--\r
    """

/// Single-part body encoded as base64.
let base64EML = """
    From: Test <t@example.com>\r
    Subject: Base64 body\r
    Content-Type: text/plain; charset=utf-8\r
    Content-Transfer-Encoding: base64\r
    \r
    SGFsbG8gV2VsdCEK\r
    """

/// HTML-only message (no text/plain part), quoted-printable: the case the
/// text/plain preference cannot satisfy, so the body must be converted.
let htmlOnlyEML = """
    From: Newsletter <news@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Update\r
    Date: Fri, 18 Jul 2026 08:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: text/html; charset=utf-8\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    <html><body><h2>Neuigkeiten</h2><p>Hallo Anton, es gibt <strong>Neues</strong>=\r
     zu berichten.</p></body></html>\r
    """

/// Real-world application-mail shape: `multipart/mixed` wrapping a nested
/// `multipart/alternative` body and several attachments. Covers a plain
/// filename, an RFC 2047-encoded filename, a filename taken from the
/// `Content-Type` `name` fallback, and an `inline` part that must NOT be
/// listed as an attachment.
let mixedEML = """
    From: HR <hr@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Ihre Bewerbung\r
    Date: Mon, 20 Jul 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="outer"\r
    \r
    --outer\r
    Content-Type: multipart/alternative; boundary="inner"\r
    \r
    --inner\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton, im Anhang finden Sie die Unterlagen.\r
    --inner\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><p>Hallo Anton, im Anhang finden Sie die <strong>Unterlagen</strong>.</p></body></html>\r
    --inner--\r
    --outer\r
    Content-Type: application/pdf; name="Lebenslauf.pdf"\r
    Content-Disposition: attachment; filename="Lebenslauf.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --outer\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment; filename="=?utf-8?Q?Pr=C3=BCfung.pdf?="\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --outer\r
    Content-Type: image/png; name="Foto.png"\r
    Content-Disposition: attachment\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgo=\r
    --outer\r
    Content-Type: image/png\r
    Content-Disposition: inline; filename="signature.png"\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgo=\r
    --outer--\r
    """

/// The Apple Mail shape that v0.9.4 fixed, with its two neighbours in one
/// tree: a genuine PDF attachment dispositioned `inline` (must be listed), a
/// named inline image (body furniture, must not), and an inline PDF carrying a
/// `Content-ID` (embedded content, must not). Modelled on the anonymized
/// dogfood fixture from the immigration-office mail of 2026-07-22.
let inlineDocumentEML = """
    From: Anton Fillmann <anton@example.com>\r
    To: Amt <amt@example.com>\r
    Subject: Unterlagen zum Gesuch\r
    Date: Wed, 22 Jul 2026 11:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Guten Tag, anbei die gewuenschten Unterlagen.\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: inline; filename="Ausweis.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: image/png\r
    Content-Disposition: inline; filename="logo.png"\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgo=\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: inline; filename="embedded.pdf"\r
    Content-ID: <doc@example.com>\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b--\r
    """

/// S/MIME-signed shape: `multipart/signed` wrapping the real content (a
/// `multipart/mixed` with a genuine attachment) plus the detached PKCS#7
/// signature. The signature `smime.p7s` carries `Content-Disposition:
/// attachment` but must NOT be listed, being cryptographic machinery, not a
/// user attachment. Regression fixture for the v0.5.1 smime.p7s bug.
let signedEML = """
    From: HR <hr@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Signierte Bewerbungsantwort\r
    Date: Mon, 21 Jul 2026 09:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/signed; protocol="application/pkcs7-signature"; micalg=sha-256; boundary="sig"\r
    \r
    --sig\r
    Content-Type: multipart/mixed; boundary="outer"\r
    \r
    --outer\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton, im Anhang der Vertrag.\r
    --outer\r
    Content-Type: application/pdf; name="Vertrag.pdf"\r
    Content-Disposition: attachment; filename="Vertrag.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --outer--\r
    --sig\r
    Content-Type: application/pkcs7-signature; name="smime.p7s"\r
    Content-Disposition: attachment; filename="smime.p7s"\r
    Content-Transfer-Encoding: base64\r
    \r
    MIICSAYJKoZIhvcNAQ==\r
    --sig--\r
    """

/// Extraction edge cases in one `multipart/mixed` tree: two attachments with
/// the same filename (collision), a filename carrying `../` (path traversal), a
/// binary part whose bytes are not valid UTF-8 (must survive verbatim), an
/// unnamed part (extension derived from the media type), and an inline part
/// (excluded). Base64 payloads decode to short, known byte strings.
let extractEML = """
    From: HR <hr@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Unterlagen\r
    Date: Mon, 22 Jul 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Body text.\r
    --b\r
    Content-Type: application/pdf; name="Doc.pdf"\r
    Content-Disposition: attachment; filename="Doc.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment; filename="Doc.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    SGVsbG8=\r
    --b\r
    Content-Type: application/octet-stream\r
    Content-Disposition: attachment; filename="../evil.bin"\r
    Content-Transfer-Encoding: base64\r
    \r
    SGk=\r
    --b\r
    Content-Type: application/octet-stream; name="logo.bin"\r
    Content-Disposition: attachment; filename="logo.bin"\r
    Content-Transfer-Encoding: base64\r
    \r
    //4AAQ==\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment\r
    Content-Transfer-Encoding: base64\r
    \r
    eA==\r
    --b\r
    Content-Type: image/png\r
    Content-Disposition: inline; filename="pixel.png"\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgo=\r
    --b--\r
    """

/// Attachment names carrying characters that a URL parser would read as
/// structure (`#` fragment, `?` query, `%` escape), plus a bare `.` that must
/// not survive as a filename.
let punctuationNameEML = """
    From: Buchhaltung <billing@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Rechnungen\r
    Date: Mon, 03 Aug 2026 09:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Body text.\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment; filename="Rechnung #123.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment; filename="Bericht%20final.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: attachment; filename="Wann? Jetzt.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: application/octet-stream\r
    Content-Disposition: attachment; filename="."\r
    Content-Transfer-Encoding: base64\r
    \r
    SGk=\r
    --b--\r
    """

/// The shape of the mail that showed `cc` missing (2026-09-08): several
/// recipients in `To` and in `Cc`, the `Cc` header folded onto a second line,
/// and an RFC 2047-encoded display name in the Outlook order, surname first.
let ccEML = """
    From: Personalabteilung <hr@example.com>\r
    To: Anton Fillmann <anton@example.com>, Jane Doe <jane@example.com>\r
    Cc: =?utf-8?Q?M=C3=BCller_Anna?= <anna@example.com>,\r
     Team Lead <lead@example.com>\r
    Subject: Protokoll der Sitzung\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Guten Tag, anbei das Protokoll.\r
    """

/// A text file attached to an ordinary mail. It is `text/plain` just like the
/// body, and it sits at the outer level while the body is nested one level
/// deeper in a `multipart/alternative`: before v1.2.0 it became the body.
let textAttachmentEML = """
    From: HR <hr@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Notizen\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="outer"\r
    \r
    --outer\r
    Content-Type: multipart/alternative; boundary="inner"\r
    \r
    --inner\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton, die Notizen hängen an.\r
    --inner\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><p>Hallo Anton, die Notizen hängen an.</p></body></html>\r
    --inner--\r
    --outer\r
    Content-Type: text/plain; charset=utf-8; name="Notizen.txt"\r
    Content-Disposition: attachment; filename="Notizen.txt"\r
    \r
    Inhalt der angehängten Datei.\r
    --outer--\r
    """

/// The Apple Mail shape of a plain-text mail with a document placed in the
/// middle of the text: the text arrives in two parts, one on either side of
/// the attachment. Before v1.2.0 only the first part reached the note.
let splitBodyEML = """
    From: Anton Fillmann <anton@example.com>\r
    To: Amt <amt@example.com>\r
    Subject: Unterlagen\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Guten Tag, hier das Formular:\r
    --b\r
    Content-Type: application/pdf\r
    Content-Disposition: inline; filename="Formular.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Freundliche Grüsse\r
    Anton Fillmann\r
    --b--\r
    """

/// The Apple Mail shape of a plain-text mail with a picture placed in the
/// middle of the text: a part of its own between the two halves, named and
/// `inline`, without a `Content-ID`. The picture is a valid PNG of 3 × 2
/// pixels. The parameters build the neighbours the rule has to tell apart: a
/// picture with text on one side only, one a `Content-ID` makes a resource of
/// the HTML, one in a container other than `mixed`.
func splitImageMail(container: String = "multipart/mixed", contentID: String? = nil, textBefore: Bool = true, textAfter: Bool = true) -> String {
    let before = textBefore ? "--b\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nGuten Tag, hier der Ausschnitt:\r\n" : ""
    let after = textAfter ? "--b\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nFreundliche Grüsse\r\n" : ""
    let identity = contentID.map { "Content-ID: \($0)\r\n" } ?? ""

    return """
        From: Anton Fillmann <anton@example.com>\r
        To: Amt <amt@example.com>\r
        Subject: Ausschnitt\r
        Date: Mon, 07 Sep 2026 10:00:00 +0200\r
        MIME-Version: 1.0\r
        Content-Type: \(container); boundary="b"\r
        \r
        \(before)--b\r
        Content-Type: image/png\r
        Content-Disposition: inline; filename="PastedGraphic-1.png"\r
        \(identity)Content-Transfer-Encoding: base64\r
        \r
        iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAAAAAC4HznGAAAAD0lEQVR4nGM4ceIEAxADABLIBLEaJ2FIAAAAAElFTkSuQmCC\r
        \(after)--b--\r
        """
}

let splitImageEML = splitImageMail()

/// The Outlook shape of the mail that lost a screenshot without a word
/// (2026-09-29): a `multipart/related` around the alternative, the HTML showing
/// the screenshot in a paragraph of its own and a linked icon under the
/// signature, both parts addressed by `cid:`. The plain form marks the
/// screenshot as `[cid:…]`, but the HTML form is the one read. The screenshot
/// is a valid PNG of 3 × 2 pixels the HTML shows at 474 × 464, the icon one of
/// 1 × 1 whose size the HTML leaves open.
let inlineImageEML = """
    From: Jane Doe <jane@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: AW: Ausschnitt\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/related; type="multipart/alternative"; boundary="rel"\r
    \r
    --rel\r
    Content-Type: multipart/alternative; boundary="alt"\r
    \r
    --alt\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Hallo Anton,\r
    \r
    hier der Ausschnitt aus dem Portal:\r
    \r
    [cid:image001.png@01DC1234.5678ABCD]\r
    \r
    Gruss\r
    Jane\r
    --alt\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><p class=MsoNormal>Hallo Anton,<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p>\r
    <p class=MsoNormal>hier der Ausschnitt aus dem Portal:<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p>\r
    <p class=MsoNormal><img width=474 height=464 style="width:4.9375in;height:4.8333in" id="Grafik_x0020_1" src="cid:image001.png@01DC1234.5678ABCD"><o:p></o:p></p>\r
    <p class=MsoNormal><o:p>&nbsp;</o:p></p><p class=MsoNormal>Gruss<br>Jane<o:p></o:p></p>\r
    <p class=MsoNormal><a href="https://www.example.com/jane"><img alt="LinkedIn" src="cid:image002.png@01DC1234.5678ABCD"></a><o:p></o:p></p></body></html>\r
    --alt--\r
    --rel\r
    Content-Type: image/png; name="image001.png"\r
    Content-Disposition: inline; filename="image001.png"\r
    Content-ID: <image001.png@01DC1234.5678ABCD>\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAAAAAC4HznGAAAAD0lEQVR4nGM4ceIEAxADABLIBLEaJ2FIAAAAAElFTkSuQmCC\r
    --rel\r
    Content-Type: image/png; name="image002.png"\r
    Content-Disposition: inline; filename="image002.png"\r
    Content-ID: <image002.png@01DC1234.5678ABCD>\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGM4AQAAygDJmcpdfgAAAABJRU5ErkJggg==\r
    --rel--\r
    """

/// The shape of a support system's reply: a picture sent as an attachment of
/// type `application/octet-stream`, which the HTML shows in place through its
/// `Content-ID` all the same. Listed as an attachment it is not left out, and
/// embedded it must not be written twice.
let referencedAttachmentEML = """
    From: Support <support@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Adressänderung\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><p>Ihre Adresse wurde geändert.</p><p><img src="cid:logo.png"></p></body></html>\r
    --b\r
    Content-Type: application/octet-stream; name=logo.png\r
    Content-Disposition: attachment; filename=logo.png\r
    Content-ID: <logo.png>\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGM4AQAAygDJmcpdfgAAAABJRU5ErkJggg==\r
    --b--\r
    """

/// An alternative whose HTML form shows nothing but a picture, a scan, while
/// the plain form says a sentence about it. The picture is a valid PNG of
/// 4 × 4 pixels without a name.
let pictureOnlyEML = """
    From: Scanner <scanner@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Scan\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/alternative; boundary="alt"\r
    \r
    --alt\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    Siehe Bild.\r
    --alt\r
    Content-Type: multipart/related; boundary="rel"\r
    \r
    --rel\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><img src="cid:scan@example.com"></body></html>\r
    --rel\r
    Content-Type: image/png\r
    Content-ID: <scan@example.com>\r
    Content-Transfer-Encoding: base64\r
    \r
    iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAAAAACMmsGiAAAADklEQVR4nGM4AQQMqAQAfRQMgauI/xAAAAAASUVORK5CYII=\r
    --rel--\r
    --alt--\r
    """

/// A mail that is nothing but an attachment, as a scanner sends it. Before
/// v1.2.0 the raw MIME part, base64 and all, became the body.
let attachmentOnlyEML = """
    From: Scanner <scanner@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Scan\r
    Date: Mon, 07 Sep 2026 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: application/pdf; name="Scan.pdf"\r
    Content-Disposition: attachment; filename="Scan.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    JVBERi0xLjQK\r
    --b--\r
    """

/// An HTML-only newsletter in the React Email shape: a hidden preview text
/// with its zero-width filler, a zero-width space in the subject and in the
/// body, a joiner between two letters, and a code block whose space is written
/// the way Resend writes it. The invisible characters are escapes, so the
/// fixture can be read.
let hiddenTextEML = """
    From: Newsletter <news@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: API\u{200B} versioning\r
    Date: Tue, 29 Sep 2026 10:00:00 +0000\r
    MIME-Version: 1.0\r
    Content-Type: text/html; charset=utf-8\r
    \r
    <html><body><div style="display:none" data-skip-in-text="true">Preview text<div> \u{200C}\u{200B}\u{200D}\u{200E}\u{200F}\u{FEFF}</div></div>\r
    <p>Hello\u{200B} there, it\u{200D}s new.</p>\r
    <pre><code>curl\u{00A0}\u{200D}\u{200B}-i</code></pre></body></html>\r
    """

// MARK: - Files that are not UTF-8

/// The bytes of a text as Latin-1 writes it, one byte per character, the way
/// an old mail program stored a mail. Every character stands for its byte, so
/// a fixture can spell out bytes that no UTF-8 string holds.
func latin1(_ text: String) -> Data {
    return Data(text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
}

/// The shape of an old booking confirmation: one plain part in ISO-8859-1,
/// transferred as 8bit, with raw Latin-1 bytes in the body and in the subject.
/// The file is not UTF-8, so it can only be read in the charset it declares.
let latin1EML = latin1("""
    From: Kundenservice <service@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Freischaltung Ihrer Bestellung bestätigt\r
    Date: Tue, 02 Aug 2016 10:00:00 +0200\r
    MIME-Version: 1.0\r
    Content-Type: text/plain; charset=iso-8859-1\r
    Content-Transfer-Encoding: 8BIT\r
    \r
    Sehr geehrter Herr Fillmann,\r
    \r
    Ihr Ticket ist freigeschaltet und gültig ab Montag.\r
    \r
    Freundliche Grüße\r
    """)

/// The shape of a reply from an insurer's web form: an alternative whose plain
/// part declares ISO-8859-15 and quoted-printable, yet carries two umlauts as
/// raw bytes beside an escaped one. `\u{00A4}` is the raw byte A4, the euro
/// sign in ISO-8859-15 and the currency sign in Latin-1. The HTML part says
/// the same in ASCII, its umlauts written as entities, and links a word the
/// plain part leaves bare, as the real one does.
let latin9QuotedPrintableEML = latin1("""
    From: Kundenservice <service@example.com>\r
    To: Anton Fillmann <anton@example.com>\r
    Subject: Ihre Anfrage\r
    Date: Fri, 01 Mar 2024 19:30:00 +0100\r
    MIME-Version: 1.0\r
    Content-Type: multipart/alternative; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=ISO-8859-15\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    Grüße aus M=FCnchen, der Beitrag beträgt 12 \u{00A4} im Monat.\r
    --b\r
    Content-Type: text/html; charset=US-ASCII\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    <p>Gr&uuml;&szlig;e aus M&uuml;nchen, der <a href=3D"https://example.com/beitrag">Beitrag</a> betr&auml;gt 12 &euro; im Monat.</p>\r
    --b--\r
    """)

/// A header in UTF-8, as a current server writes one, above a body still in
/// Latin-1: the file as a whole is neither.
let utf8HeaderLatin1BodyEML = Data("""
    From: Jörg Müller <joerg@example.com>\r
    Subject: Grüße aus Zürich\r
    Content-Type: text/plain; charset=iso-8859-1\r
    Content-Transfer-Encoding: 8bit\r
    \r

    """.utf8) + latin1("Schöne Grüße\r\n")

/// A Latin-1 mail with a file attached as raw binary bytes, so the bytes reach
/// the parser only as they stood in the file.
let latin1AttachmentEML = latin1("""
    Subject: Daten\r
    Content-Type: multipart/mixed; boundary="b"\r
    \r
    --b\r
    Content-Type: text/plain; charset=iso-8859-1\r
    Content-Transfer-Encoding: 8bit\r
    \r
    Grüße\r
    --b\r
    Content-Type: application/octet-stream; name="daten.bin"\r
    Content-Disposition: attachment; filename="daten.bin"\r
    Content-Transfer-Encoding: binary\r
    \r
    \u{00FF}\u{00FE}\u{00E4}\r
    --b--\r
    """)
