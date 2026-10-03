//
//  MIMEDecoding.swift
//  mail2md
//
//  Created by Anton Fillmann on 20.07.2026.
//

import Foundation

/// A MIME entity: a parsed header block plus its still-encoded body.
struct MIMEEntity {
    let headers: [String: String]
    let rawBody: String

    /// How `rawBody` stands for the bytes of the file.
    let source: SourceText

    /// The body as the bytes it stood in the file.
    var bodyBytes: [UInt8] {
        switch self.source {
        case .utf8:
            return Array(self.rawBody.utf8)
        case .bytes:
            return self.rawBody.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
        }
    }
}

/// How the text of a mail stands for the bytes of its file.
enum SourceText: Equatable {
    /// The file is UTF-8, so the text is the mail, and a string's UTF-8 is the
    /// bytes it was read from.
    case utf8

    /// The file is not UTF-8, so it is read byte for byte: each byte becomes
    /// the scalar of the same number, the way Latin-1 maps them, and the parse
    /// keeps every one of them. `charset` is the one the mail declares for
    /// its 8-bit bytes, used where nothing closer declares one, as in a header.
    case bytes(charset: String.Encoding)
}

/// A parsed `Content-Type` header, e.g. `multipart/alternative; boundary="x"`.
struct ContentType {
    let mediaType: String  // lowercased, e.g. "text/plain"
    let parameters: [String: String]  // lowercased keys

    var boundary: String? {
        return self.parameters["boundary"]
    }

    var charset: String? {
        return self.parameters["charset"]
    }

    /// Whether this is an S/MIME cryptographic part: a detached signature
    /// (`smime.p7s`) or a PKCS#7 envelope (`smime.p7m`). Such parts carry
    /// `Content-Disposition: attachment` but are message machinery, not user
    /// attachments, so they must be excluded from the attachment listing.
    /// The `x-` variants are the legacy spelling still emitted by Outlook.
    var isSMIMEArtifact: Bool {
        switch self.mediaType {
        case "application/pkcs7-signature", "application/x-pkcs7-signature",
            "application/pkcs7-mime", "application/x-pkcs7-mime":
            return true
        default:
            return false
        }
    }
}

// MARK: - Parameterized headers

/// Splits a `value; key=val; key2="val2"` header (the shared grammar of
/// `Content-Type` and `Content-Disposition`) into its leading value and a
/// parameter map. Value and keys are lowercased; quoted parameter values are
/// unwrapped.
func parseHeaderParameters(_ raw: String) -> (value: String, parameters: [String: String]) {
    let segments = raw.components(separatedBy: ";")
    let value = segments[0].trimmingCharacters(in: .whitespaces).lowercased()

    var parameters: [String: String] = [:]
    for segment in segments.dropFirst() {
        guard let equals = segment.firstIndex(of: "=") else {
            continue
        }
        let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        var paramValue = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if paramValue.hasPrefix("\"") && paramValue.hasSuffix("\"") && paramValue.count >= 2 {
            paramValue = String(paramValue.dropFirst().dropLast())
        }
        parameters[key] = paramValue
    }

    return (value, parameters)
}

// MARK: - Content-Type

/// Parses a `Content-Type` value into media type and parameters.
/// Defaults to `text/plain` when the header is absent (RFC 2045).
func parseContentType(_ raw: String?) -> ContentType {
    guard let raw, raw.isEmpty == false else {
        return ContentType(mediaType: "text/plain", parameters: [:])
    }

    let (mediaType, parameters) = parseHeaderParameters(raw)
    return ContentType(mediaType: mediaType, parameters: parameters)
}

// MARK: - Content-Disposition

/// Parses a `Content-Disposition` value (e.g. `attachment; filename="cv.pdf"`)
/// into its disposition type and, if present, the RFC 2047-decoded filename.
/// Returns an empty type when the header is absent. (RFC 2231 extended
/// `filename*=` parameters are out of scope.)
func parseContentDisposition(_ raw: String?) -> (type: String, filename: String?) {
    guard let raw, raw.isEmpty == false else {
        return ("", nil)
    }

    let (type, parameters) = parseHeaderParameters(raw)
    return (type, parameters["filename"].map(decodeRFC2047Header))
}

// MARK: - Charsets

