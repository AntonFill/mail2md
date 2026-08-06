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

/// Maps a MIME charset label to a `String.Encoding` via CoreFoundation's
/// IANA charset registry. Falls back to UTF-8 for absent or unknown labels.
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

// MARK: - Transfer encodings

/// Decodes a quoted-printable body into raw bytes.
///
/// Handles soft line breaks (`=` at end of line) and `=XX` hex escapes.
/// In `isHeader` (RFC 2047 "Q") mode, `_` decodes to a space and soft line
/// breaks do not apply.
func quotedPrintableBytes(_ input: String, isHeader: Bool) -> [UInt8] {
    var out: [UInt8] = []
    let lines = input.components(separatedBy: "\n")

    for (index, line) in lines.enumerated() {
        let bytes = Array(line.utf8)
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

/// Decodes a quoted-printable body as text using the given encoding.
func decodeQuotedPrintable(_ input: String, encoding: String.Encoding) -> String {
    let bytes = quotedPrintableBytes(input, isHeader: false)
    return String(bytes: bytes, encoding: encoding) ?? input
}

/// Decodes a base64 body as text using the given encoding.
func decodeBase64(_ input: String, encoding: String.Encoding) -> String {
    let cleaned = input.filter { $0.isWhitespace == false }
    guard let data = Data(base64Encoded: cleaned) else {
        return input
    }
    return String(data: data, encoding: encoding) ?? input
}

/// Decodes a leaf entity's body to its raw bytes according to the transfer
/// encoding, for binary attachment extraction. Unlike `decodeLeaf`, this never
/// routes the bytes through a text encoding: a `.png` or `.pdf` must survive
/// verbatim. Unknown/absent encodings (7bit, 8bit, binary) yield the body's
/// UTF-8 bytes, matching how the source was read.
func decodeToBytes(_ entity: MIMEEntity) -> Data {
    let encoding = (entity.headers["content-transfer-encoding"] ?? "")
        .trimmingCharacters(in: .whitespaces)
        .lowercased()

    switch encoding {
    case "base64":
        let cleaned = entity.rawBody.filter { $0.isWhitespace == false }
        return Data(base64Encoded: cleaned) ?? Data(entity.rawBody.utf8)
    case "quoted-printable":
        return Data(quotedPrintableBytes(entity.rawBody, isHeader: false))
    default:  // 7bit, 8bit, binary, or absent
        return Data(entity.rawBody.utf8)
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
        } else {
            result += String(bytes: quotedPrintableBytes(text, isHeader: true), encoding: encoding) ?? text
        }

        lastEnd = match.range.upperBound
        previousWasWord = true
    }

    result += input[lastEnd...]
    return result
}

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
