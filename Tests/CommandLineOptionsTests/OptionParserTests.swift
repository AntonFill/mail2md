//
//  OptionParserTests.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

import Testing
import CommandLineOptions

/// The getopt rules the parser promises, and the two places it deliberately departs from
/// them. The options below are not realdate's: `--output`/`-o` is a value option with a
/// short form, which realdate does not have and mail2md does.
@Suite("Option Parser")
struct OptionParserTests {

    private let parser = OptionParser([
        .value("format"),
        .value("output", short: "o"),
        .flag("recursive", short: "r"),
        .flag("verbose", short: "v"),
        .flag("rename"),
    ])

    // MARK: - Flags

    @Test("Reads a flag in its long and in its short form")
    func readsFlagInBothForms() throws {
        #expect(try self.parser.parse(["--recursive"]).isSet("recursive"))
        #expect(try self.parser.parse(["-r"]).isSet("recursive"))
        #expect(try self.parser.parse(["-r"]).isSet("verbose") == false)
    }

    @Test("Reads a group of short flags as each of them")
    func readsGroupedFlags() throws {
        let parsed = try self.parser.parse(["-rv"])

        #expect(parsed.isSet("recursive"))
        #expect(parsed.isSet("verbose"))
    }

    @Test("Accepts a repeated flag")
    func acceptsRepeatedFlag() throws {
        #expect(try self.parser.parse(["-v", "--verbose", "-vv"]).isSet("verbose"))
    }

    // MARK: - Values

    @Test("Reads a value attached or as the next argument, in both forms")
    func readsValueAttachedOrNext() throws {
        let parsed = try self.parser.parse(["--format=a", "--format", "b", "-oc", "-o", "d"])

        #expect(parsed.values(of: "format") == ["a", "b"])
        #expect(parsed.values(of: "output") == ["c", "d"])
    }

    @Test("Reads the rest of a group as the value of a value option in it")
    func readsRestOfGroupAsValue() throws {
        let parsed = try self.parser.parse(["-rodir"])

        #expect(parsed.isSet("recursive"))
        #expect(parsed.value(of: "output") == "dir")
    }

    @Test("Keeps every value of a repeated option, and the last one counts")
    func keepsRepeatedValuesInOrder() throws {
        let parsed = try self.parser.parse(["--format", "a", "--format", "b"])

        #expect(parsed.values(of: "format") == ["a", "b"])
        #expect(parsed.value(of: "format") == "b")
        #expect(parsed.value(of: "output") == nil)
        #expect(parsed.values(of: "output").isEmpty)
    }

    @Test("Passes an empty value on, because judging it is the command's business")
    func passesEmptyValueOn() throws {
        #expect(try self.parser.parse(["--format", ""]).values(of: "format") == [""])
        #expect(try self.parser.parse(["--format="]).values(of: "format") == [""])
    }

    @Test("Takes a lone dash as a value, the way -o - names standard output")
    func takesLoneDashAsValue() throws {
        #expect(try self.parser.parse(["-o", "-"]).value(of: "output") == "-")
    }

    // MARK: - Operands

    @Test("Reads options after the operands as options")
    func readsOptionsAfterOperands() throws {
        let parsed = try self.parser.parse(["file", "-r", "--format", "a"])

        #expect(parsed.operands == ["file"])
        #expect(parsed.isSet("recursive"))
        #expect(parsed.value(of: "format") == "a")
    }

    @Test("Ends the options at a double dash")
    func endsOptionsAtDoubleDash() throws {
        let parsed = try self.parser.parse(["-r", "--", "-v", "--format"])

        #expect(parsed.operands == ["-v", "--format"])
        #expect(parsed.isSet("verbose") == false)
    }

    @Test("Reads a lone dash as an operand")
    func readsLoneDashAsOperand() throws {
        #expect(try self.parser.parse(["-"]).operands == ["-"])
    }

    // MARK: - Refusals

    @Test("Rejects an unknown long option, and names it as typed")
    func rejectsUnknownLongOption() throws {
        #expect(throws: OptionError.unknownOption("--bogus")) {
            try self.parser.parse(["--bogus"])
        }
        #expect(throws: OptionError.unknownOption("--bogus")) {
            try self.parser.parse(["--bogus=1"])
        }
        // Nothing before the equals sign leaves nothing to name but the argument itself.
        #expect(throws: OptionError.unknownOption("--=x")) {
            try self.parser.parse(["--=x"])
        }
    }

    @Test("Rejects an unknown short option, also inside a group")
    func rejectsUnknownShortOption() throws {
        #expect(throws: OptionError.unknownOption("-x")) {
            try self.parser.parse(["-rx"])
        }
    }

    @Test("Never abbreviates a long option")
    func neverAbbreviates() throws {
        // A prefix that is unique today stops being unique when an option is added.
        #expect(throws: OptionError.unknownOption("--rec")) {
            try self.parser.parse(["--rec"])
        }
    }

    @Test("Refuses a value option at the end of the line")
    func refusesMissingValueAtEnd() throws {
        #expect(throws: OptionError.missingValue("--format")) {
            try self.parser.parse(["--format"])
        }
        #expect(throws: OptionError.missingValue("-o")) {
            try self.parser.parse(["-o"])
        }
    }

    @Test("Does not take an option as a value unless it is attached")
    func doesNotTakeOptionAsValue() throws {
        // getopt would read the format -r here. A forgotten value is the likelier story.
        #expect(throws: OptionError.missingValue("--format")) {
            try self.parser.parse(["--format", "-r", "dir"])
        }
        #expect(throws: OptionError.missingValue("-o")) {
            try self.parser.parse(["-o", "--rename"])
        }
        #expect(try self.parser.parse(["--format=-r"]).value(of: "format") == "-r")
    }

    @Test("Refuses a value on a flag")
    func refusesValueOnFlag() throws {
        #expect(throws: OptionError.unexpectedValue("--rename")) {
            try self.parser.parse(["--rename=yes"])
        }
    }

    @Test("Describes each refusal as a sentence to print after the command's name")
    func describesRefusals() {
        #expect(OptionError.unknownOption("--bogus").description == "unknown option '--bogus'")
        #expect(OptionError.missingValue("--format").description == "option '--format' needs a value")
        #expect(OptionError.unexpectedValue("--rename").description == "option '--rename' takes no value")
    }
}
