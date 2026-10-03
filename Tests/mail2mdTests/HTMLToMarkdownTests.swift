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

    /// A chatbot transcript writes an emoji beyond the first 65536 characters
    /// as the two UTF-16 halves of it, each a reference of its own. Read one by
    /// one, each half is U+FFFD, and the note showed `��` where the plain form
    /// of the same mail has the emoji.
    @Test(arguments: [
        ("<p>Ich bin der Chatbot &#55358;&#56598; der Post.</p>", "Ich bin der Chatbot 🤖 der Post."),
        ("<p>Live-Chat &#xD83D;&#xDCAC;</p>", "Live-Chat 💬"),
        ("<p>&#55358;&#55358;&#56598;</p>", "\u{FFFD}🤖"),
    ])
    func joinsAnEmojiWrittenAsItsTwoHalves(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A half without its partner says nothing, so it stays what the HTML
    /// standard makes of it, also beside a reference to an ordinary character.
    @Test func leavesALoneHalfAsTheReplacementCharacter() {
        #expect(HTMLToMarkdown.convert("<p>A &#55358; B &#56598;&#65; C &#65;&#56598;</p>") == "A \u{FFFD} B \u{FFFD}A C A\u{FFFD}")
    }

    /// Foundation's whitespace set holds the zero-width space, so trimming a
    /// line with it would remove one at the edge before the invisible-character
    /// rule can count it. The emitter trims spaces and nothing else.
    @Test func leavesAZeroWidthSpaceAtTheEdgeOfALine() {
        let html = "<div>\u{200B}Zeile eins\u{200B}</div><div>\u{200B}Zeile zwei\u{200B}</div>"

        #expect(HTMLToMarkdown.convert(html) == "\u{200B}Zeile eins\u{200B}\n\u{200B}Zeile zwei\u{200B}")
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

    /// Outlook sends an emoji typed into a message as a picture of it, with
    /// the emoji as its alt text; the plain form has `[??]` in its place.
    @Test func writesAPictureOfAnEmojiAsTheEmoji() {
        let html = "<p>Wir sehen uns bestimmt wieder <img alt=\"😉\" src=\"cid:image002.png@01D91522\"></p>"

        #expect(HTMLToMarkdown.convert(html) == "Wir sehen uns bestimmt wieder 😉")
    }

    @Test func dropsAPictureWhoseAltTextIsWords() {
        let html = "<p>Freundliche Grüsse <img alt=\"Firmenlogo\" src=\"https://example.com/logo.png\"></p>"

        #expect(HTMLToMarkdown.convert(html) == "Freundliche Grüsse")
    }

    /// A link around blocks that hold links of their own, the preview of a
    /// repository or a job card, is taken apart and its inner links stay:
    /// Markdown cannot nest links, and the `[[` it wrote opens a wikilink in
    /// Obsidian.
    @Test func takesALinkAroundLinksApart() {
        let html = """
            <a href="https://example.com/repo"><table><tr><td>\
            <a href="https://example.com/repo">example/repo</a> <a href="https://example.com/repo">example.com</a>\
            </td></tr></table></a>
            """

        #expect(HTMLToMarkdown.convert(html) == "[example/repo](https://example.com/repo) [example.com](https://example.com/repo)")
    }

    /// Only a link a reader can follow takes the outer one apart: an anchor
    /// without a target, or a link the browser hides, leaves it whole.
    @Test(arguments: [
        "<a name=\"karte\"></a>Zur Karte",
        "Zur Karte<a href=\"https://example.com/versteckt\" style=\"display:none\">versteckt</a>",
    ])
    func keepsALinkWhoseInnerAnchorsLeadNowhere(cell: String) {
        let html = "<a href=\"https://example.com/karte\"><table><tr><td>\(cell)</td></tr></table></a>"

        #expect(HTMLToMarkdown.convert(html) == "[Zur Karte](https://example.com/karte)")
    }

    /// A bracket in a link's text would end it early, and the pair UPS puts
    /// around its language links wrote `[[German]](#German)`, a wikilink in
    /// Obsidian. Inside code a backslash would show, so code keeps its brackets.
    @Test(arguments: [
        ("<a href=\"#German\">[German]</a>", "[\\[German\\]](#German)"),
        ("<a href=\"https://example.com/docs\"><code>list[0]</code> erklärt</a>", "[`list[0]` erklärt](https://example.com/docs)"),
    ])
    func escapesTheBracketsInALinksText(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }
}

// MARK: -

/// How a browser stacks blocks: a `div` is a line, a `p` a paragraph, and the
/// element's own style may say otherwise, down to an inline element it makes a
/// block or gives room at its sides. Markdown knows two spacings, a line break
/// and a blank line, so every block boundary lands on one of them.
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

    /// Markdown shows one empty line however many stand in a row. In a quote
    /// the cleaner cannot fold them afterwards, because a `>` line is not empty.
    @Test func foldsThreeBreaksIntoOneEmptyLine() {
        #expect(HTMLToMarkdown.convert("<p>Zeile eins<br><br><br>Zeile zwei</p>") == "Zeile eins\n\nZeile zwei")
        #expect(HTMLToMarkdown.convert("<blockquote>Zeile eins<br><br><br>Zeile zwei</blockquote>") == "> Zeile eins\n>\n> Zeile zwei")
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

    /// Padding leaves its space on its own side only: a paragraph padded above
    /// is a line toward the block below it, one padded below a line toward the
    /// block above.
    @Test func leavesSpaceOnlyOnTheSideThePaddingIsOn() {
        let html = """
            <div>Zeile eins</div><p style="margin:0;padding-top:0.5em">Oben gesperrt</p><div>Zeile zwei</div>\
            <p style="margin:0;padding-bottom:0.5em">Unten gesperrt</p><div>Zeile drei</div>
            """

        #expect(HTMLToMarkdown.convert(html) == "Zeile eins\n\nOben gesperrt\nZeile zwei\nUnten gesperrt\n\nZeile drei")
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

    /// A classifieds site sets the links of its footer one below the other
    /// with `display:block`, and nothing else stands between them.
    @Test func setsAnInlineElementItsStyleMakesABlockOnLinesOfItsOwn() {
        let link = "style=\"display: block!important; padding: 12px 0px!important;\""
        let html = """
            <div><a href="https://example.com/agb" \(link)>Nutzungsbedingungen</a>\
            <a href="https://example.com/datenschutz" \(link)>Datenschutz</a></div>
            """

        #expect(HTMLToMarkdown.convert(html) == "[Nutzungsbedingungen](https://example.com/agb)\n\n[Datenschutz](https://example.com/datenschutz)")
    }

    /// Wix keeps the links of its footer apart by padding at their sides, and
    /// nothing else stands between them either. Room at one side is enough,
    /// whether it stands after the first link or before the second.
    @Test(arguments: [
        ("border-right:1px solid #2D2D2D;padding:0 8px", "padding:0 8px"),
        ("", "padding-left:8px"),
        ("margin-right:8px", ""),
        ("", "margin:0 0 0 8px"),
    ])
    func keepsInlineElementsWithRoomAtTheirSidesApart(first: String, second: String) {
        let html = """
            <p><a href="https://example.com/hilfe"><span style="\(first)">Hilfe-Center</span></a>\
            <a href="https://example.com/datenschutz"><span style="\(second)">Datenschutz</span></a></p>
            """

        #expect(HTMLToMarkdown.convert(html) == "[Hilfe-Center](https://example.com/hilfe) [Datenschutz](https://example.com/datenschutz)")
    }

    /// A sender split an address over two links, and a browser shows it as
    /// one word. Without room between them, they stay together.
    @Test func leavesTwoLinksWithoutRoomBetweenThemTogether() {
        let html = "<p><a href=\"https://www.example.ch/\">www.example.c</a><a href=\"https://www.example.com\">om</a></p>"

        #expect(HTMLToMarkdown.convert(html) == "[www.example.c](https://www.example.ch/)[om](https://www.example.com)")
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
/// into its cells. Data means two rows or more, one of them with two filled
/// cells, no table inside it and no `role="presentation"`. The cells of a
/// layout row share a line where each but the last holds one.
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
        let html = "<table><tr><td>A|B</td><td>Zeile eins<br>Zeile zwei</td></tr><tr><td>C</td><td>D</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "|  |  |\n|---|---|\n| A\\|B | Zeile eins<br>Zeile zwei |\n| C | D |")
    }

    /// A table of a single row compares nothing, so it is layout, as in
    /// Mozilla's Readability: a letter beside its menu, a bar of links.
    @Test func takesATableOfASingleRowForLayout() {
        let html = """
            <table><tr><td><a href="https://example.com/bestellung">Ihre Bestellung</a><br><a href="https://example.com/kontakt">Kontakt</a></td>\
            <td><strong>Sehr geehrter Herr Fillmann,</strong><br>Ihr Antrag ist eingegangen.</td></tr></table>
            """
        let expected = """
            [Ihre Bestellung](https://example.com/bestellung)
            [Kontakt](https://example.com/kontakt)
            **Sehr geehrter Herr Fillmann,**
            Ihr Antrag ist eingegangen.
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A row that spans the table captions it and holds no data, so a caption
    /// above a single row leaves nothing to compare either.
    @Test func takesACaptionAboveASingleRowForLayout() {
        let html = """
            <table><tr><td colspan="2"><strong>Rechnung an:</strong></td></tr>\
            <tr><td>Anton Fillmann<br>8000 Zürich</td><td><strong>Bestellnummer:</strong> M1234567</td></tr></table>
            """

        #expect(HTMLToMarkdown.convert(html) == "**Rechnung an:**\nAnton Fillmann\n8000 Zürich\n**Bestellnummer:** M1234567")
    }

    /// A grid spaces its columns with an empty one. In a table of data that
    /// column drops out, whether its cells are empty or hold a no-break space.
    @Test func dropsAColumnThatIsEmptyInEveryRow() {
        let html = """
            <table><tr><td>Buchungsnummer:</td><td width="16">&nbsp;</td><td>M1234567</td></tr>\
            <tr><td>Einfahrt:</td><td width="16"></td><td>01.10.2026 um 08:00 Uhr</td></tr></table>
            """
        let expected = """
            |  |  |
            |---|---|
            | Buchungsnummer: | M1234567 |
            | Einfahrt: | 01.10.2026 um 08:00 Uhr |
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// Minified HTML has nothing between two cells, so taking a layout table
    /// apart must still keep them apart.
    @Test func takesALayoutTableApartCellByCell() {
        let html = "<table role=\"presentation\"><tr><td>Links<br>oben</td><td>Rechts</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Links\noben\nRechts")
    }

    /// A browser shows the cells of a layout row side by side, so where each
    /// holds one line, they share one: a bullet beside its text.
    @Test func setsTheCellsOfALayoutRowOnOneLine() {
        let bullet = "<td width=\"16\"><p style=\"padding:0;Margin:0\">&bull;</p></td>"
        let html = """
            <table role="presentation"><tr>\(bullet)<td><p style="padding:0;Margin:0">Lebenslauf</p></td></tr>\
            <tr><td colspan="2">&nbsp;</td></tr><tr>\(bullet)<td><p style="padding:0;Margin:0">Anschreiben</p></td></tr></table>
            """

        #expect(HTMLToMarkdown.convert(html) == "• Lebenslauf\n\n• Anschreiben")
    }

    /// The last cell may run on below the shared line: a step's number beside
    /// a text of two lines, which stands in a layout table of its own.
    @Test func continuesTheLastCellBelowTheSharedLine() {
        let html = """
            <table><tr><td valign="top">2</td><td><table><tr><td><img alt="" src="https://example.com/schritt-2.png"></td></tr>\
            <tr><td colspan="2">QR-Code an den Scanner halten.<br>Schranke öffnet sich.</td></tr></table></td></tr></table>
            """

        #expect(HTMLToMarkdown.convert(html) == "2 QR-Code an den Scanner halten.\nSchranke öffnet sich.")
    }

    /// A block Markdown marks, a list, a heading or a table, cannot share a
    /// line, so a row with one in a cell keeps its cells apart.
    @Test(arguments: [
        ("<td>Termine</td><td><ul><li>Montag</li><li>Dienstag</li></ul></td>", "Termine\n\n- Montag\n- Dienstag"),
        ("<td><h3>Termine</h3></td><td>Montag</td>", "### Termine\n\nMontag"),
    ])
    func keepsTheCellsApartAroundABlockMarkdownMarks(cells: String, expected: String) {
        #expect(HTMLToMarkdown.convert("<table role=\"presentation\"><tr>\(cells)</tr></table>") == expected)
    }

    /// The space a browser leaves around the cells stays around their shared
    /// line.
    @Test func keepsTheSpaceItsCellsLeaveAroundASharedLine() {
        let cell = "<td style=\"padding:12px 0\">"
        let html = "<div>Davor</div><table role=\"presentation\"><tr>\(cell)&bull;</td>\(cell)Lebenslauf</td></tr></table><div>Danach</div>"

        #expect(HTMLToMarkdown.convert(html) == "Davor\n\n• Lebenslauf\n\nDanach")
    }

    /// A browser sets a header cell in bold, also where its table is layout,
    /// as the dark bar above the details of the parking confirmation.
    @Test func setsAHeaderCellOutsideATableOfDataInBold() {
        let html = "<table><tr><th align=\"left\" style=\"padding: 8px 15px 4px; font-size: 16px;\">Buchungsdetails</th></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "**Buchungsdetails**")
    }

    /// Not where its style sets a normal weight, and not where it holds
    /// blocks: an email framework lays out whole columns in header cells and
    /// sets their weight back in a stylesheet the emitter does not read.
    @Test(arguments: [
        ("<table><tr><th style=\"font-weight: normal;\">Spalte</th></tr></table>", "Spalte"),
        ("<table><tr><th><div>Zeile eins</div><div>Zeile zwei</div></th></tr></table>", "Zeile eins\nZeile zwei"),
    ])
    func leavesAHeaderCellItsWeight(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A logo beside a signature leaves an empty column once the image is
    /// gone, and a table of one column is layout.
    @Test func takesALogoBesideASignatureForLayout() {
        let html = "<table><tr><td><img src=\"https://example.com/logo.png\"></td><td>Jane Doe<br>Personalabteilung</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Jane Doe\nPersonalabteilung")
    }

    @Test func takesATableHoldingATableForLayout() {
        let inner = "<table><tr><td>Feld</td><td>Wert</td></tr><tr><td>Feld 2</td><td>Wert 2</td></tr></table>"
        let html = "<table><tr><td>Kopf</td><td>\(inner)</td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "Kopf\n\n|  |  |\n|---|---|\n| Feld | Wert |\n| Feld 2 | Wert 2 |")
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

    /// The shape of the parking confirmation from 2026-09-01, measured on its
    /// `.eml` on 2026-10-03: data tables inside two layout tables, minified,
    /// each captioned by a header cell in a table of its own; numbered steps,
    /// the number in one cell and pictures and text in a table in the next;
    /// and a bar of links in a table of a single row.
    @Test func dataTableInsideALayoutTable() {
        let caption = "<table class=\"row\"><tr><th align=\"left\" style=\"padding: 8px 15px 4px; font-size: 16px;\">"
        let step = "<table><tr><td valign=\"top\">"
        let html = """
            <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
            <table width="600" cellpadding="0" cellspacing="0"><tr><td>
            <p>Vielen Dank für Ihre Buchung.</p>
            \(caption)Buchungsdetails</th></tr></table>\
            <table class="details"><tr><td><strong>Buchungsnummer:</strong></td><td>M1234567</td></tr>\
            <tr><td><strong>Einfahrt:</strong></td><td>01.10.2026 um 08:00 Uhr</td></tr></table>
            \(caption)Zahlungsdetails</th></tr></table>\
            <table class="details"><tr><td><strong>Zahlungsmittel:</strong></td><td>ApplePay</td></tr>\
            <tr><td><strong>Gesamtbetrag:</strong></td><td>99,00 €</td></tr></table>
            <p><b>So funktioniert der Parkvorgang:</b></p>
            \(step)1</td><td><table><tr><td><img alt="" src="https://example.com/schritt-1.png"></td></tr>\
            <tr><td colspan="2">Buchungsbestätigung ausdrucken oder auf dem Handy speichern.</td></tr></table></td></tr></table>
            \(step)2</td><td><table><tr><td><img alt="" src="https://example.com/schritt-2.png"></td></tr>\
            <tr><td colspan="2">QR-Code an den Scanner der Einfahrtssäule halten.<br>Schranke öffnet sich.</td></tr></table></td></tr></table>
            <p>Gute Reise!</p>
            <table><tr><td><a href="https://example.com/restaurants">Restaurants</a></td><td><a href="https://example.com/shops">Shops</a></td></tr></table>
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
            | **Zahlungsmittel:** | ApplePay |
            | **Gesamtbetrag:** | 99,00 € |

            **So funktioniert der Parkvorgang:**

            1 Buchungsbestätigung ausdrucken oder auf dem Handy speichern.
            2 QR-Code an den Scanner der Einfahrtssäule halten.
            Schranke öffnet sich.

            Gute Reise!

            [Restaurants](https://example.com/restaurants) [Shops](https://example.com/shops)
            """

        #expect(HTMLToMarkdown.convert(html) == expected)
    }
}
