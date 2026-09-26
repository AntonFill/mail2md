//
//  EMLFixtures.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

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
/// text/html part, and RFC 2047 encoded-word From/Subject headers.
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
    <html><body><p>Hallo Anton,</p></body></html>\r
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
    <html><body><p>Hallo Anton</p></body></html>\r
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