/// Maps a MIME charset label to a `String.Encoding` via CoreFoundation's
/// IANA charset registry. Falls back to UTF-8 for absent or unknown labels.
/// This is the encoding the label declares; how text in it is read is up to
/// `decodeText`.
func stringEncoding(for charset: String?) -> String.Encoding {
    guard let charset, charset.isEmpty == false else {
        return .utf8
    }

    let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    guard cfEncoding != kCFStringEncodingInvalidId else {
        return .utf8
    }

    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
}

/// Decodes text in the encoding its charset declares, the way a mail program
/// reads it, or nil when the bytes are not valid in that encoding.
///
/// ISO-8859-1, ASCII and windows-1252 are all read as windows-1252, which is
/// what the WHATWG Encoding Standard makes of their labels and so what a mail
/// program built on it shows. Mail declared ISO-8859-1 is often written in
/// windows-1252: a ticket system still sent „ and “ that way in 2024, as the
/// bytes 84 and 93, which ISO-8859-1 itself reads as invisible control
/// characters. Foundation's windows-1252 is no help here, because it refuses
/// the whole text at any of the five bytes the encoding leaves unassigned.
func decodeText(_ bytes: [UInt8], encoding: String.Encoding) -> String? {
    switch encoding {
    case .isoLatin1, .ascii, .windowsCP1252:
        return windows1252Text(bytes)
    default:
        return String(bytes: bytes, encoding: encoding)
    }
}

/// Text in windows-1252 as the WHATWG Encoding Standard reads it. Every byte
/// stands for one character, so it cannot fail.
private func windows1252Text(_ bytes: [UInt8]) -> String {
    var scalars = String.UnicodeScalarView()
    for byte in bytes {
        switch byte {
        case 0x80...0x9F:
            scalars.append(windows1252Block[Int(byte - 0x80)])
        default:
            scalars.append(Unicode.Scalar(byte))
        }
    }
    return String(scalars)
}

/// What windows-1252 puts on the bytes 80 to 9F, eight to a row, as the
/// standard's index lists it. Every other byte is the code point of the same
/// number, as in Latin-1, and so are the five the encoding leaves unassigned
/// (81, 8D, 8F, 90, 9D): the standard reads them as the control characters
/// there.
private let windows1252Block: [Unicode.Scalar] = [
    "\u{20AC}", "\u{0081}", "\u{201A}", "\u{0192}", "\u{201E}", "\u{2026}", "\u{2020}", "\u{2021}",
    "\u{02C6}", "\u{2030}", "\u{0160}", "\u{2039}", "\u{0152}", "\u{008D}", "\u{017D}", "\u{008F}",
    "\u{0090}", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{2022}", "\u{2013}", "\u{2014}",
    "\u{02DC}", "\u{2122}", "\u{0161}", "\u{203A}", "\u{0153}", "\u{009D}", "\u{017E}", "\u{0178}",
]

// MARK: - Transfer encodings

/// Decodes a quoted-printable body into raw bytes.
///
/// Handles soft line breaks (`=` at end of line) and `=XX` hex escapes.
/// In `isHeader` (RFC 2047 "Q") mode, `_` decodes to a space and soft line
/// breaks do not apply. A raw byte beyond ASCII, which quoted-printable does
/// not allow but some mailers send, passes through as it is.
func quotedPrintableBytes(_ input: [UInt8], isHeader: Bool) -> [UInt8] {
    var out: [UInt8] = []
    let lines = input.split(separator: 0x0A, omittingEmptySubsequences: false)

    for (index, line) in lines.enumerated() {
        let bytes = Array(line)
        var i = 0
        var softBreak = false

        while i < bytes.count {
            let byte = bytes[i]

            if isHeader && byte == 0x5F {  // '_' → space in Q-encoded headers
                out.append(0x20)
                i += 1
                continue
            }

            if byte == 0x3D {  // '='
                if isHeader == false && i == bytes.count - 1 {
                    softBreak = true
                    i += 1
                    continue
                }
                if i + 2 <= bytes.count - 1, let high = hexValue(bytes[i + 1]), let low = hexValue(bytes[i + 2]) {
                    out.append(UInt8(high << 4 | low))
                    i += 3
                    continue
                }
                // Malformed escape: keep the literal '='.
                out.append(byte)
                i += 1
                continue
            }

            out.append(byte)
            i += 1
        }

        if isHeader == false && softBreak == false && index < lines.count - 1 {
            out.append(0x0A)  // restore the hard line break
        }
    }

    return out
}

