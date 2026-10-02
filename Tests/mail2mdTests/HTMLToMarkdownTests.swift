//
//  HTMLToMarkdownTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Testing
@testable import mail2md

struct HTMLToMarkdownTests {

    @Test func convertsCommonEmailTags() {
        let html = """
            <html><body>
            <h1>Willkommen</h1>
            <p>Hallo <strong>Anton</strong>, schön dass du <em>dabei</em> bist.</p>
            <p>Mehr auf <a href="https://example.com">unserer Seite</a>.</p>
            <ul><li>Punkt eins</li><li>Punkt zwei</li></ul>
            <blockquote>Ein Zitat.</blockquote>
            <script>track()</script>
            <img src="https://example.com/pixel.gif">
            </body></html>
            """
        let md = HTMLToMarkdown.convert(html)

        #expect(md.contains("# Willkommen"))
        #expect(md.contains("Hallo **Anton**, schön dass du *dabei* bist."))
        #expect(md.contains("[unserer Seite](https://example.com)"))
        #expect(md.contains("- Punkt eins\n- Punkt zwei"))
        #expect(md.contains("> Ein Zitat."))
        // script/img content and any raw tags are gone.
        #expect(md.contains("track") == false)
        #expect(md.contains("pixel") == false)
        #expect(md.contains("<") == false)
    }

    @Test func decodesEntitiesAndDropsTrackingWhitespace() {
        let md = HTMLToMarkdown.convert("<p>A&nbsp;&amp;&nbsp;B &lt;tag&gt;</p>")

        #expect(md == "A & B <tag>")
    }

    /// Outlook writes every web and mail address as a link whose text is the
    /// address itself. As a Markdown link it would stand there twice.
    @Test(arguments: [
        ("<a href=\"http://www.example.com/\">www.example.com</a>", "www.example.com"),
        ("<a href=\"https://example.com\">https://example.com/</a>", "https://example.com/"),
        ("<a href=\"mailto:jane@example.com\">jane@example.com</a>", "jane@example.com"),
    ])
    func writesALinkThatShowsItsOwnAddressAsText(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test func keepsALinkWhoseTextSaysSomethingElse() {
        let md = HTMLToMarkdown.convert("<p>Mehr <a href=\"https://example.com/docs\">in der Doku</a>.</p>")

        #expect(md == "Mehr [in der Doku](https://example.com/docs).")
    }

    @Test func wrapsInlineCodeInBackticks() {
        let md = HTMLToMarkdown.convert("<p>Setze <code>Polar-Version</code> im Header.</p>")

        #expect(md == "Setze `Polar-Version` im Header.")
    }
}

// MARK: -

/// How a browser stacks blocks: a `div` is a line, a `p` a paragraph, and the
/// element's own style may say otherwise. Markdown knows two spacings, a line
/// break and a blank line, so every block boundary lands on one of them.
struct BlockLayoutTests {

    @Test func setsEachDivOnALineOfItsOwn() {
        #expect(HTMLToMarkdown.convert("<div>Zeile eins</div><div>Zeile zwei</div>") == "Zeile eins\nZeile zwei")
    }

    @Test func separatesParagraphsByABlankLine() {
        #expect(HTMLToMarkdown.convert("<p>Absatz eins</p><p>Absatz zwei</p>") == "Absatz eins\n\nAbsatz zwei")
    }

    @Test func readsAnEmptyLineFromADivHoldingOnlyABreak() {
        let html = "<div>Zeile eins</div><div><br></div><div>Zeile zwei</div>"

        #expect(HTMLToMarkdown.convert(html) == "Zeile eins\n\nZeile zwei")
    }

    /// Gmail and Apple Mail put the first line straight into the outer
    /// element and every further line into a `div` of its own.
    @Test func breaksTheLineBetweenTextAndAFollowingBlock() {
        #expect(HTMLToMarkdown.convert("<div>Hallo Anton,<div>Zeile eins</div></div>") == "Hallo Anton,\nZeile eins")
    }

    @Test func swallowsTheBreakThatEndsABlock() {
        #expect(HTMLToMarkdown.convert("<div>Zeile eins<br></div><div>Zeile zwei</div>") == "Zeile eins\nZeile zwei")
    }

    @Test func turnsTwoBreaksIntoAnEmptyLine() {
        #expect(HTMLToMarkdown.convert("<p>Zeile eins<br><br>Zeile zwei</p>") == "Zeile eins\n\nZeile zwei")
    }

