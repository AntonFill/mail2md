//
//  BodyCleanerTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Testing
@testable import mail2md

struct BodyCleanerTests {

    @Test func collapsesMailtoDuplicateOntoPlainTwin() {
        #expect(
            BodyCleaner.clean("Kontakt: hr@example.com<mailto:hr@example.com>") == "Kontakt: hr@example.com")
    }

    @Test func collapsesNestedMailtoInAttributionLine() {
        // The `Name <addr<mailto:addr>>` shape keeps `Name <addr>`.
        let input = "Am 11.06.2026 schrieb Jana Muster <hr@example.com<mailto:hr@example.com>>:"
        #expect(BodyCleaner.clean(input) == "Am 11.06.2026 schrieb Jana Muster <hr@example.com>:")
    }

    @Test func unwrapsStandaloneMailtoKeepingAddress() {
        #expect(
            BodyCleaner.clean("Schreiben Sie an <mailto:info@example.com>")
                == "Schreiben Sie an info@example.com")
    }

    @Test func collapsesDuplicateURL() {
        #expect(BodyCleaner.clean("https://example.com/x<https://example.com/x>") == "https://example.com/x")
    }

    @Test func stripsCIDImageReferences() {
        let input = "Grüsse\n[cid:logo001.png]\n\nAndré"
        #expect(BodyCleaner.clean(input) == "Grüsse\n\nAndré")
    }

    @Test func collapsesBlankLineRunsAndTrailingWhitespace() {
        #expect(
            BodyCleaner.clean("Absatz eins.   \n\n\n\nAbsatz zwei.")
                == "Absatz eins.\n\nAbsatz zwei.")
    }

    @Test func normalizesCarriageReturnsBeforeCollapsingBlankRuns() {
        // QP decoding reintroduces \r\n (=0D=0A) after the parser normalizes,
        // so a real blank-line run arrives as \r\n\r\n\r\n and must still collapse.
        #expect(
            BodyCleaner.clean("Zeile eins.\r\n\r\n\r\n\r\nZeile zwei.\r\n")
                == "Zeile eins.\n\nZeile zwei.")
    }

    @Test func preservesParagraphBreakAndQuoteMarkers() {
        // A single blank line (paragraph) and `>`-quote depth must survive.
        let input = "Neue Zeile.\n\n> Zitierte Zeile.\n>> Tiefer zitiert."
        #expect(BodyCleaner.clean(input) == "Neue Zeile.\n\n> Zitierte Zeile.\n>> Tiefer zitiert.")
    }
}