/// Decodes a quoted-printable body as text using the given encoding, or nil
/// when its bytes are not valid in that encoding.
func decodeQuotedPrintable(_ input: [UInt8], encoding: String.Encoding) -> String? {
    let bytes = quotedPrintableBytes(input, isHeader: false)
    return decodeText(bytes, encoding: encoding)
}

/// Decodes a base64 body as text using the given encoding.
func decodeBase64(_ input: String, encoding: String.Encoding) -> String {
    let cleaned = input.filter { $0.isWhitespace == false }
    guard let data = Data(base64Encoded: cleaned) else {
        return input
    }
    return decodeText(Array(data), encoding: encoding) ?? input
}

/// Decodes a leaf entity's body to its raw bytes according to the transfer
/// encoding, for binary attachment extraction. Unlike `decodeLeaf`, this never
/// routes the bytes through a text encoding: a `.png` or `.pdf` must survive
/// verbatim. Unknown/absent encodings (7bit, 8bit, binary) yield the body's
/// bytes as they stood in the file.
func decodeToBytes(_ entity: MIMEEntity) -> Data {
    let encoding = (entity.headers["content-transfer-encoding"] ?? "")
        .trimmingCharacters(in: .whitespaces)
        .lowercased()

    switch encoding {
    case "base64":
        let cleaned = entity.rawBody.filter { $0.isWhitespace == false }
        return Data(base64Encoded: cleaned) ?? Data(entity.bodyBytes)
    case "quoted-printable":
        return Data(quotedPrintableBytes(entity.bodyBytes, isHeader: false))
    default:  // 7bit, 8bit, binary, or absent
        return Data(entity.bodyBytes)
    }
}

// MARK: - RFC 2047 encoded-word headers

/// Decodes RFC 2047 encoded-words (`=?charset?B/Q?text?=`) in a header value.
/// Whitespace separating two adjacent encoded-words is removed, per the spec.
func decodeRFC2047Header(_ input: String) -> String {
    guard input.contains("=?") else {
        return input
    }

    let encodedWord = /=\?([^?]+)\?([BbQq])\?([^?]*)\?=/
    var result = ""
    var lastEnd = input.startIndex
    var previousWasWord = false

    for match in input.matches(of: encodedWord) {
        let gap = input[lastEnd..<match.range.lowerBound]
        if (previousWasWord && gap.allSatisfy { $0.isWhitespace }) == false {
            result += gap
        }

        let encoding = stringEncoding(for: String(match.output.1))
        let text = String(match.output.3)
        if String(match.output.2).uppercased() == "B" {
            result += decodeBase64(text, encoding: encoding)
        }
        else {
            result += decodeText(quotedPrintableBytes(Array(text.utf8), isHeader: true), encoding: encoding) ?? text
        }

        lastEnd = match.range.upperBound
        previousWasWord = true
    }

    result += input[lastEnd...]
    return result
}

// MARK: - Address lists

/// An address header (`From`, `To`, `Cc`) as a reader wants it: each mailbox
/// as `Name <address>`, or as the bare address where the name adds nothing.
///
/// What a mail program needs and a reader does not goes: the quotes around a
/// name, the angle brackets around an address without one, and a name that is
/// only the address again, which Outlook writes for everybody not in its
/// contacts (223 of 1'500 address headers in the archive, measured
/// 2026-10-03). A name keeps its quotes where it holds a comma or an angle
/// bracket, which would otherwise split the list or the mailbox. That includes
/// a comma only decoding reveals (`=?iso-8859-1?Q?M=FCller=2C_J=F6rg?=`), which
/// decoding the whole header used to set bare.
///
/// So the list is split before anything is decoded, at the commas outside a
/// quoted name. A header that is no list of mailboxes, a group like
/// `Undisclosed recipients: ;`, a name with a bare comma or an address with
/// an old-style comment, comes out as before, only decoded: guessing at it
/// could lose an address.
func normalizeAddressList(_ raw: String) -> String {
    var mailboxes: [String] = []
    let pieces = splitAddressList(raw)
    for piece in pieces {
        guard let mailbox = normalizeMailbox(piece) else {
            return decodeRFC2047Header(raw)
        }
        mailboxes.append(mailbox)
    }

    guard mailboxes.isEmpty == false else {
        return decodeRFC2047Header(raw)
    }
    return mailboxes.joined(separator: ", ")
}