    @Test func readsAParagraphWithoutMarginsAsALine() {
        let html = "<p style=\"margin:0\">Zeile eins</p><p style=\"margin: 0px\">Zeile zwei</p>"

        #expect(HTMLToMarkdown.convert(html) == "Zeile eins\nZeile zwei")
    }

    /// Word sets the paragraph spacing to zero in a stylesheet the emitter
    /// does not read, so an Outlook paragraph is a line unless its own style
    /// gives it space.
    @Test func readsAnOutlookParagraphAsALine() {
        let html = "<p class=\"MsoNormal\">Zeile eins<o:p></o:p></p><p class=\"MsoNormal\">Zeile zwei<o:p></o:p></p>"

        #expect(HTMLToMarkdown.convert(html) == "Zeile eins\nZeile zwei")
    }

    @Test(arguments: ["margin-bottom:12.0pt", "margin:0cm 0cm 12.0pt", "margin:0 0 16px 0"])
    func followsTheMarginAnOutlookParagraphCarries(style: String) {
        let html = "<p class=\"MsoNormal\" style=\"\(style)\">Absatz eins</p><p class=\"MsoNormal\">Absatz zwei</p>"

        #expect(HTMLToMarkdown.convert(html) == "Absatz eins\n\nAbsatz zwei")
    }

    /// React Email zeroes the margin and spaces its paragraphs with padding.
    @Test func countsPaddingAsSpacingToo() {
        let paragraph = "<p style=\"margin:0;padding:0;padding-top:0.5em;padding-bottom:0.5em\">"
        let html = paragraph + "Hi there,</p>" + paragraph + "Version 2026-04 is out.</p>"

        #expect(HTMLToMarkdown.convert(html) == "Hi there,\n\nVersion 2026-04 is out.")
    }

    /// Outlook's empty line is a paragraph holding one `&nbsp;`, a character
    /// a browser does not collapse. A plain space it does collapse.
    @Test func readsANonBreakingSpaceAsAnEmptyLine() {
        let html = """
            <p class="MsoNormal">Zeile eins</p><p class="MsoNormal"><o:p>&nbsp;</o:p></p>\
            <p class="MsoNormal">Zeile zwei</p><div> </div><div>Zeile drei</div>
            """

        #expect(HTMLToMarkdown.convert(html) == "Zeile eins\n\nZeile zwei\nZeile drei")
    }

    /// Without the blank line Markdown would read the next line into the list
    /// or the quote, and a line right above `---` as a heading.
    @Test func surroundsStructuralBlocksWithBlankLines() {
        let html = "<div>Vorher</div><ul><li>Punkt</li></ul><div>Dazwischen</div><blockquote>Zitat</blockquote><div>Danach</div><hr><div>Ende</div>"

        #expect(HTMLToMarkdown.convert(html) == "Vorher\n\n- Punkt\n\nDazwischen\n\n> Zitat\n\nDanach\n\n---\n\nEnde")
    }

    @Test func keepsTheEmptyLinesInsideAQuote() {
        let html = "<blockquote><div>Hallo Jane,</div><div><br></div><div>anbei mein CV.</div></blockquote>"

        #expect(HTMLToMarkdown.convert(html) == "> Hallo Jane,\n>\n> anbei mein CV.")
    }
}

// MARK: -

/// What a browser does not show stays out of the note: above all the preview
/// text a newsletter hides at the top of its body.
struct HiddenElementTests {

    @Test(arguments: [
        "<div style=\"display:none\">Vorschau</div>",
        "<div style=\"DISPLAY : none!important\">Vorschau</div>",
        "<span style=\"visibility:hidden\">Vorschau</span>",
        "<div hidden>Vorschau</div>",
        "<div data-skip-in-text=\"true\">Vorschau</div>",
    ])
    func dropsAnElementTheBrowserHides(hidden: String) {
        #expect(HTMLToMarkdown.convert(hidden + "<p>Inhalt</p>") == "Inhalt")
    }

    /// `mso-hide:all` hides an element from Outlook alone, which shows a twin
    /// out of a conditional comment instead. Every other client shows it, so
    /// dropping it would lose the button, as in the mail behind Q1's first
    /// piece of evidence.
    @Test func keepsAnElementOnlyOutlookHides() {
        let html = """
            <!--[if mso]><a href="https://example.com/angebot">Zum Angebot</a><![endif]-->\
            <a href="https://example.com/angebot" style="mso-hide:all;display:inline-block">Zum Angebot</a>
            """

        #expect(HTMLToMarkdown.convert(html) == "[Zum Angebot](https://example.com/angebot)")
    }
}

// MARK: -

/// `pre` is code, and code keeps every character: its lines, its indentation,
/// its blank lines.
struct PreformattedTextTests {

