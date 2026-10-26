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
        ("<a href=\"http://www.example.com/\"><span style=\"font-weight:bold\">www.example.com</span></a>", "**www.example.com**"),
        ("<a href=\"http://www.example.com/\"><b>www.example.com</b></a>", "**www.example.com**"),
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

    /// A target Markdown would not read as one stands in pointy brackets: one
    /// with a space, which ends a link, as in the map links and footers of a
    /// parcel service (102 targets in 6 of 648 archive mails, 2026-10-26), one
    /// with a parenthesis without its partner, or one that opens with `<`.
    /// A tab or a line break in a target the browser takes out, and so does
    /// the emitter.
    @Test(arguments: [
        ("<a href=\"https://example.com/maps?query=MUSTERSTRASSE 1+8000+ZUERICH\">Karte</a>", "[Karte](<https://example.com/maps?query=MUSTERSTRASSE 1+8000+ZUERICH>)"),
        ("<a href=\"mailto: service@example.com?subject=Mein Abo\">Abo</a>", "[Abo](<mailto: service@example.com?subject=Mein Abo>)"),
        ("<a href=\"https://example.com/a_(b\">Wiki</a>", "[Wiki](<https://example.com/a_(b>)"),
        ("<a href=\"https://example.com/a <b>\">Spitz</a>", "[Spitz](<https://example.com/a \\<b\\>>)"),
        ("<a href=\"https://example.com/lang\n\t/weg\">Umbruch</a>", "[Umbruch](https://example.com/lang/weg)"),
        ("<a href=\"https://example.com/a_(b)\">Wiki</a>", "[Wiki](https://example.com/a_(b))"),
    ])
    func writesATargetMarkdownReadsAsOne(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }
}

// MARK: -

/// Emphasis as Markdown writes it: between markers, which only work at the
/// edge of a word. Two spans of one kind that meet are one span to a reader,
/// but written one after the other, `**Software-****Entwicklung**`, their
/// markers run into four asterisks that Markdown leaves standing as text.
struct EmphasisTests {

