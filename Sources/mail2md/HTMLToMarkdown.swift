//
//  HTMLToMarkdown.swift
//  mail2md
//
//  Created by Anton Fillmann on 20.07.2026.
//

import Foundation
import SwiftSoup

/// Converts an HTML email body to Markdown.
///
/// It lays the body out the way a browser would, as far as Markdown can
/// follow: a `div` is a line, a `p` a paragraph, and the element's own style
/// decides where a browser leaves space. Lists, quotes, tables, rules and code
/// always stand apart. Hidden elements are dropped, images too, and so are
/// `script`, `style` and the like. A table holding data becomes a Markdown
/// table, one used for layout is taken apart into its cells.
///
/// The goal is readable, AI-ready Markdown, not a rendering: no fonts, no
/// colours, no stylesheet. The one rule taken from outside the element is a
/// rule about a known producer: Word zeroes the margins of its `Mso…`
/// paragraphs in a stylesheet, so an Outlook paragraph is a line.
enum HTMLToMarkdown {

    static func convert(_ html: String) -> String {
        guard let body = try? SwiftSoup.parse(html).body() else {
            return html
        }

        // Drop non-content nodes before walking the tree. If the selector fails,
        // script/style/img survive and their content would land silently in the
        // Markdown, so fall back to the raw HTML like the parse failure above:
        // unconverted output is visible, leaked stylesheet text is not.
        do {
            _ = try body
                .select("script, style, head, title, meta, link, noscript, img, svg")
                .remove()
        }
        catch {
            return html
        }

        var layout = Layout()
        self.renderChildren(of: body, into: &layout)
        return layout.markdown
    }
}

// MARK: - Tree walking
extension HTMLToMarkdown {

    /// Elements a browser lays out as blocks and this converter takes as lines,
    /// with the spacing their style gives them. `pre` and `table` are on the
    /// list for the cases in which they are layout rather than code or data.
    fileprivate static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "nav", "aside",
        "address", "center", "figure", "figcaption", "form", "fieldset", "details", "summary",
        "dl", "dt", "dd", "li", "table", "caption", "thead", "tbody", "tfoot", "tr", "td", "th", "pre",
    ]

    /// Blocks Markdown gives a syntax of their own. They always stand apart
    /// from the text around them by a blank line, whatever their margins: a
    /// line right after a list or a quote would be read into it, and a line
    /// right above `---` would turn into a heading.
    fileprivate static let structuralTags: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "hr",
    ]

    fileprivate static func renderChildren(of node: Node, into layout: inout Layout) {
        let children = node.getChildNodes()
        for child in children {
            self.render(child, into: &layout)
        }
    }

    fileprivate static func render(_ node: Node, into layout: inout Layout) {
        if let text = node as? TextNode {
            self.write(text.getWholeText(), into: &layout)
            return
        }
        guard let element = node as? Element else {
            return  // comments, data nodes, …
        }
        guard self.isHidden(element) == false else {
            return
        }

        let tag = element.tagName()
        switch tag {
        case "br":
            layout.lineBreak()
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            self.heading(element, level: level, into: &layout)
        case "strong", "b":
            self.emphasis(element, marker: "**", into: &layout)
        case "em", "i":
            self.emphasis(element, marker: "*", into: &layout)
        case "a":
            self.link(element, into: &layout)
        case "code":
            self.inlineCode(element, into: &layout)
        case "ul":
            self.list(element, ordered: false, into: &layout)
        case "ol":
            self.list(element, ordered: true, into: &layout)
        case "blockquote":
            self.quote(element, into: &layout)
        case "pre":
            self.preformatted(element, into: &layout)
        case "table":
            self.table(element, into: &layout)
        case "hr":
            layout.gap(2)
            layout.writeLines(["---"])
            layout.gap(2)
        default:
            if self.blockTags.contains(tag) {
                self.block(element, into: &layout)
            }
            else {
                self.renderChildren(of: element, into: &layout)  // span, font, o:p, … → unwrap
            }
        }
    }

    /// An element's content laid out on its own, for an element that has to
    /// see the whole of it before writing: a marker around it, a prefix before
    /// each line, a table cell to fit into one row.
    fileprivate static func content(of element: Element) -> Layout.Content {
        var inner = Layout()
        self.renderChildren(of: element, into: &inner)
        return inner.content
    }

    /// Text as a browser shows it: every run of whitespace one space, the
    /// no-break space included. A text that is nothing but whitespace only
    /// separates words, unless it holds a no-break space, which a browser does
    /// not collapse: a block holding nothing else still takes a line, and that
    /// is how Outlook writes an empty one.
    fileprivate static func write(_ raw: String, into layout: inout Layout) {
        let text = self.collapseWhitespace(raw)

        guard text.contains(where: { $0 != " " }) else {
            if text.isEmpty == false {
                layout.space(nonBreaking: raw.unicodeScalars.contains("\u{00A0}"))
            }
            return
        }
        layout.write(text)
    }
}

