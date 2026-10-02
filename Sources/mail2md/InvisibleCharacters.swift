//
//  InvisibleCharacters.swift
//  mail2md
//
//  Created by Anton Fillmann on 02.10.2026.
//

import Foundation

/// A narrow rule for characters nobody sees.
///
/// Removed is what never belongs in running text: chains of three or more
/// zero-width characters (the filler behind a preview text), Unicode tag
/// characters outside a flag, and the lone zero-width space and byte order
/// mark. Kept but reported is what can belong there: a joiner outside an emoji,
/// the two direction marks and the bidi controls. Both are counted, so a run
/// can say what it changed and point at what it left in.
///
/// Narrow on purpose. A rule that removed every invisible character would also
/// take the soft hyphen out of a German compound, the non-joiner out of Persian
/// and the joiner out of a family emoji. The text is foreign data on its way to
/// a reader that may be a language model, so what stays is named instead.
///
/// Pure and independent of the mail around it, so the same rule can guard a
/// mail reader later.
enum InvisibleCharacters {

    static func clean(_ text: String) -> (text: String, report: Report) {
        var report = Report()

        var scalars = self.decodingCodeSpaces(Array(text.unicodeScalars))
        scalars = self.removingChains(scalars, report: &report)
        scalars = self.removingStrays(scalars, report: &report)
        self.countKept(scalars, report: &report)

        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return (String(view), report)
    }
}

// MARK: - The report
extension InvisibleCharacters {

    /// What the rule found, per class.
    struct Report: Equatable {
        // Removed.
        var zeroWidthChains = 0
        var tagCharacters = 0
        var zeroWidthSpaces = 0
        var byteOrderMarks = 0

        // Kept, and reported for a second look.
        var joiners = 0
        var directionMarks = 0
        var bidiControls = 0

        var removed: Int {
            return self.zeroWidthChains + self.tagCharacters + self.zeroWidthSpaces + self.byteOrderMarks
        }

        var kept: Int {
            return self.joiners + self.directionMarks + self.bidiControls
        }

        var isEmpty: Bool {
            return self.removed == 0 && self.kept == 0
        }

        /// One line naming every class that occurred, the removed ones first:
        /// `invisible characters: removed 714 (zero-width chains 700, ZWSP 12,
        /// BOM 2), kept 3 (ZWJ 2, LRM/RLM 1)`.
        var summary: String {
            var parts: [String] = []

            let removed = self.listing([
                ("zero-width chains", self.zeroWidthChains),
                ("tag characters", self.tagCharacters),
                ("ZWSP", self.zeroWidthSpaces),
                ("BOM", self.byteOrderMarks),
            ])
            if self.removed > 0 {
                parts.append("removed \(self.removed) (\(removed))")
            }

            let kept = self.listing([
                ("ZWJ", self.joiners),
                ("LRM/RLM", self.directionMarks),
                ("bidi controls", self.bidiControls),
            ])
            if self.kept > 0 {
                parts.append("kept \(self.kept) (\(kept))")
            }

            return "invisible characters: " + parts.joined(separator: ", ")
        }

        mutating func add(_ other: Report) {
            self.zeroWidthChains += other.zeroWidthChains
            self.tagCharacters += other.tagCharacters
            self.zeroWidthSpaces += other.zeroWidthSpaces
            self.byteOrderMarks += other.byteOrderMarks
            self.joiners += other.joiners
            self.directionMarks += other.directionMarks
            self.bidiControls += other.bidiControls
        }

        private func listing(_ counts: [(label: String, count: Int)]) -> String {
            return counts
                .filter { $0.count > 0 }
                .map { "\($0.label) \($0.count)" }
                .joined(separator: ", ")
        }
    }
}

// MARK: - The steps
extension InvisibleCharacters {

    /// Resend writes every space of a code block as no-break space, joiner and
    /// zero-width space, in the plain part as in the HTML. The sequence is a
    /// space, and it has to become one before the rule sees its pieces: the
    /// rule would remove the zero-width space and keep the joiner, and a copied
    /// command would not run.
    fileprivate static func decodingCodeSpaces(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)

        var index = 0
        while index < scalars.count {
            let isCodeSpace = index + 2 < scalars.count
                && scalars[index] == "\u{00A0}"
                && scalars[index + 1] == "\u{200D}"
                && scalars[index + 2] == "\u{200B}"

            if isCodeSpace {
                result.append(" ")
                index += 3
                continue
            }
            result.append(scalars[index])
            index += 1
        }

