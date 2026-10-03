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

    @Test func collapsesMailtoDuplicateEndingALongerToken() {
        // The twin need not be a word of its own: a label written straight
        // before the address still collapses onto it.
        #expect(BodyCleaner.clean("E-Mail:hr@example.com<mailto:hr@example.com>") == "E-Mail:hr@example.com")
    }

    @Test func cleansALongLinkInLinearTime() {
        // A backreference regex started at every character of a long token
        // and backtracked through all of it: 3 s for this link alone, 1.3 s
        // for a real mail with a few links of 1'000 characters (measured
        // 2026-10-03). The pass from the wrapper takes under a millisecond.
        let link = "https://example.com/?q=" + String(repeating: "a", count: 4_000)
        let body = "Hier der Link: \(link)\nKontakt: hr@example.com<mailto:hr@example.com>"

        var cleaned = ""
        let elapsed = ContinuousClock().measure {
            cleaned = BodyCleaner.clean(body)
        }

        #expect(cleaned == "Hier der Link: \(link)\nKontakt: hr@example.com")
        #expect(elapsed < .seconds(1))
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

    @Test func leavesAFencedCodeBlockAsItIs() {
        // Code keeps its blank lines and its spacing; only the text around
        // the fence is cleaned.
        let input = "Text.   \n\n\n\n```\ndef f():\n\n\n    return 1  \n```\n\n\n\nWeiter."
        #expect(BodyCleaner.clean(input) == "Text.\n\n```\ndef f():\n\n\n    return 1  \n```\n\nWeiter.")
    }

    @Test func cleansOnAfterAFenceThatNeverCloses() {
        // An unclosed fence is a stray line, not code.
        #expect(BodyCleaner.clean("```\nZeile.\n\n\n\nNoch eine.") == "```\nZeile.\n\nNoch eine.")
    }
}