// MARK: - Blocks
extension HTMLToMarkdown {

    fileprivate static func block(_ element: Element, into layout: inout Layout) {
        let spacing = self.spacing(of: element)

        layout.gap(spacing.top)
        self.renderChildren(of: element, into: &layout)
        layout.gap(spacing.bottom)
    }

    fileprivate static func heading(_ element: Element, level: Int, into layout: inout Layout) {
        let text = self.content(of: element).flattened
        guard text.isEmpty == false else {
            return
        }

        layout.gap(2)
        layout.writeLines([String(repeating: "#", count: level) + " " + text])
        layout.gap(2)
    }

    /// A list, one line per item. A nested list is folded into its item's
    /// line, and anything a sloppy mailer put between the items is kept as a
    /// line of its own rather than dropped.
    fileprivate static func list(_ element: Element, ordered: Bool, into layout: inout Layout) {
        var lines: [String] = []
        var number = 1

        let children = element.getChildNodes()
        for child in children {
            if let text = child as? TextNode {
                let line = self.collapseWhitespace(text.getWholeText()).trimmingSpaces
                if line.isEmpty == false {
                    lines.append(line)
                }
                continue
            }
            guard
                let item = child as? Element,
                self.isHidden(item) == false
            else {
                continue
            }

            let line = self.content(of: item).flattened
            guard line.isEmpty == false else {
                continue
            }
            guard item.tagName() == "li" else {
                lines.append(line)
                continue
            }

            let marker = ordered ? "\(number). " : "- "
            lines.append(marker + line)
            number += 1
        }

        guard lines.isEmpty == false else {
            return
        }
        layout.gap(2)
        layout.writeLines(lines)
        layout.gap(2)
    }

    fileprivate static func quote(_ element: Element, into layout: inout Layout) {
        let lines = self.content(of: element).trimmedLines
        guard lines.isEmpty == false else {
            return
        }

        layout.gap(2)
        layout.writeLines(lines.map { $0.isEmpty ? ">" : "> " + $0 })
        layout.gap(2)
    }

    /// Code, kept character for character in a fence: its lines, its
    /// indentation, its blank lines. A `pre` holding blocks is no code but
    /// layout, as when a recruiting system wraps a whole letter in one, so it
    /// is read like a `div`.
    fileprivate static func preformatted(_ element: Element, into layout: inout Layout) {
        guard self.holdsBlocks(element) == false else {
            self.block(element, into: &layout)
            return
        }

        let text = self.verbatimText(of: element)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.allSatisfy({ $0.isWhitespace }) {
            lines.removeFirst()
        }
        while let last = lines.last, last.allSatisfy({ $0.isWhitespace }) {
            lines.removeLast()
        }
        guard lines.isEmpty == false else {
            return
        }

        // A fence ends at the first run of backticks at least as long as the
        // one that opened it, so it has to outgrow every run inside the code.
        let fence = String(repeating: "`", count: max(3, self.longestBacktickRun(in: text) + 1))

        layout.gap(2)
        layout.writeLines([fence] + lines + [fence])
        layout.gap(2)
    }
}

// MARK: - Inline elements
extension HTMLToMarkdown {

    fileprivate static func emphasis(_ element: Element, marker: String, into layout: inout Layout) {
        let content = self.content(of: element)

        layout.place(content) { line in
            return marker + line + marker
        }
    }

