//
//  OptionParser.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

/// Reads a command line the way `getopt_long(3)` reads it, so the habits a user brings from
/// `ls`, `cp` and `rm` carry over:
///
/// - Short flags can be grouped: `-rv` is `-r -v`.
/// - A value option takes its value attached (`--format=x`, `-ox`) or as the next argument
///   (`--format x`, `-o x`).
/// - Options and operands can come in any order.
/// - `--` ends the options, and everything after it is an operand. A lone `-` is an operand.
///
/// Two rules deliberately differ from getopt:
///
/// - **Long options are never abbreviated.** `--rec` is an unknown option, not `--recursive`:
///   a prefix that is unique today stops being unique the day an option is added, and a
///   command line that used to work breaks.
/// - **A value never starts with a dash unless it is attached.** getopt would read
///   `--format -r` as the format `-r`; here it is a missing value, because a forgotten value
///   is far more likely than a value that starts with a dash, and `--format=-r` still says it
///   on purpose. A lone `-` stays a value.
///
/// The parser only reads. It knows nothing about help, versions or which combinations make
/// sense; the command states its options, gets back what was on the line, and decides.
public struct OptionParser: Sendable {

    public let options: [Option]

    public init(_ options: [Option]) {
        self.options = options
    }
}

// MARK: - Option

/// One option a command accepts, keyed by its long name.
public struct Option: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        /// Present or absent, never with a value: `--rename`.
        case flag
        /// Carries a value: `--format yyyy.MM.dd`.
        case value
    }

    /// The name after `--`, and the key the parsed arguments use for this option.
    public let long: String
    /// The letter after `-`, if the option has a short form.
    public let short: Character?
    public let kind: Kind

    public static func flag(_ long: String, short: Character? = nil) -> Option {
        Option(long: long, short: short, kind: .flag)
    }

    public static func value(_ long: String, short: Character? = nil) -> Option {
        Option(long: long, short: short, kind: .value)
    }
}

// MARK: - Parsed arguments

/// What a command line held, by the long names of its options.
public struct ParsedArguments: Sendable, Equatable {

    /// The arguments that are not options, in command line order.
    public internal(set) var operands: [String] = []

    var setFlags: Set<String> = []
    var givenValues: [String: [String]] = [:]

    /// Whether the flag was on the command line, in its long or its short form.
    public func isSet(_ flag: String) -> Bool {
        self.setFlags.contains(flag)
    }

    /// Every value the option was given, in command line order, and none if it was not given.
    public func values(of option: String) -> [String] {
        self.givenValues[option] ?? []
    }

    /// The value the option was given last, which is the one that counts when it is repeated.
    public func value(of option: String) -> String? {
        self.givenValues[option]?.last
    }
}

// MARK: - Errors

/// A command line the parser cannot read. The description is the sentence a command prints
/// after its own name: `realdate: unknown option '--bogus'`.
public enum OptionError: Error, Equatable, CustomStringConvertible {
    /// An option that was not declared, as typed: `--bogus`, `-x`.
    case unknownOption(String)
    /// A value option without its value, as typed: `--format`, `-o`.
    case missingValue(String)
    /// A flag that was given a value: `--rename=yes` reports `--rename`.
    case unexpectedValue(String)

    public var description: String {
        switch self {
        case .unknownOption(let option):
            return "unknown option '\(option)'"
        case .missingValue(let option):
            return "option '\(option)' needs a value"
        case .unexpectedValue(let option):
            return "option '\(option)' takes no value"
        }
    }
}

// MARK: - Parsing

extension OptionParser {

    /// Reads the arguments after the command's own name.
    public func parse(_ arguments: [String]) throws -> ParsedArguments {
        var parsed = ParsedArguments()
        var remaining = arguments[...]

        while let argument = remaining.popFirst() {
            if argument == "--" {
                parsed.operands.append(contentsOf: remaining)
                break
            }
            else if argument.hasPrefix("--") {
                try self.readLongOption(argument, remaining: &remaining, into: &parsed)
            }
            else if argument.hasPrefix("-") && argument.count > 1 {
                try self.readShortOptions(argument, remaining: &remaining, into: &parsed)
            }
            else {
                parsed.operands.append(argument)
            }
        }
        return parsed
    }

    /// `--name`, `--name=value` or `--name value`.
    private func readLongOption(_ argument: String, remaining: inout ArraySlice<String>, into parsed: inout ParsedArguments) throws {
        let body = argument.dropFirst(2)
        let name: String
        let attachedValue: String?
        if let equals = body.firstIndex(of: "=") {
            name = String(body[..<equals])
            attachedValue = String(body[body.index(after: equals)...])
        }
        else {
            name = String(body)
            attachedValue = nil
        }

        guard let option = self.options.first(where: { $0.long == name }) else {
            // `--=x` has no name to report, so it is reported as typed.
            throw OptionError.unknownOption(name.isEmpty ? argument : "--\(name)")
        }

        switch option.kind {
        case .flag:
            guard attachedValue == nil else {
                throw OptionError.unexpectedValue("--\(name)")
            }
            parsed.setFlags.insert(option.long)
        case .value:
            let value: String
            if let attachedValue {
                value = attachedValue
            }
            else {
                value = try self.nextValue(for: "--\(name)", remaining: &remaining)
            }
            parsed.givenValues[option.long, default: []].append(value)
        }
    }

    /// `-r`, a group like `-rv`, or a value option with its value attached (`-ox`) or next.
    private func readShortOptions(_ argument: String, remaining: inout ArraySlice<String>, into parsed: inout ParsedArguments) throws {
        var letters = argument.dropFirst()

        while let letter = letters.popFirst() {
            guard let option = self.options.first(where: { $0.short == letter }) else {
                throw OptionError.unknownOption("-\(letter)")
            }

            switch option.kind {
            case .flag:
                parsed.setFlags.insert(option.long)
            case .value:
                // The rest of the group is the value, the way getopt reads `-ofile`.
                let value: String
                if letters.isEmpty {
                    value = try self.nextValue(for: "-\(letter)", remaining: &remaining)
                }
                else {
                    value = String(letters)
                }
                parsed.givenValues[option.long, default: []].append(value)
                return
            }
        }
    }

    /// The argument after a value option, unless it is missing or looks like an option itself.
    private func nextValue(for option: String, remaining: inout ArraySlice<String>) throws -> String {
        guard let next = remaining.first,
              next == "-" || next.hasPrefix("-") == false
        else {
            throw OptionError.missingValue(option)
        }
        remaining.removeFirst()
        return next
    }
}