        return result
    }

    /// Removes every chain of three or more zero-width characters.
    ///
    /// A chain may have horizontal whitespace between its characters, because
    /// that is how the fillers in the archive are built: `U+034F`, a space,
    /// `U+200C`, a space, and so on. Of 2171 chains measured on 2026-10-02,
    /// only three were unbroken. The chain takes the whitespace around it
    /// along, and the gap closes to a single space where it stood between two
    /// words on one line, to nothing at the edge of a line.
    fileprivate static func removingChains(_ scalars: [Unicode.Scalar], report: inout Report) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)

        var index = 0
        while index < scalars.count {
            guard self.isZeroWidth(scalars[index]) || self.isHorizontalSpace(scalars[index]) else {
                result.append(scalars[index])
                index += 1
                continue
            }

            // The run of zero-width characters and spaces starting here.
            var end = index
            while end < scalars.count, self.isZeroWidth(scalars[end]) || self.isHorizontalSpace(scalars[end]) {
                end += 1
            }
            let run = scalars[index..<end]
            let zeroWidthCount = run.filter { self.isZeroWidth($0) }.count

            if zeroWidthCount >= 3 {
                report.zeroWidthChains += zeroWidthCount

                let hasSpace = run.contains { self.isHorizontalSpace($0) }
                let betweenWords = index > 0 && end < scalars.count && scalars[index - 1] != "\n" && scalars[end] != "\n"
                if hasSpace && betweenWords {
                    result.append(" ")
                }
            }
            else {
                result.append(contentsOf: run)
            }
            index = end
        }

        return result
    }

    /// Removes what is never legitimate on its own: a zero-width space, a byte
    /// order mark inside the text, and a tag character outside a flag.
    fileprivate static func removingStrays(_ scalars: [Unicode.Scalar], report: inout Report) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]

            if let end = self.flagEnd(in: scalars, at: index) {
                result.append(contentsOf: scalars[index...end])
                index = end + 1
                continue
            }

            switch scalar.value {
            case 0x200B:
                report.zeroWidthSpaces += 1
            case 0xFEFF:
                report.byteOrderMarks += 1
            case 0xE0000...0xE007F:
                report.tagCharacters += 1
            default:
                result.append(scalar)
            }
            index += 1
        }

        return result
    }

    /// Counts what stays but deserves a second look.
    fileprivate static func countKept(_ scalars: [Unicode.Scalar], report: inout Report) {
        let positions = scalars.enumerated()
        for (index, scalar) in positions {
            switch scalar.value {
            case 0x200D:
                if self.joinsEmoji(scalars, at: index) == false {
                    report.joiners += 1
                }
            case 0x200E, 0x200F:
                report.directionMarks += 1
            case 0x202A...0x202E, 0x2066...0x2069:
                report.bidiControls += 1
            default:
                break
            }
        }
    }
}

// MARK: - Character classes
extension InvisibleCharacters {

    /// The zero-width characters the fillers in the archive are built from,
    /// with their siblings: soft hyphen, combining grapheme joiner, Arabic
    /// letter mark, Mongolian vowel separator, the zero-width space, non-joiner
    /// and joiner, both direction marks, word joiner, the invisible operators
    /// and the zero-width no-break space. On its own each can be legitimate;
    /// three in a chain never are.
    fileprivate static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x034F, 0x061C, 0x180E, 0x200B...0x200F, 0x2060...0x2064, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Whitespace that stays on its line, the no-break space included.
    fileprivate static func isHorizontalSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Where a subdivision flag ends, if one starts at `index`: the black flag,
    /// one or more tag characters spelling the region, and the cancel tag.
    fileprivate static func flagEnd(in scalars: [Unicode.Scalar], at index: Int) -> Int? {
        guard scalars[index].value == 0x1F3F4 else {
            return nil
        }

        var end = index + 1
        while end < scalars.count, (0xE0020...0xE007E).contains(scalars[end].value) {
            end += 1
        }
        guard
            end > index + 1,
            end < scalars.count,
            scalars[end].value == 0xE007F
        else {
            return nil
        }
        return end
    }

    /// Whether the joiner at `index` links two emoji, as in a family or a
    /// profession. Variation selectors and skin-tone modifiers may sit between
    /// the emoji before it and the joiner.
    fileprivate static func joinsEmoji(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        var before = index - 1
        while before >= 0, self.isEmojiAppendage(scalars[before]) {
            before -= 1
        }
        let after = index + 1

        guard
            before >= 0,
            after < scalars.count
        else {
            return false
        }
        return self.isPictographic(scalars[before]) && self.isPictographic(scalars[after])
    }

    /// An emoji character proper. ASCII is excluded, because digits, `#` and
    /// `*` count as emoji only for their keycap sequences.
    fileprivate static func isPictographic(_ scalar: Unicode.Scalar) -> Bool {
        return scalar.value > 0x7F && scalar.properties.isEmoji
    }

    fileprivate static func isEmojiAppendage(_ scalar: Unicode.Scalar) -> Bool {
        return scalar.value == 0xFE0F || scalar.properties.isEmojiModifier
    }
}