    /// A link as `[text](href)`, its text on one line. A link whose text is
    /// its own address, give or take the scheme and a closing slash, is
    /// written as that text: Outlook links every address it prints, and the
    /// Markdown link would show it twice.
    fileprivate static func link(_ element: Element, into layout: inout Layout) {
        let content = self.content(of: element)
        let href = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = content.flattened

        guard
            href.isEmpty == false,
            text.isEmpty == false,
            self.address(text) != self.address(href)
        else {
            layout.place(content) { line in
                return line
            }
            return
        }

        layout.place(content.onOneLine) { line in
            return "[\(line)](\(href))"
        }
    }

    fileprivate static func inlineCode(_ element: Element, into layout: inout Layout) {
        let content = self.content(of: element)
        let delimiter = content.flattened.contains("`") ? "``" : "`"

        layout.place(content.onOneLine) { line in
            return delimiter == "`" ? "`\(line)`" : "`` \(line) ``"
        }
    }
}

// MARK: - Tables
extension HTMLToMarkdown {

    /// One cell of a data table.
    fileprivate struct Cell {
        let lines: [String]
        let isHeader: Bool
        let span: Int

        var isEmpty: Bool {
            return self.lines.isEmpty
        }

        /// The cell's text for one row of a Markdown table: the pipe escaped,
        /// line breaks as `<br>`, bold where a header cell stands in a body row.
        func markdown(bold: Bool) -> String {
            let escaped = self.lines.map { $0.replacingOccurrences(of: "|", with: "\\|") }
            let marked = bold ? escaped.map { HTMLToMarkdown.bold($0) } : escaped
            return marked.joined(separator: "<br>")
        }
    }

    /// A table holding data becomes a Markdown table. Any other table is
    /// layout and is read cell by cell, each cell a block, so two cells never
    /// run into each other even where minified HTML has nothing between them.
    fileprivate static func table(_ element: Element, into layout: inout Layout) {
        guard let rows = self.dataRows(of: element) else {
            self.block(element, into: &layout)
            return
        }

        let caption = element.children().array().first { $0.tagName() == "caption" }
        if let caption {
            layout.gap(2)
            layout.writeLines(self.content(of: caption).trimmedLines)
            layout.gap(2)
        }

        // Columns that are empty in every row drop out, the spacer columns of
        // a layout grid above all. Spanning rows do not count, they leave the
        // table.
        let width = rows.map { self.width(of: $0) }.max() ?? 0
        let bodyGrid = rows.filter { self.isSpanning($0) == false }.map { self.expanded($0, to: width) }
        let columns = (0..<width).filter { column in
            return bodyGrid.contains { $0[column]?.isEmpty == false }
        }

        var section: [[Cell?]] = []
        for row in rows {
            // A row whose only cell spans the table captions the rows below
            // it: it stands above them, and the table is split there.
            guard self.isSpanning(row) == false else {
                self.writeTableSection(section, columns: columns, into: &layout)
                section = []

                let heading = row[0].lines.map { row[0].isHeader ? self.bold($0) : $0 }
                layout.gap(2)
                layout.writeLines(heading)
                layout.gap(2)
                continue
            }
            section.append(self.expanded(row, to: width))
        }
        self.writeTableSection(section, columns: columns, into: &layout)
    }

    /// The rows of a data table, or nil for a layout table.
    ///
    /// A table holds data when it is not marked as presentation, holds no
    /// table itself, and has at least one row with two filled cells. The last
    /// test runs on the rendered cells, so a logo beside a signature, an empty
    /// cell once the image is gone, does not make a table of data. Rows without
    /// any text are left out, the spacer rows of a layout grid.
    fileprivate static func dataRows(of table: Element) -> [[Cell]]? {
        let role = ((try? table.attr("role")) ?? "").lowercased()
        guard
            role != "presentation",
            self.holdsTable(table) == false
        else {
            return nil
        }

        var rows: [[Cell]] = []
        let rowElements = self.rowElements(of: table)
        for row in rowElements where self.isHidden(row) == false {
            let isHeaderRow = row.parent()?.tagName() == "thead"
            let cellElements = row.children().array().filter { ["td", "th"].contains($0.tagName()) && self.isHidden($0) == false }

            let cells = cellElements.map { cell in
                let span = Int(((try? cell.attr("colspan")) ?? "").trimmingCharacters(in: .whitespaces)) ?? 1
                return Cell(
                    lines: self.content(of: cell).trimmedLines.filter { $0.isEmpty == false },
                    isHeader: isHeaderRow || cell.tagName() == "th",
                    span: max(1, span)
                )
            }
            if cells.contains(where: { $0.isEmpty == false }) {
                rows.append(cells)
            }
        }

        let holdsData = rows.contains { row in
            return row.filter { $0.isEmpty == false }.count >= 2
        }
        return holdsData ? rows : nil
    }