    /// Outlook sets every run of formatting in an element of its own, so a
    /// bold line can arrive as two `b`, split wherever the formatting inside
    /// it changed: after a hyphen, before a colon.
    @Test(arguments: [
        ("<b><span>Kurs für Software-</span></b><b><span>Entwicklung</span></b>", "**Kurs für Software-Entwicklung**"),
        ("<b>Workshop am Montag</b><b>:</b>", "**Workshop am Montag:**"),
        ("<span><b>Teil eins</b></span><span><b>, Teil zwei</b></span>", "**Teil eins, Teil zwei**"),
        ("<strong>Fett</strong><b>druck</b>", "**Fettdruck**"),
        ("<b><a href=\"https://example.com\">Anmeldung</a></b><b>:</b>", "**[Anmeldung](https://example.com):**"),
    ])
    func joinsBoldSpansThatMeet(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A job board sets a note in italics, its first word in bold as well,
    /// each piece in a span of its own.
    @Test func joinsItalicSpansThatMeet() {
        let html = "<span><em><strong>Wichtig</strong></em></span><span><em>: bitte bis Freitag antworten.</em></span>"

        #expect(HTMLToMarkdown.convert(html) == "***Wichtig**: bitte bis Freitag antworten.*")
    }

    /// Only spans whose markers would touch are joined. A space between them
    /// keeps both readable, and so do a change of kind and a new line.
    @Test(arguments: [
        ("<b>Eins</b> <b>Zwei</b>", "**Eins** **Zwei**"),
        ("<b>Eins </b><b>Zwei</b>", "**Eins** **Zwei**"),
        ("<b>Fett</b><i>kursiv</i>", "**Fett***kursiv*"),
        ("<div><b>Eins</b></div><div><b>Zwei</b></div>", "**Eins**\n**Zwei**"),
    ])
    func keepsSpansWhoseMarkersDoNotTouchApart(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A span over two lines is set line by line, and only its last line
    /// meets the span after it.
    @Test func joinsTheLastLineOfASpanWithTheSpanAfterIt() {
        let html = "<b>Zeile eins<br>Zeile zwei</b><b>, Fortsetzung</b>"

        #expect(HTMLToMarkdown.convert(html) == "**Zeile eins**\n**Zeile zwei, Fortsetzung**")
    }

    /// Emphasis inside emphasis of its own kind adds nothing a reader sees.
    /// Its markers would only stand doubled, and beside a span that follows
    /// they would leave a run that Markdown cannot pair.
    @Test(arguments: [
        ("<b>Alle <strong>Termine</strong> im Überblick</b>", "**Alle Termine im Überblick**"),
        ("<i>sehr <em>wichtig</em></i>", "*sehr wichtig*"),
        ("<strong><b>Doppelt</b></strong><b>:</b>", "**Doppelt:**"),
    ])
    func setsNoMarkersInsideEmphasisOfItsOwnKind(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A row of a layout table whose cells cannot share a line is replayed
    /// into the note, and the replay joins two spans as laying them out in
    /// place does.
    @Test func joinsSpansThatMeetInAReplayedCell() {
        let html = "<table><tr><td><ul><li>Punkt</li></ul></td><td><b>Fett</b><b>druck</b></td></tr></table>"

        #expect(HTMLToMarkdown.convert(html) == "- Punkt\n\n**Fettdruck**")
    }

    /// An email framework sets a name or an amount in bold through the style
    /// of a `div` or a `span` rather than with `b`, and a browser shows it
    /// bold all the same: from a weight of 600 up, and `bold` and `bolder`.
    @Test(arguments: [
        ("<div style=\"font-size:16px;font-weight:bold;color:#333333\">Jane Doe</div><div>Zeile</div>", "**Jane Doe**\nZeile"),
        ("<div><span>Prämie pro Monat CHF</span> <span style=\"font-size:28px;font-weight:bold\"> 329.35</span></div>", "Prämie pro Monat CHF **329.35**"),
        ("<a href=\"https://example.com\" style=\"color:#ffffff;font-weight:700\">Startseite</a>", "**[Startseite](https://example.com)**"),
        ("<span style=\"font-weight: bolder\">Hinweis</span>", "**Hinweis**"),
        ("<span style=\"font-weight:600!important\">Hinweis</span>", "**Hinweis**"),
        ("<b style=\"font-weight:inherit\">Hinweis</b>", "**Hinweis**"),
    ])
    func boldsWhatItsStyleSetsBold(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A weight below 600 shows no bold, also where the style sets it on a
    /// `b`: the style wins over the tag, as in a browser.
    @Test(arguments: [
        "<span style=\"font-weight:599\">mager</span>",
        "<span style=\"font-weight:normal\">mager</span>",
        "<span style=\"font-weight:lighter\">mager</span>",
        "<b style=\"font-weight:400\">mager</b>",
        "<strong style=\"font-weight: normal\">mager</strong>",
    ])
    func leavesALighterWeightPlain(html: String) {
        #expect(HTMLToMarkdown.convert(html) == "mager")
    }

    /// The same for italics: a style that slants the text, and one that sets
    /// an `i` upright.
    @Test(arguments: [
        ("<p style=\"margin-top: 0px; margin-bottom: 12px; font-style: italic;\">Alternativ mit dem Code abrufen.</p>", "*Alternativ mit dem Code abrufen.*"),
        ("<span style=\"font-style:oblique 10deg\">schräg</span>", "*schräg*"),
        ("<i style=\"font-style:normal\">gerade</i>", "gerade"),
        ("<span style=\"font-weight:bold;font-style:italic\">beides</span>", "***beides***"),
    ])
    func italicizesWhatItsStyleSetsItalic(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// Bold from a style meets bold from a tag as two `b` meet.
    @Test func joinsBoldFromAStyleWithBoldFromATag() {
        let html = "<b>Umwelt</b><span style=\"font-weight:bold\">abgabe</span>"

        #expect(HTMLToMarkdown.convert(html) == "**Umweltabgabe**")
    }

    /// Emphasis from a style counts as emphasis around the elements inside
    /// it, and the other way round.
    @Test(arguments: [
        ("<div style=\"font-weight:bold\">Alle <b>Termine</b> im Überblick</div>", "**Alle Termine im Überblick**"),
        ("<b>Alle <span style=\"font-weight:700\">Termine</span> im Überblick</b>", "**Alle Termine im Überblick**"),
        ("<p style=\"font-style:italic\">Ganz <i>schräg</i></p>", "*Ganz schräg*"),
    ])
    func setsNoMarkersInsideStyledEmphasisOfItsOwnKind(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// Markers around each line of a list or a heading would break it, so
    /// emphasis around one sets none.
    @Test(arguments: [
        ("<div style=\"font-weight:bold\"><ul><li>Punkt</li></ul></div>", "- Punkt"),
        ("<b><ul><li>Punkt</li></ul></b>", "- Punkt"),
        ("<h2 style=\"font-weight:bold\">Titel</h2>", "## Titel"),
    ])
    func setsNoMarkersAroundABlockMarkdownMarks(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    /// A header cell is bold of itself, so a style that sets it bold adds no
    /// second pair of markers; a heading lays its text out on its own, so
    /// emphasis inside it keeps its markers, as before.
    @Test(arguments: [
        ("<table><tr><th style=\"font-weight:bold\">Buchungsdetails</th></tr></table>", "**Buchungsdetails**"),
        ("<h2 style=\"font-weight:bold\">Alle <b>Termine</b></h2>", "## Alle **Termine**"),
    ])
    func leavesTheBoldOfHeadersAndHeadingsAsItWas(html: String, expected: String) {
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

    /// MJML spaces its sections with an empty `div` of a set height holding
    /// a hair space, table layouts with an empty cell or row of a set height,
    /// and a browser shows the space.
    @Test(arguments: [
        "<div style=\"height:20px;line-height:20px;\">&#8202;</div>",
        "<table role=\"presentation\"><tr><td height=\"20\"></td></tr></table>",
        "<table role=\"presentation\"><tr height=\"16\"><td></td></tr></table>",
        "<div style=\"height:1em\"><div></div></div>",
    ])
    func readsAnEmptyBlockOfAHeightAsABlankLine(spacer: String) {
        #expect(HTMLToMarkdown.convert("<div>Eins</div>\(spacer)<div>Zwei</div>") == "Eins\n\nZwei")
    }

    /// Below 3pt a reader sees a hairline, not a gap; a block holding text or
    /// a picture is no spacer, and neither is an inline element.
    @Test(arguments: [
        "<div style=\"height:2px\"></div>",
        "<div style=\"line-height:20px\"></div>",
        "<div style=\"height:auto\"></div>",
        "<div style=\"height:40px\">Mitte</div>",
        "<table role=\"presentation\"><tr><td height=\"60\"><img src=\"https://example.com/logo.png\"></td></tr></table>",
        "<table role=\"presentation\"><tr><td height=\"60\"><a href=\"https://example.com\"><img src=\"https://example.com/logo.png\"></a></td></tr></table>",
        "<span style=\"height:20px\"></span>",
    ])
    func leavesOtherBlocksOfAHeightWithoutSpace(element: String) {
        let expected = element.contains("Mitte") ? "Eins\nMitte\nZwei" : "Eins\nZwei"

        #expect(HTMLToMarkdown.convert("<div>Eins</div>\(element)<div>Zwei</div>") == expected)
    }

    /// A list its style shows without bullets is a stack of lines to a
    /// reader, spaced as its style spaces it.
    @Test(arguments: ["list-style:none", "list-style-type: none", "list-style: none outside"])
    func readsAListWithoutMarkersAsLines(style: String) {
        let html = """
            <div>Hausarztmodell</div><ul style="padding:0;margin:0;\(style)">\
            <li><span>Franchise: CHF 300.–</span></li><li><span>Unfalldeckung: Nein</span></li></ul><div>Danach</div>
            """

        #expect(HTMLToMarkdown.convert(html) == "Hausarztmodell\nFranchise: CHF 300.–\nUnfalldeckung: Nein\nDanach")
    }

    /// Without a margin of its own, such a list has the browser's, a line
    /// above and below, and an ordered one loses its numbers as well.
    @Test func spacesAListWithoutMarkersAsABrowserDoes() {
        let html = "<div>Vorher</div><ol style=\"list-style-type:none\"><li>Eins</li><li>Zwei</li></ol><div>Danach</div>"

        #expect(HTMLToMarkdown.convert(html) == "Vorher\n\nEins\nZwei\n\nDanach")
    }

    /// `none` in the shorthand is the bullet's picture where a type stands
    /// beside it, and the bullet stays.
    @Test(arguments: ["list-style: square none", "list-style-type: disc"])
    func keepsTheMarkersOfAListThatShowsThem(style: String) {
        let html = "<ul style=\"\(style)\"><li>Eins</li><li>Zwei</li></ul>"

        #expect(HTMLToMarkdown.convert(html) == "- Eins\n- Zwei")
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

    /// A cell of data whose style sets it bold, the total of a receipt.
    @Test func boldsACellOfDataItsStyleSetsBold() {
        let html = """
            <table><tr><td>Kabel</td><td>5.00</td></tr>\
            <tr><td style="font-weight:bold">Total</td><td style="font-weight:bold">5.00</td></tr></table>
            """

        #expect(HTMLToMarkdown.convert(html) == "|  |  |\n|---|---|\n| Kabel | 5.00 |\n| **Total** | **5.00** |")
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

/// Pictures from a part of the mail, addressed by `cid:`. Each one shown is
/// noted with the size the HTML gives it, so the run can name what the note
/// leaves out, and given the file it was written to, it is embedded in its
/// place. A picture from the web is neither.
struct PictureTests {

    static let screenshot = "<img width=\"474\" height=\"464\" style=\"width:4.9375in;height:4.8333in\" src=\"cid:image001.png@01DC1234\">"

    @Test func notesAPictureFromTheMailAndLeavesItOut() {
        let converted = HTMLToMarkdown.convert("<p>Hier der Ausschnitt:</p><p>\(Self.screenshot)</p>", imageNames: [:])

        #expect(converted.markdown == "Hier der Ausschnitt:")
        #expect(converted.images == [InlineImage(contentID: "image001.png@01DC1234", width: 474, height: 464)])
    }

    /// A browser lets the inline style win over the attributes, and leaves a
    /// side open that is a share of the page or `auto`.
    @Test(arguments: [
        ("width=\"474\" height=\"464\"", 474, 464),
        ("width=\"600\" height=\"400\" style=\"width:4.9375in;height:4.8333in\"", 474, 464),
        ("style=\"width:120px\" height=\"30\"", 120, 30),
        ("width=\"100%\" height=\"40\" style=\"height:auto\"", nil, nil),
        ("", nil, nil),
    ] as [(String, Int?, Int?)])
    func notesTheSizeTheHTMLGivesAPicture(attributes: String, width: Int?, height: Int?) {
        let converted = HTMLToMarkdown.convert("<img \(attributes) src=\"cid:logo@example.com\">", imageNames: [:])

        #expect(converted.images == [InlineImage(contentID: "logo@example.com", width: width, height: height)])
    }

    /// Only a picture the mail carries is its own: one from the web is no part
    /// of it, a hidden one is not shown, and a picture of an emoji is written
    /// as the emoji, also when its file is there.
    @Test(arguments: [
        "<img src=\"https://example.com/logo.png\">",
        "<div style=\"display:none\"><img src=\"cid:pixel@example.com\"></div>",
        "<p>Bis bald <img alt=\"😉\" src=\"cid:image002.png@01D9\"></p>",
    ])
    func notesNoOtherPicture(html: String) {
        let converted = HTMLToMarkdown.convert(html, imageNames: ["pixel@example.com": "pixel.png", "image002.png@01D9": "image002.png"])

        #expect(converted.images.isEmpty)
        #expect(converted.markdown.contains("![[") == false)
    }

    /// Given the file a picture was written to, it is embedded where the `img`
    /// stood, in Outlook's paragraphs on a line of its own.
    @Test func embedsAPictureWhereItStood() {
        let html = """
            <p class=MsoNormal>Hier der Ausschnitt:<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p>\
            <p class=MsoNormal>\(Self.screenshot)<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p><p class=MsoNormal>Gruss<o:p></o:p></p>
            """
        let converted = HTMLToMarkdown.convert(html, imageNames: ["image001.png@01DC1234": "2026.09.07 10.00 ENCL image001.png"])

        #expect(converted.markdown == "Hier der Ausschnitt:\n\n![[2026.09.07 10.00 ENCL image001.png]]\n\nGruss")
        #expect(converted.images.map { $0.contentID } == ["image001.png@01DC1234"])
    }

    /// The alt text becomes the embed's alias where it says something about
    /// the picture (Anton's decision 1a, 2026-10-03), on one line: Outlook sent
    /// a text box as a picture, its text in the alt.
    @Test func aliasesAnEmbedWithAnAltTextThatSaysSomething() {
        let html = "<img alt=\"Terminsache!\nBitte bis Freitag einreichen.\" src=\"cid:image008.png@01D2\">"
        let converted = HTMLToMarkdown.convert(html, imageNames: ["image008.png@01D2": "image008.png"])

        #expect(converted.markdown == "![[image008.png|Terminsache! Bitte bis Freitag einreichen.]]")
    }

    /// An alt text says nothing when it is empty or a file name, and nothing of
    /// the sender's when Office described the picture itself, in German or in
    /// English, old or new. A number would set the picture's size in Obsidian,
    /// and a bracket or a pipe would break the embed.
    @Test(arguments: [
        "",
        "PastedGraphic-1.png",
        "Ein Bild, das Text, Screenshot enthält.\n\nAutomatisch generierte Beschreibung",
        "Ein Bild, das Kleidung, Person, Lächeln enthält.\n\nKI-generierte Inhalte können fehlerhaft sein.",
        "A screenshot of a computer\n\nDescription automatically generated",
        "A close-up of a logo\n\nAI-generated content may be incorrect.",
        "A person standing in front of a building\n\nDescription generated with high confidence",
        "120",
        "120x40",
        "Logo [klein]",
        "Firma | Slogan",
    ])
    func embedsWithoutAnAliasAnAltTextThatSaysNothing(alt: String) {
        let converted = HTMLToMarkdown.convert("<img alt=\"\(alt)\" src=\"cid:logo@example.com\">", imageNames: ["logo@example.com": "logo.png"])

        #expect(converted.markdown == "![[logo.png]]")
    }

    /// A link around a picture is taken apart and the picture stays: Obsidian
    /// does not show an embed inside a link, and in an archive of 716 mails
    /// 135 of 136 such links held nothing but a logo or an icon.
    @Test func takesALinkAroundAnEmbeddedPictureApart() {
        let html = "<p>Gruss<br>Jane<br><a href=\"https://www.example.com/jane\"><img alt=\"LinkedIn\" src=\"cid:image002.png@01DC\"></a></p>"
        let converted = HTMLToMarkdown.convert(html, imageNames: ["image002.png@01DC": "image002.png"])

        #expect(converted.markdown == "Gruss\nJane\n![[image002.png|LinkedIn]]")
    }

    /// Without its file the picture is left out, and the link around it with
    /// it, since nothing in it shows: the note it was before.
    @Test func leavesALinkAroundAPictureWithoutItsFileAsItWas() {
        let html = "<p>Gruss<br>Jane <a href=\"https://www.example.com/jane\"><img alt=\"LinkedIn\" src=\"cid:image002.png@01DC\"></a></p>"
        let converted = HTMLToMarkdown.convert(html, imageNames: [:])

        #expect(converted.markdown == "Gruss\nJane")
        #expect(converted.images.map { $0.contentID } == ["image002.png@01DC"])
    }

    /// RFC 2392 writes the `Content-ID` after `cid:` with its special
    /// characters percent-encoded.
    @Test func readsAPercentEncodedAddress() {
        let converted = HTMLToMarkdown.convert("<img src=\"cid:image001.png%4001DC\">", imageNames: ["image001.png@01DC": "image001.png"])

        #expect(converted.markdown == "![[image001.png]]")
        #expect(converted.images.map { $0.contentID } == ["image001.png@01DC"])
    }

    /// The converter marks pictures with attributes of its own while it walks
    /// the HTML. A mail that brings them along does not steer it: not to a
    /// file of its choosing, and not to a picture it hides.
    @Test func ignoresTheMarksAMailBringsAlong() {
        let html = """
            <img data-mail2md-file="../geheim.png" src="cid:logo@example.com">\
            <div style="display:none"><img data-mail2md-shown src="cid:pixel@example.com"></div>
            """
        let converted = HTMLToMarkdown.convert(html, imageNames: [:])

        #expect(converted.markdown.isEmpty)
        #expect(converted.images == [InlineImage(contentID: "logo@example.com", width: nil, height: nil)])
    }

    /// Only a picture that shows takes a link apart: one the browser hides,
    /// and a picture of an emoji, which stays text, leave it whole.
    @Test(arguments: [
        ("<a href=\"https://example.com/jane\">Jane<img style=\"display:none\" src=\"cid:logo@example.com\"></a>", "[Jane](https://example.com/jane)"),
        ("<a href=\"https://example.com/jane\"><img alt=\"😉\" src=\"cid:logo@example.com\"></a>", "[😉](https://example.com/jane)"),
    ])
    func keepsALinkWhosePictureDoesNotShow(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html, imageNames: ["logo@example.com": "logo.png"]).markdown == expected)
    }

    /// A row of pictures alone is no row of text, so it cannot make a table of
    /// data out of a single row of it either.
    @Test func countsNoRowOfPicturesAloneTowardsData() {
        let html = "<table><tr><td>Jane Doe</td><td>Geschäftsleitung</td></tr><tr><td><img src=\"cid:a@example.com\"></td><td><img src=\"cid:b@example.com\"></td></tr></table>"
        let converted = HTMLToMarkdown.convert(html, imageNames: ["a@example.com": "a.png", "b@example.com": "b.png"])

        #expect(converted.markdown == "Jane Doe Geschäftsleitung\n![[a.png]] ![[b.png]]")
    }

    /// Whether a table holds data is decided as if its pictures were not
    /// there, so embedding them turns no layout into a table: the logo and the
    /// icon beside a signature leave it lines, with the pictures in them.
    @Test func keepsASignatureWithItsLogosForLayout() {
        let html = """
            <table><tr><td><img alt="Firmenlogo" src="cid:logo@example.com"></td><td>Jane Doe<br>Geschäftsleitung</td></tr>\
            <tr><td><img src="cid:icon@example.com"></td><td>www.example.com</td></tr></table>
            """
        let names = ["logo@example.com": "logo.png", "icon@example.com": "icon.png"]

        #expect(HTMLToMarkdown.convert(html, imageNames: names).markdown == "![[logo.png|Firmenlogo]] Jane Doe\nGeschäftsleitung\n![[icon.png]] www.example.com")
        #expect(HTMLToMarkdown.convert(html, imageNames: [:]).markdown == "Jane Doe\nGeschäftsleitung\nwww.example.com")
    }

    /// A table that holds data without its pictures holds them as well, in the
    /// cells they stand in.
    @Test func keepsThePicturesOfATableOfData() {
        let html = """
            <table><tr><th>Bild</th><th>Artikel</th><th>Preis</th></tr>\
            <tr><td><img src="cid:stuhl@example.com"></td><td>Stuhl</td><td>120</td></tr>\
            <tr><td><img src="cid:tisch@example.com"></td><td>Tisch</td><td>300</td></tr></table>
            """
        let converted = HTMLToMarkdown.convert(html, imageNames: ["stuhl@example.com": "stuhl.png", "tisch@example.com": "tisch.png"])

        #expect(converted.markdown == "| Bild | Artikel | Preis |\n|---|---|---|\n| ![[stuhl.png]] | Stuhl | 120 |\n| ![[tisch.png]] | Tisch | 300 |")
    }

    /// A picture looks the same with emphasis or without, so a line holding
    /// nothing but pictures gets no markers, in bold, in italics and in a
    /// header cell, while a line of text beside it keeps them.
    @Test(arguments: [
        ("<p><b><img alt=\"Signatur\" src=\"cid:logo@example.com\"></b></p>", "![[logo.png|Signatur]]"),
        ("<p><i><img src=\"cid:logo@example.com\"></i></p>", "![[logo.png]]"),
        ("<p><b>Jane Doe<br><img src=\"cid:logo@example.com\"></b></p>", "**Jane Doe**\n![[logo.png]]"),
        ("<table><tr><th><img src=\"cid:logo@example.com\"></th><td>Jane Doe</td></tr></table>", "![[logo.png]] Jane Doe"),
    ])
    func setsNoEmphasisAroundPicturesAlone(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html, imageNames: ["logo@example.com": "logo.png"]).markdown == expected)
    }

    /// In a table of data the pipe before the alias is escaped, which is how
    /// Obsidian writes a link with an alias inside a table.
    @Test func escapesTheAliasPipeOfAnEmbedInATable() {
        let html = "<table><tr><td>Logo</td><td><img alt=\"Firmenlogo\" src=\"cid:logo@example.com\"></td></tr><tr><td>Name</td><td>Muster AG</td></tr></table>"
        let converted = HTMLToMarkdown.convert(html, imageNames: ["logo@example.com": "logo.png"])

        #expect(converted.markdown == "|  |  |\n|---|---|\n| Logo | ![[logo.png\\|Firmenlogo]] |\n| Name | Muster AG |")
    }
}

// MARK: -

/// A box the mail sets apart, framed on all four sides or on a background of
/// its own. A card among them, a box of more than one line under a bold first
/// line, its title, is set apart in the note too: between rules, or as a
/// callout in Obsidian's format. A box inside a box belongs to it, and the box
/// holding the mail's last line is its footer, no card (Anton's decision B,
/// 2026-10-26).
struct BoxTests {

    /// A card framed on all four sides, as an insurer sets one per person.
    static let card = """
        <div>Davor</div><table role="presentation"><tr><td style="border:2px solid #CCCCCC;border-radius:8px;padding:12px 17px">\
        <div style="font-weight:bold">Jane Doe</div><div>01.01.1990, weiblich</div>\
        <div>Prämie pro Monat CHF <span style="font-weight:bold">100.00</span></div></td></tr></table><div>Danach</div>
        """

    @Test func setsACardApartAsACallout() {
        let expected = "Davor\n\n> [!quote] Jane Doe\n> 01.01.1990, weiblich\n> Prämie pro Monat CHF **100.00**\n\nDanach"

        #expect(HTMLToMarkdown.convert(Self.card, format: .obsidian) == expected)
    }

    @Test func setsACardApartBetweenRulesInPlainMarkdown() {
        let expected = "Davor\n\n---\n\n**Jane Doe**\n01.01.1990, weiblich\nPrämie pro Monat CHF **100.00**\n\n---\n\nDanach"

        #expect(HTMLToMarkdown.convert(Self.card) == expected)
    }

    /// A background of its own sets a box apart however the mail writes it,
    /// and only a colour that differs from the one around it.
    @Test(arguments: [
        "style=\"background-color:#4976BA;border-radius:8px\"",
        "style=\"background:#eee\"",
        "style=\"background: url(https://example.com/white.png) no-repeat #eeeeee\"",
        "style=\"background-color: rgb(73, 118, 186)\"",
        "style=\"background-color:#4976BA26\"",
        "style=\"background:yellow\"",
        "bgcolor=\"#4976ba\"",
        "bgcolor=\"4976ba\"",
    ])
    func setsABoxOnABackgroundOfItsOwnApart(background: String) {
        let html = """
            <div>Davor</div><table role="presentation"><tr><td \(background)>\
            <div style="font-weight:bold">522.–</div><div>Ersparnis pro Jahr in CHF</div></td></tr></table><div>Danach</div>
            """

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "Davor\n\n> [!quote] 522.–\n> Ersparnis pro Jahr in CHF\n\nDanach")
    }

    /// What is no card stays as it was: a box without a bold first line, one
    /// of a single line, a background like the one around it or none, a frame
    /// open at a side, a box inside a box, the footer, and a marked word.
    @Test(arguments: [
        ("<div style=\"background:#eeeeee\"><div>Zeile eins</div><div>Zeile zwei</div></div>", "Zeile eins\nZeile zwei"),
        ("<div style=\"border:1px solid #cccccc\"><b>Titel</b></div>", "**Titel**"),
        ("<div style=\"background:#ffffff\"><div style=\"background-color:white\"><b>Titel</b><div>Text</div></div></div>", "**Titel**\nText"),
        ("<div style=\"background-color:transparent\"><b>Titel</b><div>Text</div></div>", "**Titel**\nText"),
        ("<div style=\"background-color:rgba(0, 0, 0, 0)\"><b>Titel</b><div>Text</div></div>", "**Titel**\nText"),
        ("<div style=\"border-top:1px solid #cccccc\"><b>Titel</b><div>Text</div></div>", "**Titel**\nText"),
        ("<div style=\"border:1px solid #cccccc;border-bottom:none\"><b>Titel</b><div>Text</div></div>", "**Titel**\nText"),
        ("<div style=\"border:0 solid #cccccc\"><b>Titel</b><div>Text</div></div>", "**Titel**\nText"),
        ("<div style=\"border:1px solid #cccccc\"><div>Kopf</div><div style=\"background:#eeeeee\"><b>Innen</b><div>Text</div></div></div>", "Kopf\n**Innen**\nText"),
        ("<div style=\"border:1px solid #cccccc\"><div><b>Teil</b> und <b>Teil</b></div><div>Text</div></div>", "**Teil** und **Teil**\nText"),
        ("<div>Ein <span style=\"background:#eeeeee\"><b>Titel</b><br>Text</span></div>", "Ein **Titel**\nText"),
    ])
    func leavesWhatIsNoCardAsItWas(box: String, expected: String) {
        let html = "<div>Davor</div>\(box)<div>Danach</div>"

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "Davor\n\(expected)\nDanach")
    }

    /// The footer of a mail often sits on a colour of its own, a heading
    /// above the address, and it is no card.
    @Test func leavesTheBoxHoldingTheLastLineAsItWas() {
        let html = "<div>Brief</div><div style=\"background:#4976ba;color:#ffffff\"><b>Kontakt</b><div>Adresse</div></div>"

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "Brief\n**Kontakt**\nAdresse")
    }

    /// A mail lays its text on a panel of a colour of its own. The panel
    /// holding all of it is the page, and a card on it is a card.
    @Test(arguments: [
        "<div style=\"background:#f4f4f4\"><div style=\"background:#ffffff\">%@</div></div>",
        "<div style=\"background:#ffffff\"><div style=\"background:#f4f4f4\">%@</div></div>",
    ])
    func takesThePanelHoldingAllTextForThePage(panels: String) {
        let card = "<div>Hallo</div><div style=\"border:1px solid #cccccc\"><b>Karte</b><div>Text</div></div><div>Gruss</div>"
        let html = panels.replacingOccurrences(of: "%@", with: card)

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "Hallo\n\n> [!quote] Karte\n> Text\n\nGruss")
    }

    /// On a page of a colour of its own, a card in the colour around the
    /// page is a card.
    @Test func setsACardInAColourOfItsOwnOnAColouredPageApart() {
        let html = """
            <div style="background:#f4f4f4"><div>Hallo</div>\
            <div style="background:#ffffff"><b>Karte</b><div>Text</div></div><div>Gruss</div></div>
            """

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "Hallo\n\n> [!quote] Karte\n> Text\n\nGruss")
    }

    /// A browser sets a heading in bold, so a heading opening a box is its
    /// title.
    @Test func takesAHeadingForTheTitle() {
        let html = "<div style=\"border:1px solid #cccccc\"><h3>Buchungsdetails</h3><div>Nummer: 1</div></div><div>Danach</div>"

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == "> [!quote] Buchungsdetails\n>\n> Nummer: 1\n\nDanach")
    }

    /// A card whose title is a dark bar above a table of fields, as the
    /// parking confirmation sets its details.
    static func fieldCard(_ between: String = "", header: String = "") -> String {
        return """
            <div style="border:1px solid #cccccc"><table><tr><th>Buchungsdetails</th></tr></table>\(between)\
            <table>\(header)<tr><td><b>Nummer:</b></td><td>1</td></tr><tr><td><b>Datum:</b></td><td>01.09.2026</td></tr></table></div><div>Danach</div>
            """
    }

    /// Markdown needs a header over a table, and one without header cells
    /// gets an empty one, which under a callout's title shows as an empty
    /// first row. The title heads the table already, so its first row takes
    /// the header's place (Anton's decision A, 2026-10-26).
    @Test func takesTheFirstRowForTheHeaderOfATableRightUnderTheTitle() {
        let expected = "> [!quote] Buchungsdetails\n>\n> | **Nummer:** | 1 |\n> |---|---|\n> | **Datum:** | 01.09.2026 |\n\nDanach"

        #expect(HTMLToMarkdown.convert(Self.fieldCard(), format: .obsidian) == expected)
    }

    /// Only there: a table further down the card, a table with a header of
    /// its own, and the card between rules keep their header as before.
    @Test(arguments: [
        (BoxTests.fieldCard("<div>Stand heute</div>"), OutputFormat.obsidian, "> [!quote] Buchungsdetails\n> Stand heute\n>\n> |  |  |\n> |---|---|\n> | **Nummer:** | 1 |\n> | **Datum:** | 01.09.2026 |\n\nDanach"),
        (BoxTests.fieldCard(header: "<tr><th>Feld</th><th>Wert</th></tr>"), OutputFormat.obsidian, "> [!quote] Buchungsdetails\n>\n> | Feld | Wert |\n> |---|---|\n> | **Nummer:** | 1 |\n> | **Datum:** | 01.09.2026 |\n\nDanach"),
        (BoxTests.fieldCard(), OutputFormat.markdown, "---\n\n**Buchungsdetails**\n\n|  |  |\n|---|---|\n| **Nummer:** | 1 |\n| **Datum:** | 01.09.2026 |\n\n---\n\nDanach"),
    ])
    func keepsTheHeaderOfEveryOtherTableInACard(html: String, format: OutputFormat, expected: String) {
        #expect(HTMLToMarkdown.convert(html, format: format) == expected)
    }

    /// Two cards one below the other share the rule between them.
    @Test func drawsOneRuleBetweenTwoCards() {
        let html = """
            <div>Davor</div><div style="border:1px solid #cccccc"><b>Eins</b><div>Text</div></div>\
            <div style="height:20px;line-height:20px">&#8202;</div>\
            <div style="border:1px solid #cccccc"><b>Zwei</b><div>Text</div></div><div>Danach</div>
            """

        #expect(HTMLToMarkdown.convert(html) == "Davor\n\n---\n\n**Eins**\nText\n\n---\n\n**Zwei**\nText\n\n---\n\nDanach")
    }

    /// A frame alone makes no button, on a dark page with light text either:
    /// a button sits on a colour of its own.
    @Test func leavesAFramedLineOnADarkPagePlain() {
        let html = "<div style=\"background:#333333;color:#ffffff\"><div>Davor</div><div style=\"border:1px solid #ffffff\">Hinweis</div><div>Danach</div></div>"

        #expect(HTMLToMarkdown.convert(html) == "Davor\nHinweis\nDanach")
    }

    /// A box of one line in light text on a dark background of its own is a
    /// button, and a reader sees it at once, so it is bold. A pale bar in dark
    /// text is not, and neither is a button that is a link, which says so
    /// itself, or a dark box of more lines.
    @Test(arguments: [
        ("<td style=\"background:#757575\"><div style=\"color:#FFFFFF\">Kein Wechsel gewünscht</div></td>", "**Kein Wechsel gewünscht**"),
        ("<td style=\"background-color: rgb(15, 69, 39)\"><div style=\"color:white\">Bestätigt</div></td>", "**Bestätigt**"),
        ("<td bgcolor=\"#0f4527\"><font color=\"#ffffff\">Bestätigt</font></td>", "**Bestätigt**"),
        ("<td style=\"background:#0f4527;color:#fff\">Prämie CHF <b>100</b></td>", "**Prämie CHF 100**"),
        ("<td style=\"background:#E5E5E5\"><div style=\"color:#333333\">Keine Ersparnis</div></td>", "Keine Ersparnis"),
        ("<td style=\"background:#dff8ea\"><div style=\"color:#0f4527\">Ersparnis CHF <span style=\"font-weight:bold\">10.00</span></div></td>", "Ersparnis CHF **10.00**"),
        ("<td style=\"background:rgba(0, 0, 0, 0.15)\"><div style=\"color:#333333\">Hinweis</div></td>", "Hinweis"),
        ("<td style=\"background:#0f4527\"><a href=\"https://example.com\" style=\"color:#ffffff\">Ansehen</a></td>", "[Ansehen](https://example.com)"),
        ("<td style=\"background:#0f4527;color:#ffffff\"><div>Zeile eins</div><div>Zeile zwei</div></td>", "Zeile eins\nZeile zwei"),
    ])
    func boldsAButtonInLightTextOnADarkBackground(cell: String, expected: String) {
        let html = "<div>Davor</div><table role=\"presentation\"><tr>\(cell)</tr></table><div>Danach</div>"

        #expect(HTMLToMarkdown.convert(html) == "Davor\n\(expected)\nDanach")
    }
}

// MARK: -

/// Columns MJML sets side by side. A browser shows them next to each other
/// once the window is wide enough, and only the class names say so, because
/// the widths stand in a stylesheet. Where each column holds as many lines as
/// the others, the lines pair up as in a table.
struct ColumnTests {