    @Test func keepsTheLinesIndentationAndBlankLinesOfCode() {
        let html = """
            <pre><code>def greet(name):
                if name:
                    return "Hi " + name


                return "Hi there"</code></pre>
            """
        let expected = """
            ```
            def greet(name):
                if name:
                    return "Hi " + name


                return "Hi there"
            ```
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// The `code` inside the `pre` used to add a pair of its own.
    @Test func writesNoBackticksInsideTheFence() {
        #expect(HTMLToMarkdown.convert("<pre><code>Polar-Version: 2026-04</code></pre>") == "```\nPolar-Version: 2026-04\n```")
    }

    @Test func lengthensTheFenceAroundBackticks() {
        let md = HTMLToMarkdown.convert("<pre>```swift\nlet x = 1\n```</pre>")

        #expect(md == "````\n```swift\nlet x = 1\n```\n````")
    }

    /// A recruiting system wraps whole letters in `pre`, one `div` per line.
    /// That is layout, not code, and a fence would hide the links.
    @Test func readsAPreHoldingBlocksAsALetter() {
        let html = """
            <pre><div>Guten Tag Herr Fillmann,</div><div><br></div><div>danke für das Telefonat.</div>\
            <div><a href="https://example.com/profil">Ihr Profil</a></div></pre>
            """

        #expect(HTMLToMarkdown.convert(html) == "Guten Tag Herr Fillmann,\n\ndanke für das Telefonat.\n[Ihr Profil](https://example.com/profil)")
    }
}

// MARK: -

/// A table is either data, written as a Markdown table, or layout, taken apart
/// into its cells. Data means a row with two filled cells, no table inside it
/// and no `role="presentation"`.
struct TableTests {

    @Test func writesADataTableUnderAnEmptyHeader() {
        let html = """
            <table><tr><td><strong>Buchungsnummer:</strong></td><td>M1234567</td></tr>\
            <tr><td><strong>Einfahrt:</strong></td><td>01.10.2026 um 08:00 Uhr</td></tr></table>
            """
        let expected = """
            |  |  |
            |---|---|
            | **Buchungsnummer:** | M1234567 |
            | **Einfahrt:** | 01.10.2026 um 08:00 Uhr |
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test func takesTheHeaderFromARowOfHeaderCells() {
        let html = "<table><thead><tr><th>Artikel</th><th>Preis</th></tr></thead><tbody><tr><td>Kabel</td><td>5.00</td></tr></tbody></table>"

        #expect(HTMLToMarkdown.convert(html) == "| Artikel | Preis |\n|---|---|\n| Kabel | 5.00 |")
    }

    /// A row whose only cell spans the table captions the rows below it, so
    /// it stands above them and the table is split there.
    @Test func liftsASpanningRowAboveTheTable() {
        let html = """
            <table><tr><th colspan="2">Buchungsdetails</th></tr><tr><td>Parkbereich:</td><td>P8</td></tr>\
            <tr><th colspan="2">Zahlungsdetails</th></tr><tr><td>Gesamtbetrag:</td><td>99,00 €</td></tr></table>
            """
        let expected = """
            **Buchungsdetails**

            |  |  |
            |---|---|
            | Parkbereich: | P8 |

            **Zahlungsdetails**

            |  |  |
            |---|---|
            | Gesamtbetrag: | 99,00 € |
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test func escapesPipesAndKeepsLineBreaksInACell() {
        let html = "<table><tr><td>A|B</td><td>Zeile eins<br>Zeile zwei</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "|  |  |\n|---|---|\n| A\\|B | Zeile eins<br>Zeile zwei |")
    }

    /// Minified HTML has nothing between two cells, so taking a layout table
    /// apart must still keep them apart.
    @Test func takesALayoutTableApartCellByCell() {
        let html = "<table role=\"presentation\"><tr><td>Links</td><td>Rechts</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Links\nRechts")
    }

    /// A logo beside a signature leaves an empty column once the image is
    /// gone, and a table of one column is layout.
    @Test func dropsAColumnThatIsEmptyInEveryRow() {
        let html = "<table><tr><td><img src=\"https://example.com/logo.png\"></td><td>Jane Doe<br>Personalabteilung</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Jane Doe\nPersonalabteilung")
    }

    @Test func takesATableHoldingATableForLayout() {
        let html = "<table><tr><td>Kopf</td><td><table><tr><td>Feld</td><td>Wert</td></tr></table></td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Kopf\n\n|  |  |\n|---|---|\n| Feld | Wert |")
    }
}

// MARK: -

/// One constructed snippet per sender stack, each in the shape the stack
/// really sends and with the whole expected note. Under Q1's option B every
/// one of them runs through the emitter, not only the newsletters.
struct SenderStackTests {

    @Test func gmail() {
        let html = """
            <div dir="ltr">Hallo Anton,<div><br></div><div>danke für die Unterlagen.</div><div>Ich melde mich bis Freitag.</div>\
            <div><br></div><div>Viele Grüsse</div><div>Jane</div></div><br>
            <div class="gmail_quote"><div dir="ltr" class="gmail_attr">Am Mo., 7. Sept. 2026 um 10:00 Uhr schrieb Anton Fillmann \
            &lt;<a href="mailto:anton@example.com">anton@example.com</a>&gt;:<br></div>
            <blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">\
            <div dir="ltr">Hallo Jane,<div><br></div><div>anbei mein CV.</div></div></blockquote></div>
            """
        let expected = """
            Hallo Anton,

            danke für die Unterlagen.
            Ich melde mich bis Freitag.

            Viele Grüsse
            Jane

            Am Mo., 7. Sept. 2026 um 10:00 Uhr schrieb Anton Fillmann <anton@example.com>:

            > Hallo Jane,
            >
            > anbei mein CV.
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test func appleMail() {
        let html = """
            <html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head>\
            <body style="overflow-wrap: break-word; -webkit-nbsp-mode: space; line-break: after-white-space;">\
            Guten Tag Frau Muster,<div><br></div><div>anbei das Formular.</div><div><br></div>\
            <div>Freundliche Grüsse</div><div>Anton Fillmann</div><div><br><blockquote type="cite">\
            <div>Am 07.09.2026 um 09:00 schrieb Jane Muster &lt;jane@example.com&gt;:</div><br class="Apple-interchange-newline">\
            <div><div>Guten Tag Herr Fillmann,</div><div>bitte senden Sie uns das Formular.</div></div></blockquote></div></body></html>
            """
        let expected = """
            Guten Tag Frau Muster,

            anbei das Formular.

            Freundliche Grüsse
            Anton Fillmann

            > Am 07.09.2026 um 09:00 schrieb Jane Muster <jane@example.com>:
            >
            > Guten Tag Herr Fillmann,
            > bitte senden Sie uns das Formular.
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test func outlook() {
        let html = """
            <html xmlns:o="urn:schemas-microsoft-com:office:office"><head><style>p.MsoNormal {margin:0cm; font-size:11.0pt;}</style></head>
            <body lang="DE-CH"><div class="WordSection1">
            <p class="MsoNormal">Hallo Anton<o:p></o:p></p>
            <p class="MsoNormal"><o:p>&nbsp;</o:p></p>
            <p class="MsoNormal">Wir haben Ihr Profil erhalten.<o:p></o:p></p>
            <p class="MsoNormal">Der Termin passt uns.<o:p></o:p></p>
            <p class="MsoNormal"><o:p>&nbsp;</o:p></p>
            <p class="MsoNormal" style="margin-bottom:12.0pt">Freundliche Grüsse<br>Jane Doe<o:p></o:p></p>
            <p class="MsoNormal">Personalabteilung<o:p></o:p></p>
            <p class="MsoNormal"><a href="http://www.example.com/">www.example.com</a><o:p></o:p></p>
            <p class="MsoNormal"><o:p>&nbsp;</o:p></p>
            <div style="border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0cm 0cm 0cm">
            <p class="MsoNormal"><b>Von:</b> Anton Fillmann &lt;anton@example.com&gt;<br><b>Gesendet:</b> Montag, 7. September 2026 09:00<br>\
            <b>An:</b> Jane Doe &lt;jane@example.com&gt;<br><b>Betreff:</b> Bewerbung<o:p></o:p></p>
            </div>
            <p class="MsoNormal"><o:p>&nbsp;</o:p></p>
            <p class="MsoNormal">Guten Tag<o:p></o:p></p>
            </div></body></html>
            """
        let expected = """
            Hallo Anton

            Wir haben Ihr Profil erhalten.
            Der Termin passt uns.

            Freundliche Grüsse
            Jane Doe

            Personalabteilung
            www.example.com

            **Von:** Anton Fillmann <anton@example.com>
            **Gesendet:** Montag, 7. September 2026 09:00
            **An:** Jane Doe <jane@example.com>
            **Betreff:** Bewerbung

            Guten Tag
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// The stack behind Resend: a hidden preview text with its filler, nested
    /// layout tables, padding instead of margins, and a code block.
    @Test func reactEmail() {
        let filler = " \u{200C}\u{200B}\u{200D}\u{200E}\u{200F}\u{FEFF} \u{200C}\u{200B}\u{200D}\u{200E}\u{200F}\u{FEFF}"
        let paragraph = "<p style=\"margin:0;padding:0;padding-top:0.5em;padding-bottom:0.5em\">"
        let html = """
            <!DOCTYPE html><html dir="ltr" lang="en"><head><meta content="text/html; charset=UTF-8" http-equiv="Content-Type"/>\
            <title>Versioning</title></head><body style="background-color:#f4f4f5">\
            <div style="display:none;overflow:hidden;line-height:1px;opacity:0;max-height:0;max-width:0" data-skip-in-text="true">\
            Understand the new API versioning.<div>\(filler)</div></div>
            <table border="0" width="100%" cellPadding="0" cellSpacing="0" role="presentation" align="center"><tbody><tr>\
            <td style="padding-top:24px;padding-bottom:24px">
            <table align="center" width="100%" border="0" cellPadding="0" cellSpacing="0" role="presentation"><tbody>\
            <tr style="width:100%"><td><img alt="Logo" src="https://example.com/logo.png" width="10%"/></td></tr></tbody></table>
            <h1 style="margin:0;padding:0;padding-top:0.389em">Introducing API versioning</h1>
            \(paragraph)Hi <!-- -->there<!-- -->,</p>
            \(paragraph)Version <strong>2026-04</strong> becomes the default.</p>
            <ul style="margin:0;padding:0"><li style="margin:0"><p style="margin:0;padding:0"><strong>Current</strong> is the stable default.</p></li>\
            <li style="margin:0"><p style="margin:0;padding:0"><strong>Next</strong> is in development.</p></li></ul>
            <pre style="padding:16px"><code><span>curl -i https://api.example.com/v1/products/ \\</span>
            <span>  -H &quot;Polar-Version: 2026-04&quot;</span></code></pre>
            \(paragraph)Read the <a href="https://example.com/docs" style="color:#0670DB">versioning docs</a>.</p>
            </td></tr></tbody></table></body></html>
            """
        let expected = """
            # Introducing API versioning

            Hi there,

            Version **2026-04** becomes the default.

            - **Current** is the stable default.
            - **Next** is in development.

            ```
            curl -i https://api.example.com/v1/products/ \\
              -H "Polar-Version: 2026-04"
            ```

            Read the [versioning docs](https://example.com/docs).
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// The shape of the parking confirmation from 2026-09-01: a data table
    /// inside two layout tables, minified, its sections captioned by rows
    /// that span both columns.
    @Test func dataTableInsideALayoutTable() {
        let html = """
            <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
            <table width="600" cellpadding="0" cellspacing="0"><tr><td>
            <p>Vielen Dank für Ihre Buchung.</p>
            <table class="details"><tr><th colspan="2">Buchungsdetails</th></tr>\
            <tr><td><strong>Buchungsnummer:</strong></td><td>M1234567</td></tr>\
            <tr><td><strong>Einfahrt:</strong></td><td>01.10.2026 um 08:00 Uhr</td></tr>\
            <tr><th colspan="2">Zahlungsdetails</th></tr>\
            <tr><td><strong>Gesamtbetrag:</strong></td><td>99,00 €</td></tr></table>
            <p>Gute Reise!</p>
            </td></tr></table>
            </td></tr></table>
            """
        let expected = """
            Vielen Dank für Ihre Buchung.

            **Buchungsdetails**

            |  |  |
            |---|---|
            | **Buchungsnummer:** | M1234567 |
            | **Einfahrt:** | 01.10.2026 um 08:00 Uhr |

            **Zahlungsdetails**

            |  |  |
            |---|---|
            | **Gesamtbetrag:** | 99,00 € |

            Gute Reise!
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }
}