    /// A section of a data table, between two spanning rows. Its first row is
    /// the header when it consists of header cells; otherwise the header stays
    /// empty, since Markdown cannot write a table without one.
    fileprivate static func writeTableSection(_ section: [[Cell?]], columns: [Int], into layout: inout Layout) {
        guard section.isEmpty == false, columns.isEmpty == false else {
            return
        }

        var rows = section
        var header = Array(repeating: "", count: columns.count)
        let first = rows[0].compactMap { $0 }
        if first.allSatisfy({ $0.isHeader }) {
            header = columns.map { rows[0][$0]?.markdown(bold: false) ?? "" }
            rows.removeFirst()
        }

        var lines = [self.tableRow(header), "|" + Array(repeating: "---", count: columns.count).joined(separator: "|") + "|"]
        for row in rows {
            let cells = columns.map { column in
                return row[column].map { $0.markdown(bold: $0.isHeader) } ?? ""
            }
            lines.append(self.tableRow(cells))
        }

        layout.gap(2)
        layout.writeLines(lines)
        layout.gap(2)
    }

    fileprivate static func tableRow(_ cells: [String]) -> String {
        return "| " + cells.joined(separator: " | ") + " |"
    }

    /// The rows of a table, with those inside `thead`, `tbody` and `tfoot`,
    /// in document order. Rows of a nested table are not among them.
    fileprivate static func rowElements(of table: Element) -> [Element] {
        var rows: [Element] = []

        let children = table.children().array()
        for child in children {
            switch child.tagName() {
            case "tr":
                rows.append(child)
            case "thead", "tbody", "tfoot":
                rows += child.children().array().filter { $0.tagName() == "tr" }
            default:
                break
            }
        }

        return rows
    }

    fileprivate static func width(of row: [Cell]) -> Int {
        return row.reduce(0) { $0 + $1.span }
    }

    /// A row as one slot per column: a cell where it starts, nil where a span
    /// covers the column or the row ends early.
    fileprivate static func expanded(_ row: [Cell], to width: Int) -> [Cell?] {
        var slots: [Cell?] = []
        for cell in row {
            slots.append(cell)
            slots += Array(repeating: nil, count: cell.span - 1)
        }
        return slots + Array(repeating: nil, count: max(0, width - slots.count))
    }

    fileprivate static func isSpanning(_ row: [Cell]) -> Bool {
        return row.count == 1 && row[0].span > 1
    }
}

// MARK: - Style
extension HTMLToMarkdown {

    /// Whether a browser would show the element at all. Only what the browser
    /// hides is dropped: `display:none`, `visibility:hidden`, the attribute
    /// `hidden`, and React Email's marker for its preview text.
    ///
    /// `mso-hide:all` is not among them. It hides an element from Outlook
    /// alone, which shows a twin from a conditional comment instead, so every
    /// other client shows it; in the archive it hides a button that way.
    fileprivate static func isHidden(_ element: Element) -> Bool {
        if element.hasAttr("hidden") {
            return true
        }
        let skipInText = ((try? element.attr("data-skip-in-text")) ?? "").lowercased()
        if element.hasAttr("data-skip-in-text") && skipInText != "false" {
            return true
        }

        let style = self.declarations(of: element)
        return style["display"] == "none" || style["visibility"] == "hidden"
    }

