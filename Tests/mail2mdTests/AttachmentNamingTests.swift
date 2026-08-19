//
//  AttachmentNamingTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 19.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct AttachmentNamingTests {

    /// 2026-08-18T07:52 UTC. Fixed and rendered in UTC, so the expectations
    /// below hold on any machine (same reasoning as the acceptance suite's
    /// pinned `TZ`).
    static let mailDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        components.hour = 7
        components.minute = 52
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    static let utc = TimeZone(identifier: "UTC")!

    /// A naming over the fixed date, in UTC.
    static func naming(_ pattern: String, date: Date? = AttachmentNamingTests.mailDate) -> AttachmentNaming {
        return AttachmentNaming(pattern: pattern, date: date, timeZone: AttachmentNamingTests.utc)
    }

    @Test func fillsTheVaultSchemaPattern() {
        let naming = Self.naming("{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}")

        #expect(naming.apply(to: "Foto.JPG") == "2026.08.18 07.52 ENCL Foto.JPG")
    }

    @Test func rendersDateAndTimeInTheirDefaultFormats() {
        let naming = Self.naming("{date} {time} {name}")

        #expect(naming.apply(to: "Doc.pdf") == "2026-08-18 07-52 Doc.pdf")
    }

    /// The common pattern says nothing about the extension, so it is appended.
    /// A pattern that does place `{ext}` keeps full control and gets no second
    /// copy.
    @Test(arguments: [
        ("ENCL {name}", "ENCL Foto.JPG"),
        ("ENCL {name}{ext}", "ENCL Foto.JPG"),
        ("{ext} {name}", ".JPG Foto"),
    ])
    func placesTheExtensionOnceAndOnlyOnce(pattern: String, expected: String) {
        #expect(Self.naming(pattern).apply(to: "Foto.JPG") == expected)
    }

    @Test func leavesANameWithoutExtensionWithoutADot() {
        #expect(Self.naming("ENCL {name}").apply(to: "README") == "ENCL README")
    }

    /// A leading dot belongs to the stem: `.gitignore` is a name, not a bare
    /// extension.
    @Test func keepsADotfileWhole() {
        #expect(Self.naming("ENCL {name}").apply(to: ".gitignore") == "ENCL .gitignore")
    }

    /// A pattern is a filename, never a path: a `/` in it (or in the mail's own
    /// filename) must not steer the write into another directory.
    @Test func neverProducesAPathSeparator() {
        let naming = Self.naming("{name}/../evil")

        #expect(naming.apply(to: "Doc.pdf") == "Doc-..-evil.pdf")
    }

    /// Only reachable through the library: the CLI refuses a date-bearing
    /// pattern on a dateless mail rather than writing a name with a hole.
    @Test func rendersDatePlaceholdersAsNothingWithoutADate() {
        let naming = Self.naming("{date} ENCL {name}", date: nil)

        #expect(naming.apply(to: "Doc.pdf") == "ENCL Doc.pdf")
    }

    @Test func keepsAnUnknownPlaceholderVerbatim() {
        #expect(Self.naming("{nmae} {name}").apply(to: "Doc.pdf") == "{nmae} Doc.pdf")
    }

    @Test func reportsUnknownPlaceholdersInOrder() {
        #expect(AttachmentNaming.unknownPlaceholders(in: "{date} {nmae} {name} {stem}") == ["nmae", "stem"])
        #expect(AttachmentNaming.unknownPlaceholders(in: "{date:yyyy} {name}{ext}").isEmpty)
    }

    @Test func knowsWhichPatternsNeedTheMailsDate() {
        #expect(AttachmentNaming.requiresDate("{date} {name}"))
        #expect(AttachmentNaming.requiresDate("{time:HH.mm} {name}"))
        #expect(AttachmentNaming.requiresDate("ENCL {name}{ext}") == false)
        // A literal that merely looks like one is not a placeholder.
        #expect(AttachmentNaming.requiresDate("{Datum} {name}") == false)
    }

    /// An unclosed brace is a literal, so no pattern can fail to parse.
    @Test func treatsAnUnclosedBraceAsText() {
        #expect(Self.naming("{name} {oops").apply(to: "Doc.pdf") == "Doc {oops.pdf")
    }
}
