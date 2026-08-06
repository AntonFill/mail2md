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
}