    /// The gap above and below a block, a line break (1) or a blank line (2).
    ///
    /// A blank line stands where a browser leaves visible space, from 3pt up,
    /// and margin and padding both leave it: React Email zeroes its margins
    /// and spaces its paragraphs with padding. Without a style, a `p` has the
    /// browser's margin of one line above and below and every other block
    /// none. Outlook's `Mso…` paragraphs are the exception, because Word
    /// zeroes their margins in a stylesheet this converter does not read.
    ///
    /// The rule replaces a mapping by tag, after counting the archive on
    /// 2026-10-02: 656 of 2285 plain paragraphs had no margin, and 321 of 8296
    /// Outlook paragraphs did.
    fileprivate static func spacing(of element: Element) -> (top: Int, bottom: Int) {
        let classes = ((try? element.className()) ?? "").split(separator: " ")
        let isParagraph = element.tagName() == "p"
        let isWordParagraph = isParagraph && classes.contains { $0.hasPrefix("Mso") }
        let defaultMargin = (isParagraph && isWordParagraph == false) ? 12.0 : 0.0

        let box = self.box(self.declarations(of: element))
        let top = (box.marginTop ?? defaultMargin) + (box.paddingTop ?? 0)
        let bottom = (box.marginBottom ?? defaultMargin) + (box.paddingBottom ?? 0)

        return (top >= 3 ? 2 : 1, bottom >= 3 ? 2 : 1)
    }

    /// The element's inline style as lowercased declarations, `!important`
    /// removed, later declarations winning.
    fileprivate static func declarations(of element: Element) -> [String: String] {
        guard
            let style = try? element.attr("style"),
            style.isEmpty == false
        else {
            return [:]
        }

        var declarations: [String: String] = [:]
        let parts = style.split(separator: ";")
        for part in parts {
            let pair = part.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else {
                continue
            }

            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair[1]
                .lowercased()
                .replacingOccurrences(of: "!important", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            declarations[name] = value
        }

        return declarations
    }

    /// The vertical margins and paddings a style sets, in points, from the
    /// shorthands and the longhands in the order they were declared. Nil where
    /// the style says nothing.
    fileprivate static func box(_ declarations: [String: String]) -> (marginTop: Double?, marginBottom: Double?, paddingTop: Double?, paddingBottom: Double?) {
        var margin = self.verticalSides(declarations["margin"])
        var padding = self.verticalSides(declarations["padding"])

        if let value = declarations["margin-top"] {
            margin.top = self.points(value)
        }
        if let value = declarations["margin-bottom"] {
            margin.bottom = self.points(value)
        }
        if let value = declarations["padding-top"] {
            padding.top = self.points(value)
        }
        if let value = declarations["padding-bottom"] {
            padding.bottom = self.points(value)
        }

        return (margin.top, margin.bottom, padding.top, padding.bottom)
    }

    /// Top and bottom of a `margin` or `padding` shorthand: one value is all
    /// four sides, two are vertical and horizontal, three and four start with
    /// the top and give the bottom third.
    fileprivate static func verticalSides(_ shorthand: String?) -> (top: Double?, bottom: Double?) {
        guard
            let values = shorthand?.split(whereSeparator: { $0.isWhitespace }).map(String.init),
            values.isEmpty == false
        else {
            return (nil, nil)
        }

        let top = self.points(values[0])
        let bottom = values.count >= 3 ? self.points(values[2]) : top
        return (top, bottom)
    }

    /// A CSS length in points, with an `em` taken as 12pt, the size of mail
    /// text. Nil for what cannot be read.
    fileprivate static func points(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed == "auto" {
            return 0
        }

        let units: [(suffix: String, factor: Double)] = [
            ("rem", 12), ("em", 12), ("px", 0.75), ("pt", 1), ("pc", 12),
            ("cm", 28.35), ("mm", 2.835), ("in", 72), ("%", 0),
        ]
        for unit in units where trimmed.hasSuffix(unit.suffix) {
            return Double(trimmed.dropLast(unit.suffix.count)).map { $0 * unit.factor }
        }

        return Double(trimmed).map { $0 * 0.75 }  // a unitless number is pixels
    }
}

// MARK: - Helpers
extension HTMLToMarkdown {

