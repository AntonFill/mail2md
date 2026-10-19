//
//  HelpPage.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

import Darwin

/// A help text in the layout ArgumentParser printed, wrapped to the window it is shown in.
///
/// BSD tools do not do this. `ssh` and `rm` print their usage hard-wrapped below 80 columns
/// whatever the window, and a narrower window folds those lines at its edge, without the
/// indent (measured 2026-10-18). ArgumentParser, which realdate and mail2md used before, wrapped
/// to the window instead, and this keeps that: the descriptions stay in their column at any
/// width. The rules are ArgumentParser's down to where a line breaks, so a page reads the same
/// as it did at every width.
public struct HelpPage: Sendable, Equatable {

    /// One row: a label such as `-r, --recursive`, and what it does.
    public struct Entry: Sendable, Equatable {
        public let label: String
        public let description: String

        public init(_ label: String, _ description: String) {
            self.label = label
            self.description = description
        }
    }

    /// A titled block of rows, such as `ARGUMENTS` or `OPTIONS`.
    public struct Section: Sendable, Equatable {
        public let title: String
        public let entries: [Entry]

        public init(_ title: String, _ entries: [Entry]) {
            self.title = title
            self.entries = entries
        }
    }

    public let overview: String
    public let usage: String
    public let sections: [Section]

    public init(overview: String, usage: String, sections: [Section]) {
        self.overview = overview
        self.usage = usage
        self.sections = sections
    }
}

// MARK: - Layout

extension HelpPage {

    /// The column a description starts in.
    static let descriptionColumn = 26
    /// How far a label is indented.
    static let labelIndent = 2

    /// The page laid out for a window `width` columns wide, ending in a newline.
    ///
    /// The usage line is never wrapped, as ArgumentParser left it. A label that does not fit
    /// in front of the description column puts its description on the next line.
    public func rendered(width: Int) -> String {
        let overview = "OVERVIEW: \(self.overview)".wrapped(to: width)
        let sections = self.sections.map { section in
            "\(section.title):\n" + section.entries.map({ Self.row($0, width: width) }).joined()
        }
        return overview + "\n\n" + "USAGE: \(self.usage)\n\n" + sections.joined(separator: "\n")
    }

    private static func row(_ entry: Entry, width: Int) -> String {
        let label = String(repeating: " ", count: Self.labelIndent) + entry.label
        let description = entry.description.wrapped(to: width, indent: Self.descriptionColumn)

        if label.count < Self.descriptionColumn {
            return label + description.dropFirst(label.count) + "\n"
        }
        else {
            return label + "\n" + description + "\n"
        }
    }
}

// MARK: - Window width

extension HelpPage {

    /// The width to lay a page out for: `COLUMNS` if the user set it, else the width of the
    /// window standard output goes to, else 80. The order ArgumentParser and `ls` use.
    public static var screenWidth: Int {
        if let columns = Self.columnsFromEnvironment {
            return columns
        }
        if let window = Self.windowWidth {
            return window
        }
        return 80
    }

    static var columnsFromEnvironment: Int? {
        guard let value = getenv("COLUMNS"),
              let columns = Int(String(cString: value)),
              columns > 0
        else {
            return nil
        }
        return columns
    }

    /// Nil when standard output is not a terminal, as in a pipe or a file.
    static var windowWidth: Int? {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0,
              size.ws_col > 0
        else {
            return nil
        }
        return Int(size.ws_col)
    }
}

// MARK: - Wrapping

extension String {

    /// ArgumentParser's wrapping, rule for rule, so a page breaks where it always did.
    ///
    /// A line ends at the last space within the width, so it stays shorter than the width; the
    /// remainder is kept whole once it fits; a word wider than the width gets a line of its own;
    /// and every line but an empty one starts with `indent` spaces.
    func wrapped(to width: Int, indent: Int = 0) -> String {
        // ArgumentParser prints nothing at all once the indent eats the width. One word per
        // line is still readable.
        let columns = Swift.max(1, width - indent)
        var lines: [Substring] = []
        var current = self.startIndex

        while true {
            let chunk = self[current...].prefix(columns)
            if let lineBreak = chunk.lastIndex(of: "\n") {
                lines.append(contentsOf: self[current..<lineBreak].split(separator: "\n", omittingEmptySubsequences: false))
                current = self.index(after: lineBreak)
            }
            else if chunk.endIndex == self.endIndex {
                lines.append(self[current...])
                break
            }
            else if let space = chunk.lastIndex(of: " ") {
                lines.append(self[current..<space])
                current = self.index(after: space)
            }
            else if let space = self[current...].firstIndex(of: " ") {
                lines.append(self[current..<space])
                current = self.index(after: space)
            }
            else {
                lines.append(self[current...])
                break
            }
        }

        let padding = String(repeating: " ", count: indent)
        return lines.map({ $0.isEmpty ? String($0) : padding + $0 }).joined(separator: "\n")
    }
}