/// Splits an address list at the commas outside a quoted name. A comma in an
/// address or a comment, which no mail in the archive has, splits a mailbox,
/// and the header comes out as before.
private func splitAddressList(_ raw: String) -> [String] {
    var pieces: [String] = []
    var piece = ""
    var isQuoted = false
    var isEscaped = false

    for character in raw {
        if isEscaped {
            isEscaped = false
        }
        else if isQuoted, character == "\\" {
            isEscaped = true
        }
        else if character == "\"" {
            isQuoted.toggle()
        }
        else if isQuoted == false, character == "," {
            pieces.append(piece)
            piece = ""
            continue
        }
        piece.append(character)
    }
    pieces.append(piece)

    return pieces
        .map { $0.trimmingCharacters(in: spacesAndTabs) }
        .filter { $0.isEmpty == false }
}

/// One mailbox as `Name <address>` or the bare address, or nil if the piece
/// is none: an address holds an `@`, and nothing stands beside a bare one.
private func normalizeMailbox(_ piece: String) -> String? {
    if let match = piece.wholeMatch(of: /(.*?)\s*<([^<>\s]*)>/) {
        let address = String(match.2)
        guard address.contains("@") else {
            return nil
        }
        return mailbox(name: displayName(String(match.1)), address: address)
    }

    guard piece.wholeMatch(of: /[^\s<>"(),;:]+@[^\s<>"(),;:]+/) != nil else {
        return nil
    }
    return piece
}

/// A display name as a reader sees it: decoded, then unquoted, so the quotes
/// a mailer encoded along with the name go as well, and without the single
/// quotes Outlook puts around an address it uses as a name.
private func displayName(_ raw: String) -> String {
    let name = unquoted(decodeRFC2047Header(raw).trimmingCharacters(in: spacesAndTabs))
    guard
        name.count >= 2,
        name.hasPrefix("'"),
        name.hasSuffix("'")
    else {
        return name
    }
    return String(name.dropFirst().dropLast())
}

/// The text of a quoted string with its backslash escapes resolved, if the
/// text is one quoted string; any other text, `"Muster" "AG"` among them, as
/// it is.
private func unquoted(_ text: String) -> String {
    guard
        text.count >= 2,
        text.hasPrefix("\""),
        text.hasSuffix("\"")
    else {
        return text
    }

    var result = ""
    var isEscaped = false
    for character in text.dropFirst().dropLast() {
        if isEscaped {
            isEscaped = false
        }
        else if character == "\\" {
            isEscaped = true
            continue
        }
        else if character == "\"" {
            return text
        }
        result.append(character)
    }
    return result
}

/// A mailbox as `Name <address>`, the name quoted only where a comma or an
/// angle bracket in it would split the list or the mailbox, or the bare
/// address where there is no name or the name is the address again.
private func mailbox(name: String, address: String) -> String {
    guard
        name.isEmpty == false,
        name.caseInsensitiveCompare(address) != .orderedSame
    else {
        return address
    }
    guard name.contains(where: { $0 == "," || $0 == "<" || $0 == ">" }) else {
        return "\(name) <\(address)>"
    }

    let escaped = name
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\" <\(address)>"
}

/// Spaces and tabs only: Foundation's `.whitespaces` holds U+200B as well,
/// and trimming it here would hide it from the invisible-character rule.
private let spacesAndTabs = CharacterSet(charactersIn: " \t")

// MARK: - Helpers

/// Returns the numeric value of an ASCII hex digit, or nil.
private func hexValue(_ byte: UInt8) -> Int? {
    switch byte {
    case 0x30...0x39: return Int(byte - 0x30)  // 0-9
    case 0x41...0x46: return Int(byte - 0x41 + 10)  // A-F
    case 0x61...0x66: return Int(byte - 0x61 + 10)  // a-f
    default: return nil
    }
}