    /// Collapses every run of whitespace to one space, the no-break space
    /// included. Works on Unicode scalars, so a zero-width character next to a
    /// space survives for the invisible-character rule to count.
    fileprivate static func collapseWhitespace(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false

        let scalars = text.unicodeScalars
        for scalar in scalars {
            if scalar.properties.isWhitespace {
                pendingSpace = true
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(scalar)
        }
        if pendingSpace {
            result.append(" ")
        }

        return String(result)
    }

    /// The text of a `pre` as it stands, `br` as a line break, hidden parts
    /// left out.
    fileprivate static func verbatimText(of node: Node) -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        guard let element = node as? Element else {
            return ""
        }
        if element.tagName() == "br" {
            return "\n"
        }
        guard self.isHidden(element) == false else {
            return ""
        }
        return element.getChildNodes().map { self.verbatimText(of: $0) }.joined()
    }

    fileprivate static func holdsBlocks(_ element: Element) -> Bool {
        let tags = self.blockTags.union(self.structuralTags)
        return element.children().array().contains { child in
            return tags.contains(child.tagName()) || self.holdsBlocks(child)
        }
    }

    fileprivate static func holdsTable(_ element: Element) -> Bool {
        return element.children().array().contains { child in
            return child.tagName() == "table" || self.holdsTable(child)
        }
    }

    fileprivate static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// An address as a reader compares it: without its scheme, without a
    /// closing slash, in any case.
    fileprivate static func address(_ text: String) -> String {
        var address = text.lowercased()
        let schemes = ["https://", "http://", "mailto:"]
        for scheme in schemes where address.hasPrefix(scheme) {
            address.removeFirst(scheme.count)
        }
        if address.hasSuffix("/") {
            address.removeLast()
        }
        return address
    }

