//
//  InvisibleCharactersTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 02.10.2026.
//

import Testing
@testable import mail2md

/// The narrow rule: remove what is never legitimate in running text, keep and
/// report what can be, and count both.
struct InvisibleCharactersTests {

    @Test func removesZeroWidthSpacesAndByteOrderMarks() {
        let (text, report) = InvisibleCharacters.clean("\u{FEFF}Hallo\u{200B} Welt")

        #expect(text == "Hallo Welt")
        #expect(report == InvisibleCharacters.Report(zeroWidthSpaces: 1, byteOrderMarks: 1))
    }

    /// The filler behind a preview text, measured in the archive: zero-width
    /// characters with a space between each, so a chain is counted across the
    /// spaces, and the gap closes to the one space it stood for.
    @Test func removesAFillerChainAcrossTheSpacesBetween() {
        let filler = " \u{034F} \u{200C} \u{00AD} \u{034F} \u{200C} "
        let (text, report) = InvisibleCharacters.clean("Vorschau" + filler + "Inhalt")

        #expect(text == "Vorschau Inhalt")
        #expect(report == InvisibleCharacters.Report(zeroWidthChains: 5))
    }

    @Test func removesAChainWithoutInventingASpace() {
        let (text, report) = InvisibleCharacters.clean("Vor\u{200B}\u{200C}\u{200D}\u{FEFF}schau")

        #expect(text == "Vorschau")
        #expect(report == InvisibleCharacters.Report(zeroWidthChains: 4))
    }

    @Test func removesAChainThatFillsALine() {
        let (text, _) = InvisibleCharacters.clean("Zeile eins\n \u{200C} \u{200C} \u{200C} \nZeile zwei")

        #expect(text == "Zeile eins\n\nZeile zwei")
    }

    /// A soft hyphen or a non-joiner between letters is typography, not filler.
    @Test func keepsSingleInvisibleCharactersBetweenLetters() {
        let input = "Donau\u{00AD}dampf\u{00AD}schiff\u{00AD}fahrt, Auf\u{200C}lage"
        let (text, report) = InvisibleCharacters.clean(input)

        #expect(text == input)
        #expect(report.isEmpty)
    }

    /// Tag characters spell out text nobody sees, the carrier of ASCII
    /// smuggling. A subdivision flag is the one place they belong.
    @Test func removesTagCharactersButKeepsAFlag() {
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let (text, report) = InvisibleCharacters.clean("Gruss aus \(scotland), Hallo\u{E0049}\u{E0047}\u{E004E}")

        #expect(text == "Gruss aus \(scotland), Hallo")
        #expect(report == InvisibleCharacters.Report(tagCharacters: 3))
    }

    @Test func keepsAJoinerInsideAnEmojiAndReportsOneOutside() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let input = "\(family) a\u{200D}b"
        let (text, report) = InvisibleCharacters.clean(input)

        #expect(text == input)
        #expect(report == InvisibleCharacters.Report(joiners: 1))
    }

    /// Contacts on macOS wraps a copied phone number in LRO and PDF, so these
    /// occur in harmless mail too: kept, but named.
    @Test func keepsAndReportsDirectionMarksAndBidiControls() {
        let input = "\u{200E}Shalom\u{200F}, Tel. \u{202D}+41 79 000 00 00\u{202C}"
        let (text, report) = InvisibleCharacters.clean(input)

        #expect(text == input)
        #expect(report == InvisibleCharacters.Report(directionMarks: 2, bidiControls: 2))
    }

    /// Resend writes each space of a code block as no-break space, joiner and
    /// zero-width space. Read as a space, a copied command runs again.
    @Test func readsTheSpaceOfACodeBlockAsASpace() {
        let space = "\u{00A0}\u{200D}\u{200B}"
        let (text, report) = InvisibleCharacters.clean("curl\(space)-i\n\(space)\(space)-H")

        #expect(text == "curl -i\n  -H")
        #expect(report.isEmpty)
    }

    @Test func summarizesWhatWasRemovedAndWhatWasKept() {
        let report = InvisibleCharacters.Report(zeroWidthChains: 700, zeroWidthSpaces: 12, byteOrderMarks: 2, joiners: 2, directionMarks: 1)

        #expect(report.summary == "invisible characters: removed 714 (zero-width chains 700, ZWSP 12, BOM 2), kept 3 (ZWJ 2, LRM/RLM 1)")
    }

    @Test func summarizesOnlyWhatOccurred() {
        #expect(InvisibleCharacters.Report(tagCharacters: 3).summary == "invisible characters: removed 3 (tag characters 3)")
        #expect(InvisibleCharacters.Report(bidiControls: 2).summary == "invisible characters: kept 2 (bidi controls 2)")
    }

    @Test func addsTheReportsOfSeveralTexts() {
        var report = InvisibleCharacters.Report(zeroWidthSpaces: 1)
        report.add(InvisibleCharacters.Report(zeroWidthSpaces: 2, joiners: 1))

        #expect(report == InvisibleCharacters.Report(zeroWidthSpaces: 3, joiners: 1))
    }
}