    /// A column in the shape MJML writes it, `mj-column-per-49` for 49 %.
    static func column(_ percent: String, _ content: String) -> String {
        return "<div class=\"mj-column-per-\(percent) mj-outlook-group-fix\" style=\"font-size:0px;display:inline-block;vertical-align:top;width:100%;\">\(content)</div>"
    }

    /// Columns in the section MJML lays them out in, between Outlook's
    /// conditional comments.
    static func section(_ columns: [String]) -> String {
        let cells = columns.joined(separator: "<!--[if mso | IE]></td><td style=\"vertical-align:top;\"><![endif]-->")
        return """
            <div>Davor</div><table role="presentation"><tr><td style="font-size:0px;padding:0px;text-align:center;">\
            <!--[if mso | IE]><table role="presentation"><tr><td style="vertical-align:top;"><![endif]-->\(cells)\
            <!--[if mso | IE]></td></tr></table><![endif]--></td></tr></table><div>Danach</div>
            """
    }

    @Test func pairsColumnsOfAsManyLinesAsATable() {
        let left = Self.column("49", """
            <table role="presentation" style="background-color:#f5f5f5"><tr><td style="padding-top:4px"><div style="font-weight:bold"><span>Bisher:</span></div></td></tr>\
            <tr><td style="padding:8px"><div><span>Kasse A</span><br>Hausarzt</div></td></tr></table>
            """)
        let spacer = Self.column("2", "<table role=\"presentation\"><tbody></tbody></table>")
        let right = Self.column("49", """
            <table role="presentation" style="background-color:#4976BA26"><tr><td style="padding-top:4px"><div style="font-weight:bold"><span>Neu:</span></div></td></tr>\
            <tr><td style="padding:8px"><div><span>Kasse B</span><br>Telmed</div></td></tr></table>
            """)

        #expect(HTMLToMarkdown.convert(Self.section([left, spacer, right])) == "Davor\n\n| Bisher: | Neu: |\n|---|---|\n| Kasse A | Kasse B |\n| Hausarzt | Telmed |\n\nDanach")
    }

