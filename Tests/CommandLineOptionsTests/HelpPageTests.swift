//
//  HelpPageTests.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

import Testing
import CommandLineOptions

/// The layout is ArgumentParser's, so the expected pages are ArgumentParser's own output: realdate
/// 1.3.0 and mail2md 1.3.1, both built on it, printed with `COLUMNS` set (2026-10-18). A page
/// derived from `HelpPage` itself would only prove the derivation. The same comparison ran
/// outside the suite at ten widths from 30 to 201 columns, all byte for byte.
@Suite("Help Page")
struct HelpPageTests {

    /// realdate's help as 1.3.0 printed it, the last version on ArgumentParser.
    private let realdate = HelpPage(
        overview: "Extract date from filename prefix, set file timestamps, and remove date from filename.",
        usage: "realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>",
        sections: [
            HelpPage.Section("ARGUMENTS", [
                HelpPage.Entry("<path>", "Path to file(s) or directory."),
            ]),
            HelpPage.Section("OPTIONS", [
                HelpPage.Entry("--format <format>", "Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd, yyyy-MM-dd-HH-mm). (default: yyyy.MM.dd.HH.mm, yyyy.MM.dd)"),
                HelpPage.Entry("-r, --recursive", "Search recursively in subdirectories."),
                HelpPage.Entry("-v, --verbose", "Show detailed information."),
                HelpPage.Entry("--rename", "Set timestamps, and rename files."),
                HelpPage.Entry("-d, --directories", "Treat a directory itself as an item: set its timestamps, and rename it with --rename. Applies to the given directory, and to every visited subdirectory with -r."),
                HelpPage.Entry("--version", "Show the version."),
                HelpPage.Entry("-h, --help", "Show help information."),
            ]),
        ]
    )

    /// mail2md's help as 1.3.1 printed it, for the labels too long for their column.
    private let mail2md = HelpPage(
        overview: "Convert .eml files to Markdown with YAML frontmatter.",
        usage: "mail2md [--output <output>] [--verbose] [--force] [--extract-attachments] [--attachments-dir <attachments-dir>] [--attachment-name <attachment-name>] [--inline-images] <path>",
        sections: [
            HelpPage.Section("ARGUMENTS", [
                HelpPage.Entry("<path>", "Path to an .eml file."),
            ]),
            HelpPage.Section("OPTIONS", [
                HelpPage.Entry("-o, --output <output>", "Output file path. Defaults to the input path with .md extension."),
                HelpPage.Entry("-v, --verbose", "Show detailed information."),
                HelpPage.Entry("-f, --force", "Overwrite existing output files that differ from the generated Markdown."),
                HelpPage.Entry("--extract-attachments", "Write attachment files (next to the output, or into --attachments-dir) and link them from the note."),
                HelpPage.Entry("--attachments-dir <attachments-dir>", "Directory for extracted attachments; implies --extract-attachments. Defaults next to the output."),
                HelpPage.Entry("--attachment-name <attachment-name>", "Rename extracted attachments after a pattern, e.g. \"{date} {time} ENCL {name}\"; placeholders are {name}, {ext}, {date} and {time}, the latter two with an optional format ({date:yyyy.MM.dd}). Implies --extract-attachments."),
                HelpPage.Entry("--inline-images", "Write the pictures the mail shows from its own parts (cid:) as files too, and embed each where it stands. Implies --extract-attachments."),
                HelpPage.Entry("--version", "Show the version."),
                HelpPage.Entry("-h, --help", "Show help information."),
            ]),
        ]
    )

    @Test("Lays a page out as ArgumentParser did, at 80 columns")
    func matchesAt80Columns() {
        #expect(self.realdate.rendered(width: 80) == """
            OVERVIEW: Extract date from filename prefix, set file timestamps, and remove
            date from filename.

            USAGE: realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>

            ARGUMENTS:
              <path>                  Path to file(s) or directory.

            OPTIONS:
              --format <format>       Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd,
                                      yyyy-MM-dd-HH-mm). (default: yyyy.MM.dd.HH.mm,
                                      yyyy.MM.dd)
              -r, --recursive         Search recursively in subdirectories.
              -v, --verbose           Show detailed information.
              --rename                Set timestamps, and rename files.
              -d, --directories       Treat a directory itself as an item: set its
                                      timestamps, and rename it with --rename. Applies to
                                      the given directory, and to every visited
                                      subdirectory with -r.
              --version               Show the version.
              -h, --help              Show help information.

