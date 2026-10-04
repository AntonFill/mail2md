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

    /// The cleaner looks at every line of a body, and in 1.2.1 it built four
    /// regexes for each one: the median mail of the archive took 48 instead of
    /// 20 ms (measured 2026-10-04). A regex now runs only on a line that holds
    /// what it looks for, and these 4'000 lines, which hold nothing of it, take
    /// 27 ms in a debug build instead of 2.35 s.
    @Test func cleansManyOrdinaryLinesQuickly() {
        let body = Array(repeating: "Eine gewöhnliche Zeile ohne Ballast.", count: 2_000).joined(separator: "\n\n")

        var cleaned = ""
        let elapsed = ContinuousClock().measure {
            cleaned = BodyCleaner.clean(body)
        }

        #expect(cleaned == body)
        #expect(elapsed < .milliseconds(500))
    }

    @Test func collapsesDuplicateURL() {
        #expect(BodyCleaner.clean("https://example.com/x<https://example.com/x>") == "https://example.com/x")
    }

    @Test func stripsCIDImageReferences() {
        let input = "Grüsse\n[cid:logo001.png]\n\nAndré"
        #expect(BodyCleaner.clean(input) == "Grüsse\n\nAndré")
    }

    @Test func removesExchangesFirstContactBanner() {
        // Exchange writes it into the mail it receives; the sender never did.
        let input = """
            Sie erhalten nicht oft eine E-Mail von hr@example.com. [Erfahren Sie, warum dies wichtig ist](https://aka.ms/LearnAboutSenderIdentification)

            Sehr geehrter Herr Muster
            """
        #expect(BodyCleaner.clean(input) == "Sehr geehrter Herr Muster")
    }

    /// The marker is matched whatever the case of its link, and so is the
    /// check that lets a line reach the pattern: one stricter than the pattern
    /// would switch it off without a word. The archive writes the link one
    /// way only (14 times, 2026-10-04).
    @Test func removesTheBannerWhateverTheCaseOfItsLink() {
        let input = "You don't often get email from hr@example.com. [Learn why this is important](https://aka.ms/learnaboutsenderidentification)\n\nDear Sir"

        #expect(BodyCleaner.clean(input) == "Dear Sir")
    }

    @Test func removesTheBannerInAQuoteWithOneOfItsBlankLines() {
        let input = """
            > Grüsse
            >
            > You don't often get email from hr@example.com. [Learn why this is important](https://aka.ms/LearnAboutSenderIdentification)
            >
            > Sehr geehrte Damen und Herren
            """
        #expect(BodyCleaner.clean(input) == "> Grüsse\n>\n> Sehr geehrte Damen und Herren")
    }

    @Test func removesTheBannerInItsPlainForm() {
        let input = """
            Sie erhalten nicht häufig E-Mails von hr@example.com. Erfahren Sie, warum dies wichtig ist<https://aka.ms/LearnAboutSenderIdentification>
            > Sie erhalten nicht oft eine E-Mail von hr@example.com. Erfahren Sie, warum dies wichtig ist <https://aka.ms/LearnAboutSenderIdentification>
            Sehr geehrte Damen und Herren
            """
        #expect(BodyCleaner.clean(input) == "Sehr geehrte Damen und Herren")
    }

    @Test func keepsALineThatGoesOnAfterTheBannerLink() {
        // The banner ends with its link; a line that goes on is somebody's text.
        let input = "[Warum?](https://aka.ms/LearnAboutSenderIdentification) fragt Microsoft."
        #expect(BodyCleaner.clean(input) == input)
    }

    @Test func dropsALinkAroundAPicturePlaceholder() {
        // Apple Mail quotes a picture as its file name in angle brackets, and
        // a linked one, a social icon in a signature, keeps its link.
        let input = """
            > Grüsse
            >
            > [<image001.png>](https://example.com/linkedin) [<image002.png>](https://example.com/xing)
            >
            > ___________________________
            """
        #expect(BodyCleaner.clean(input) == "> Grüsse\n>\n> ___________________________")
    }

    @Test func keepsTheTextBesideALinkedPlaceholder() {
        let input = "> [<image447521.PNG>](https://example.com/) Jana Muster | Beraterin"
        #expect(BodyCleaner.clean(input) == "> Jana Muster | Beraterin")
    }

    @Test func keepsAPlaceholderThatIsNotALinkedPicture() {
        // Unlinked, it is often the trace of a photo or a document the quoted
        // mail carried, like the PDF beside it; and a document is no picture,
        // linked or not.
        let input = "> <Mail-Anhang.jpeg>\n> <Lebenslauf.pdf>\n> [<Preisliste.pdf>](https://example.com/preise)"
        #expect(BodyCleaner.clean(input) == input)
    }

    @Test func leavesNoGapWhereTextSurroundsARemovedLine() {
        let input = "> Grüsse\n> [<image001.png>](https://example.com/a)\n> Jana Muster"
        #expect(BodyCleaner.clean(input) == "> Grüsse\n> Jana Muster")
    }

    @Test func keepsTheOnlyBlankLineBesideARemovedLine() {
        // Text above it and a blank line below: that blank line is the
        // paragraph break, and nothing doubles it.
        let input = "> Grüsse\n> [<image001.png>](https://example.com/a)\n>\n> Jana Muster"
        #expect(BodyCleaner.clean(input) == "> Grüsse\n>\n> Jana Muster")
    }

    @Test func keepsTheShallowerBlankLineWhereAQuoteEnds() {
        let input = "> Grüsse\n>\n> [<image001.png>](https://example.com/a)\n\nNeuer Absatz"
        #expect(BodyCleaner.clean(input) == "> Grüsse\n\nNeuer Absatz")
    }

    @Test func endsTheBodyWithoutAnEmptyQuoteLine() {
        let input = "> Grüsse\n>\n> [<image001.png>](https://example.com/a)"
        #expect(BodyCleaner.clean(input) == "> Grüsse")
    }

    @Test func startsTheBodyWithoutAnEmptyQuoteLine() {
        let input = "> [<image001.png>](https://example.com/a)\n>\n> Grüsse"
        #expect(BodyCleaner.clean(input) == "> Grüsse")
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