    /// Without a bold first line in every column there is no header to take,
    /// and Markdown's table gets an empty one, as a table of data does.
    @Test func writesAnEmptyHeaderOverColumnsWithoutATitleEach() {
        let left = Self.column("35", "<div><b>Eins</b></div><div>Zwei</div>")
        let right = Self.column("65", "<div>Drei</div><div>Vier | Fünf</div>")

        #expect(HTMLToMarkdown.convert(Self.section([left, right])) == "Davor\n\n|  |  |\n|---|---|\n| **Eins** | Drei |\n| Zwei | Vier \\| Fünf |\n\nDanach")
    }

    /// Columns of different lengths, columns of one line, and columns that
    /// each take the whole width stand one below the other, as before.
    @Test(arguments: [
        (["49", "49"], ["<div>Eins</div><div>Zwei</div>", "<div>Drei</div>"], "Eins\nZwei\nDrei"),
        (["49", "49"], ["<div>Eins</div>", "<div>Zwei</div>"], "Eins\nZwei"),
        (["100", "100"], ["<div>Eins</div><div>Zwei</div>", "<div>Drei</div><div>Vier</div>"], "Eins\nZwei\nDrei\nVier"),
        (["60", "60"], ["<div>Eins</div><div>Zwei</div>", "<div>Drei</div><div>Vier</div>"], "Eins\nZwei\nDrei\nVier"),
        (["49", "49"], ["<div>Eins</div><div>Zwei</div>", "<div>&#8202;</div>"], "Eins\nZwei"),
    ])
    func stacksColumnsThatDoNotPairUp(percents: [String], contents: [String], expected: String) {
        let html = Self.section(zip(percents, contents).map { Self.column($0, $1) })

        #expect(HTMLToMarkdown.convert(html) == "Davor\n\(expected)\nDanach")
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

    /// An insurer's confirmation, built with MJML: a banner, one card per
    /// person with the old and the new insurance in two columns, a bar with
    /// the saving, the premium in large bold figures and a status button, the
    /// footer on the company's colour. The weights stand in the style, never
    /// in a `b`. The expected note takes the form Anton corrected the note of
    /// 1.4.0 to by hand on 2026-10-25.
    @Test func mjml() {
        let font = "font-family:Source Sans Pro, Helvetica, Arial, sans-serif;"
        func section(_ content: String, style: String = "padding:0px;") -> String {
            return """
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:512px;">\
                <table align="center" border="0" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff;background-color:#ffffff;width:100%;">\
                <tbody><tr><td style="direction:ltr;font-size:0px;\(style)text-align:center;">\(content)</td></tr></tbody></table></div>
                """
        }
        func column(_ percent: String, _ content: String) -> String {
            return "<div class=\"mj-column-per-\(percent) mj-outlook-group-fix\" style=\"font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%;\">\(content)</div>"
        }
        func bar(_ background: String, _ color: String, _ size: String, _ content: String, padding: String) -> String {
            return column("100", """
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody><tr><td style="vertical-align:top;\(padding)">\
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody><tr>\
                <td align="center" style="background:\(background);font-size:0px;padding:0px 8px;padding-top:8px;padding-bottom:8px;word-break:break-word;">\
                <div style="\(font)font-size:\(size);line-height:20px;text-align:center;color:\(color);">\(content)</div></td></tr></tbody></table></td></tr></tbody></table>
                """)
        }
        func premium(_ amount: String) -> String {
            return column("100", """
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody><tr><td style="vertical-align:top;padding-top:8px;">\
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody><tr>\
                <td align="center" style="font-size:0px;padding:0px 8px;padding-top:16px;word-break:break-word;">\
                <div style="\(font)font-size:14px;line-height:20px;text-align:center;color:#7F7F7F;"><span>Prämie pro Monat CHF</span>
                <span style="font-size:28px;font-weight:bold;color:#333333"> \(amount)</span></div></td></tr></tbody></table></td></tr></tbody></table>
                """)
        }
        func insurance(_ heading: String, _ background: String, _ insurer: String, _ model: String) -> String {
            return column("49", """
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" style="background-color:\(background);vertical-align:top;" width="100%"><tbody>\
                <tr><td align="left" style="font-size:0px;padding:0px 8px;padding-top:4px;word-break:break-word;">\
                <div style="\(font)font-size:14px;font-weight:bold;line-height:20px;text-align:left;color:#333333;"><span>\(heading)</span></div></td></tr>\
                <tr><td align="left" style="font-size:0px;padding:8px;word-break:break-word;">\
                <div style="\(font)font-size:16px;line-height:20px;text-align:left;color:#333333;"><span>\(insurer)</span><br>\(model)</div></td></tr>\
                <tr><td align="left" style="font-size:0px;padding:0px 8px;padding-bottom:8px;word-break:break-word;">\
                <div style="\(font)font-size:14px;line-height:20px;text-align:left;color:#333333;"><span><span>Franchise: CHF 300.–</span><br>\
                <span>Unfalldeckung: Ja</span></span></div></td></tr></tbody></table>
                """)
        }
        func card(_ name: String, _ born: String, _ body: String) -> String {
            let person = column("100", """
                <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody>\
                <tr><td align="left" style="font-size:0px;padding:0;word-break:break-word;">\
                <div style="\(font)font-size:16px;font-weight:bold;line-height:24px;text-align:left;color:#333333;">\(name)</div></td></tr>\
                <tr><td align="left" style="font-size:0px;padding:0;word-break:break-word;">\
                <div style="\(font)font-size:14px;line-height:20px;text-align:left;color:#333333;"><span>\(born), </span>
                <span>Weiblich</span></div></td></tr></tbody></table>
                """)
            return """
                <div style="background:#FFFFFF;background-color:#FFFFFF;margin:0px auto;max-width:550px;border-radius:8px;overflow:hidden;">\
                <table align="center" border="0" cellpadding="0" cellspacing="0" role="presentation" style="background:#FFFFFF;background-color:#FFFFFF;width:100%;border-collapse:separate;">\
                <tbody><tr><td style="border:2px solid #CCCCCC;border-radius:8px;direction:ltr;font-size:0px;padding:12px 17px;text-align:center;">\
                \(section(person, style: "padding:0px;padding-bottom:12px;"))\(body)</td></tr></tbody></table></div>
                """
        }
        let banner = column("100", """
            <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%" style="border-collapse:separate;"><tbody><tr>\
            <td style="background-color:#4976BA;border-radius:8px;vertical-align:top;border-collapse:separate;padding-top:8px;padding-bottom:8px;">\
            <table border="0" cellpadding="0" cellspacing="0" role="presentation" width="100%"><tbody>\
            <tr><td align="center" style="font-size:0px;padding:0px 8px;padding-bottom:0px;word-break:break-word;">\
            <div style="\(font)font-size:28px;font-weight:bold;line-height:32px;text-align:center;color:#ffffff;">300.–</div></td></tr>\
            <tr><td align="center" style="font-size:0px;padding:0px 8px;padding-top:0px;word-break:break-word;">\
            <div style="\(font)font-size:20px;line-height:30px;text-align:center;color:#ffffff;">Totale Ersparnis pro Jahr in CHF</div></td></tr>\
            </tbody></table></td></tr></tbody></table>
            """)
        let spacing = "padding:0px;padding-top:8px;"
        let first = card("Jane Doe", "01.01.1990",
            section(insurance("Bisher:", "#f5f5f5", "Kasse A", "Hausarztmodell") + column("2", "<table border=\"0\" role=\"presentation\"><tbody></tbody></table>") + insurance("Neu für 2027:", "#4976BA26", "Kasse B", "Telmed"))
            + section(
                bar("#dff8ea", "#0f4527", "16px", "<span style=\"font-size:14px\">Ersparnis pro Jahr CHF</span>\n<span style=\"font-size:20px;font-weight:bold\">300.00</span>", padding: "padding:0px;")
                + premium("250.00")
                + bar("#0f4527", "#ffffff", "20px", "<span>Versicherung wechselt für Sie</span>", padding: "padding:0px;padding-top:18px;"),
                style: spacing
            )
        )
        let second = card("Mia Doe", "02.02.2010",
            section(column("100", """
                <div style="\(font)font-size:16px;line-height:20px;text-align:left;color:#333333;"><span>Kasse C – Hausarztmodell</span></div>\
                <div style="\(font)font-size:14px;line-height:20px;text-align:left;color:#333333;"><ul style="padding:4px 0;margin:0;list-style:none">\
                <li><span>Franchise: CHF 0.–</span></li><li><span>Unfalldeckung: Nein</span></li></ul></div>
                """))
            + section(
                bar("#E5E5E5", "#333333", "16px", "<span>Keine Ersparnis</span>", padding: "padding:0px;")
                + premium("100.00")
                + bar("#757575", "#FFFFFF", "20px", "<span>Kein Wechsel gewünscht</span>", padding: "padding:0px;padding-top:18px;"),
                style: spacing
            )
        )
        let spacer = "<div style=\"height:32px;line-height:32px;\">&#8202;</div>"
        let html = """
            <!doctype html><html><head><style type="text/css">@media only screen and (min-width:480px) { .mj-column-per-49 { width:49%!important; } }</style></head>\
            <body style="word-spacing:normal;background-color:#ffffff;">\
            <div style="display:none;font-size:1px;color:#ffffff;line-height:1px;max-height:0px;max-width:0px;opacity:0;overflow:hidden;">Es freut uns</div>\
            <div role="article" style="word-spacing:normal;background-color:#ffffff;">\
            <div style="\(font)font-size:16px;line-height:20px;text-align:left;color:#354052;"><p style="margin-top: 0px; margin-bottom: 12px;">Sehr geehrte Frau Doe</p></div>\
            <div style="height:40px;line-height:40px;">&#8202;</div>\
            \(section(banner, style: spacing))\(spacer)\(first)\(spacer)\(second)\(spacer)\
            <div style="\(font)font-size:16px;line-height:24px;text-align:left;color:#333333;"><strong>Umweltabgabe</strong><br>\
            <span>Die Umweltabgabe von <strong>CHF 4.75</strong> ist abgezogen.</span></div>\
            <div style="height:20px;line-height:20px;">&#8202;</div>\
            <div style="\(font)font-size:16px;line-height:20px;text-align:left;color:#354052;">\
            <p style="margin-top: 0px; margin-bottom: 12px; font-style: italic;">Alternativ mit Ihrem persönlichen Code abrufen.</p>\
            <p style="margin-top: 0px; margin-bottom: 12px;">Freundliche Grüsse<br>Ihre Versicherung</p></div>\
            <div style="background:#4976ba;background-color:#4976ba;margin:0px auto;max-width:600px;">\
            <div style="\(font)font-size:16px;line-height:28px;text-align:center;color:#ffffff;">Versicherung AG, Musterstrasse 1, 8000 Zürich<br>\
            <a href="https://www.example.com" style="text-decoration: none; color: #ffffff; font-weight: 700;">example.com</a> | \
            <a href="https://example.com/datenschutz" style="text-decoration: none; color: #ffffff; font-weight: 700;">Datenschutz</a></div></div>\
            </div></body></html>
            """
        let expected = """
            Sehr geehrte Frau Doe

            > [!quote] 300.–
            > Totale Ersparnis pro Jahr in CHF

            > [!quote] Jane Doe
            > 01.01.1990, Weiblich
            >
            > | Bisher: | Neu für 2027: |
            > |---|---|
            > | Kasse A | Kasse B |
            > | Hausarztmodell | Telmed |
            > | Franchise: CHF 300.– | Franchise: CHF 300.– |
            > | Unfalldeckung: Ja | Unfalldeckung: Ja |
            >
            > Ersparnis pro Jahr CHF **300.00**
            >
            > Prämie pro Monat CHF **250.00**
            >
            > **Versicherung wechselt für Sie**

            > [!quote] Mia Doe
            > 02.02.2010, Weiblich
            >
            > Kasse C – Hausarztmodell
            >
            > Franchise: CHF 0.–
            > Unfalldeckung: Nein
            >
            > Keine Ersparnis
            >
            > Prämie pro Monat CHF **100.00**
            >
            > **Kein Wechsel gewünscht**

            **Umweltabgabe**
            Die Umweltabgabe von **CHF 4.75** ist abgezogen.

            *Alternativ mit Ihrem persönlichen Code abrufen.*

            Freundliche Grüsse
            Ihre Versicherung

            Versicherung AG, Musterstrasse 1, 8000 Zürich
            **[example.com](https://www.example.com)** | **[Datenschutz](https://example.com/datenschutz)**
            """

        #expect(HTMLToMarkdown.convert(html, format: .obsidian) == expected)
    }
}