            """)
    }

    @Test("Uses the whole width of a wide window")
    func matchesAt120Columns() {
        #expect(self.realdate.rendered(width: 120) == """
            OVERVIEW: Extract date from filename prefix, set file timestamps, and remove date from filename.

            USAGE: realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>

            ARGUMENTS:
              <path>                  Path to file(s) or directory.

            OPTIONS:
              --format <format>       Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd, yyyy-MM-dd-HH-mm). (default:
                                      yyyy.MM.dd.HH.mm, yyyy.MM.dd)
              -r, --recursive         Search recursively in subdirectories.
              -v, --verbose           Show detailed information.
              --rename                Set timestamps, and rename files.
              -d, --directories       Treat a directory itself as an item: set its timestamps, and rename it with --rename. Applies
                                      to the given directory, and to every visited subdirectory with -r.
              --version               Show the version.
              -h, --help              Show help information.

            """)
    }

    @Test("Keeps the description column in a narrow window, a word wider than it on a line of its own")
    func matchesAt40Columns() {
        #expect(self.realdate.rendered(width: 40) == """
            OVERVIEW: Extract date from filename
            prefix, set file timestamps, and remove
            date from filename.

            USAGE: realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>

            ARGUMENTS:
              <path>                  Path to
                                      file(s) or
                                      directory.

            OPTIONS:
              --format <format>       Date custom
                                      format (e.g.
                                      dd-MM-yyyy,
                                      yyyy-MM-dd,
                                      yyyy-MM-dd-HH-mm).
                                      (default:
                                      yyyy.MM.dd.HH.mm,
                                      yyyy.MM.dd)
              -r, --recursive         Search
                                      recursively
                                      in
                                      subdirectories.
              -v, --verbose           Show detailed
                                      information.
              --rename                Set
                                      timestamps,
                                      and rename
                                      files.
              -d, --directories       Treat a
                                      directory
                                      itself as an
                                      item: set its
                                      timestamps,
                                      and rename it
                                      with
                                      --rename.
                                      Applies to
                                      the given
                                      directory,
                                      and to every
                                      visited
                                      subdirectory
                                      with -r.
              --version               Show the
                                      version.
              -h, --help              Show help
                                      information.

            """)
    }

    @Test("Puts the description of a label too long for its column on the next line")
    func movesDescriptionBelowLongLabel() {
        #expect(self.mail2md.rendered(width: 80) == """
            OVERVIEW: Convert .eml files to Markdown with YAML frontmatter.

            USAGE: mail2md [--output <output>] [--verbose] [--force] [--extract-attachments] [--attachments-dir <attachments-dir>] [--attachment-name <attachment-name>] [--inline-images] <path>

            ARGUMENTS:
              <path>                  Path to an .eml file.

            OPTIONS:
              -o, --output <output>   Output file path. Defaults to the input path with .md
                                      extension.
              -v, --verbose           Show detailed information.
              -f, --force             Overwrite existing output files that differ from the
                                      generated Markdown.
              --extract-attachments   Write attachment files (next to the output, or into
                                      --attachments-dir) and link them from the note.
              --attachments-dir <attachments-dir>
                                      Directory for extracted attachments; implies
                                      --extract-attachments. Defaults next to the output.
              --attachment-name <attachment-name>
                                      Rename extracted attachments after a pattern, e.g.
                                      "{date} {time} ENCL {name}"; placeholders are {name},
                                      {ext}, {date} and {time}, the latter two with an
                                      optional format ({date:yyyy.MM.dd}). Implies
                                      --extract-attachments.
              --inline-images         Write the pictures the mail shows from its own parts
                                      (cid:) as files too, and embed each where it stands.
                                      Implies --extract-attachments.
              --version               Show the version.
              -h, --help              Show help information.

            """)
    }
}
