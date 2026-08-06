//
//  MarkdownRendererTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct MarkdownRendererTests {

    @Test func rendersTemplateFrontmatterAndBody() {
        let message = EMLParser().parse(simpleEML)
        let expected = """
            ---
            created: 2026-06-15T09:41
            from: "Jane Doe <jane@example.com>"
            to: "Anton Fillmann <anton@example.com>"
            via:
            subject: "Projektanfrage iOS"
            attachments:
            ---

            Hallo Anton,

            das ist eine Testmail.

            """

        let renderer = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)
        #expect(renderer.render(message) == expected)
    }

    @Test func rendersCreatedInReaderLocalZoneNotSenderZone() {
        // simpleEML's Date: is 09:41 +0200 == the 07:41 UTC instant. The reader's
        // zone, not the sender's offset, decides the wall-clock: Europe/Zurich
        // (CEST, +0200) renders 09:41; UTC renders 07:41 for the same instant.
        let message = EMLParser().parse(simpleEML)

        let zurich = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)
        #expect(zurich.render(message).contains("created: 2026-06-15T09:41\n"))

        let utc = MarkdownRenderer(timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc.render(message).contains("created: 2026-06-15T07:41\n"))
    }

    /// Regression: the sender's offset must not leak into the rendered wall-clock.
    /// Both headers denote 10:01 UTC, so a Zurich reader (CEST, +0200) sees 12:01
    /// either way; the earlier bug echoed the header's digits instead.
    @Test(arguments: [
        "Tue, 28 Jul 2026 10:01:00 +0000",
        "Tue, 28 Jul 2026 15:01:00 +0500",
    ])
    func rendersSameInstantRegardlessOfSenderOffset(header: String) {
        let message = EMLParser().parse("Date: \(header)\r\nSubject: T\r\n\r\nBody")
        let renderer = MarkdownRenderer(timeZone: TimeZone(identifier: "Europe/Zurich")!)

        #expect(renderer.render(message).contains("created: 2026-07-28T12:01\n"))
    }

    @Test func omitsHeadingAndMessageID() {
        let markdown = MarkdownRenderer().render(EMLParser().parse(simpleEML))

        #expect(markdown.contains("# Inhalt") == false)
        #expect(markdown.contains("message-id") == false)
    }

    @Test func rendersBareKeyForMissingHeader() {
        let markdown = MarkdownRenderer().render(
            EMLParser().parse("Subject: Only a subject\r\n\r\nBody"))

        #expect(markdown.contains("\nfrom:\n"))
        #expect(markdown.contains("\ncreated:\n"))
    }

    @Test func rendersAttachmentsAsFlowList() {
        let markdown = MarkdownRenderer().render(EMLParser().parse(mixedEML))

        #expect(
            markdown.contains("attachments: [\"Lebenslauf.pdf\", \"Prüfung.pdf\", \"Foto.png\"]\n"))
    }
}