    /// Bold, unless the text already is.
    fileprivate static func bold(_ text: String) -> String {
        guard text.hasPrefix("**") == false || text.hasSuffix("**") == false else {
            return text
        }
        return "**" + text + "**"
    }
}

// MARK: - Layout

/// The Markdown being written, line by line.
///
/// Blocks do not write blank lines themselves. They ask for a gap before and
/// after them, a line break (1) or a blank line (2), and gaps that meet merge
/// into the larger one, the way a browser collapses adjoining margins. A gap is
/// only written once something follows it, so nothing piles up at the edges or
/// between two empty blocks.
fileprivate struct Layout {

    /// A block laid out on its own, for an element to wrap, prefix or flatten.
    struct Content {
        /// Its lines, the last one the line it ended on: empty where it ended
        /// with a line break.
        let lines: [String]
        let gapBefore: Int
        let gapAfter: Int
        let spaceBefore: Bool
        let spaceAfter: Bool

        /// Whether its last line holds something without text, a no-break
        /// space.
        let endsOccupied: Bool

        /// The lines without blank ones at either end.
        var trimmedLines: [String] {
            var lines = self.lines
            while lines.first?.isEmpty == true {
                lines.removeFirst()
            }
            while lines.last?.isEmpty == true {
                lines.removeLast()
            }
            return lines
        }

        /// All text on one line, for a heading, a list item, a link.
        var flattened: String {
            return self.lines.filter { $0.isEmpty == false }.joined(separator: " ")
        }

        /// The same content with its text on one line, keeping a line break at
        /// either end: a link can hold a `br`, Markdown's link text cannot.
        var onOneLine: Content {
            let text = self.flattened
            var lines = text.isEmpty ? [] : [text]
            if self.lines.count > 1, self.lines.first?.isEmpty == true {
                lines.insert("", at: 0)
            }
            if self.lines.count > 1, self.lines.last?.isEmpty == true {
                lines.append("")
            }

            return Content(
                lines: lines,
                gapBefore: self.gapBefore,
                gapAfter: self.gapAfter,
                spaceBefore: self.spaceBefore,
                spaceAfter: self.spaceAfter,
                endsOccupied: self.endsOccupied && text.isEmpty
            )
        }
    }

    private var lines: [String] = []
    private var current = ""

    /// The current line holds something, if only a no-break space.
    private var occupied = false

    /// Anything has been written at all; a gap before that is no gap.
    private var started = false

    /// The last thing written was a line break.
    private var brokeLine = false

    private var pendingGap = 0
    private var leadingGap = 0
    private var leadingSpace = false

    var markdown: String {
        var lines = self.lines
        if self.occupied {
            lines.append(self.current.trimmingSpaces)
        }
        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    var content: Content {
        var lines = self.lines
        if self.occupied || self.brokeLine {
            lines.append(self.current.trimmingSpaces)
        }

        return Content(
            lines: lines,
            gapBefore: self.leadingGap,
            gapAfter: self.pendingGap,
            spaceBefore: self.leadingSpace,
            spaceAfter: self.pendingGap == 0 && self.current.hasSuffix(" "),
            endsOccupied: self.occupied && self.current.trimmingSpaces.isEmpty
        )
    }

    mutating func gap(_ size: Int) {
        if self.started == false {
            self.leadingGap = max(self.leadingGap, size)
        }
        self.pendingGap = max(self.pendingGap, size)
    }

    /// Inline text, its whitespace already collapsed.
    mutating func write(_ text: String) {
        self.settle()

        var piece = Substring(text)
        if self.current.isEmpty || self.current.hasSuffix(" ") {
            let stripped = piece.drop { $0 == " " }
            if self.started == false, stripped.count < piece.count {
                self.leadingSpace = true
            }
            piece = stripped
        }
        guard piece.isEmpty == false else {
            return
        }

        self.current += piece
        self.occupied = true
        self.started = true
        self.brokeLine = false
    }

    /// The space between two words. At the start of a line or before a gap it
    /// is nothing, unless it is a no-break space: that one holds an otherwise
    /// empty line open.
    mutating func space(nonBreaking: Bool = false) {
        if self.started == false {
            self.leadingSpace = true
        }
        if self.pendingGap == 0, self.current.isEmpty == false {
            if self.current.hasSuffix(" ") == false {
                self.current += " "
            }
            return
        }
        if nonBreaking {
            self.settle()
            self.occupied = true
            self.started = true
            self.brokeLine = false
        }
    }

    /// Ends the current line where a `br` stands, an empty one included.
    mutating func lineBreak() {
        self.settle()
        self.commit()
        self.started = true
        self.brokeLine = true
    }

    /// Lines that a block has formatted itself, written as they are: a list, a
    /// quote, a table, a code fence.
    mutating func writeLines(_ block: [String]) {
        guard block.isEmpty == false else {
            return
        }

        self.settle()
        if self.occupied {
            self.commit()
        }
        self.lines.append(contentsOf: block)
        self.started = true
        self.brokeLine = false
    }

    /// Writes content laid out on its own, each line of text passed through
    /// `transform`, with the gaps, spaces and line breaks it had at its edges.
    mutating func place(_ content: Content, transform: (String) -> String) {
        if content.gapBefore > 0 {
            self.gap(content.gapBefore)
        }
        else if content.spaceBefore {
            self.space()
        }

        let lines = content.lines.enumerated()
        for (index, line) in lines {
            if index > 0 {
                self.lineBreak()
            }
            if line.isEmpty == false {
                self.write(transform(line))
            }
        }
        if content.endsOccupied {
            self.space(nonBreaking: true)
        }

        if content.gapAfter > 0 {
            self.gap(content.gapAfter)
        }
        else if content.spaceAfter {
            self.space()
        }
    }

    /// Writes the pending gap, now that something follows it.
    private mutating func settle() {
        let gap = self.pendingGap
        self.pendingGap = 0
        guard
            self.started,
            gap > 0
        else {
            return
        }

        if self.occupied {
            self.commit()
        }
        if gap == 2, self.lines.last?.isEmpty == false {
            self.lines.append("")
        }
    }

    /// Moves the current line into the finished ones. One blank line is all
    /// Markdown shows, so an empty line after an empty line is dropped.
    private mutating func commit() {
        let line = self.current.trimmingSpaces
        if line.isEmpty == false || self.lines.last?.isEmpty != true {
            self.lines.append(line)
        }
        self.current = ""
        self.occupied = false
    }
}

// MARK: -
extension String {

    /// Without the spaces at either end, and only spaces: Foundation's
    /// whitespace set also holds the zero-width space, which has to reach the
    /// invisible-character rule to be counted. The emitter's lines hold no
    /// other whitespace once it is collapsed.
    fileprivate var trimmingSpaces: String {
        let start = self.firstIndex { $0 != " " } ?? self.endIndex
        let end = self.lastIndex { $0 != " " }.map { self.index(after: $0) } ?? start
        return String(self[start..<end])
    }
}
