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
/// always stand apart. Hidden elements are dropped, and so are `script`,
/// `style` and the like. A table holding data becomes a Markdown table, one
/// used for layout is taken apart into its rows, whose cells share a line
/// where a browser shows them side by side.
///
/// Pictures are dropped, except a picture of an emoji, written as the emoji,
/// and a picture from a part of the mail whose file the caller names, which
/// is embedded in its place. Each picture from the mail that a reader would
/// see is handed back, so the run can name what the note leaves out.
///
/// A box the mail sets apart, framed or on a colour of its own, stays apart
/// where it is a card, between rules or as an Obsidian callout, and a button
/// in light text on a dark colour is bold. Colours count for nothing else.
///
/// The goal is readable, AI-ready Markdown, not a rendering: no fonts, no
/// stylesheet. The two rules taken from outside the element are rules about
/// a known producer: Word zeroes the margins of its `Mso…` paragraphs in a
/// stylesheet, so an Outlook paragraph is a line, and MJML sets the widths of
/// its columns there, so its class names say which stand side by side.
enum HTMLToMarkdown {

    static func convert(_ html: String, format: OutputFormat = .markdown) -> String {
        return self.convert(html, imageNames: [:], format: format).markdown
    }

    /// The Markdown, and the pictures from parts of the mail it shows, in
    /// document order.
    ///
    /// `imageNames` holds the file each picture was written to, by the
    /// `Content-ID` its `cid:` address names. Such a picture is embedded where
    /// the `img` stood; every other one is left out, as it always was.
    /// `format` says how a box the mail sets apart is written.
    static func convert(_ html: String, imageNames: [String: String], format: OutputFormat = .markdown) -> (markdown: String, images: [InlineImage]) {
        guard let body = try? SwiftSoup.parse(self.joiningSurrogateHalves(html)).body() else {
            return (html, [])
        }

        // Drop non-content nodes before walking the tree. If the selector fails,
        // script/style survive and their content would land silently in the
        // Markdown, so fall back to the raw HTML like the parse failure above:
        // unconverted output is visible, leaked stylesheet text is not.
        do {
            _ = try body
                .select("script, style, head, title, meta, link, noscript, svg")
                .remove()
            try self.markFiles(in: body, imageNames: imageNames)
            try self.markBoxes(in: body, format: format)
        }
        catch {
            return (html, [])
        }

        var layout = Layout()
        self.renderChildren(of: body, into: &layout)
        return (layout.markdown, self.shownImages(in: body))
    }
}

// MARK: - Pictures from the mail
extension HTMLToMarkdown {

    /// The attributes the walk passes pictures by. Before it, a picture whose
    /// file the caller named carries that name; during it, every picture from
    /// the mail the walk reaches is marked as shown, so that afterwards the
    /// tree itself says which ones a reader sees: not a hidden one, not one
    /// inside code. The walk is a tree of static calls, and the pictures are
    /// the one thing it hands back besides the text.
    fileprivate static let fileAttribute = "data-mail2md-file"
    fileprivate static let shownAttribute = "data-mail2md-shown"

    /// Clears the marks the mail's own HTML may bring along, so it cannot steer
    /// the walk, and names the file of every picture the caller wrote one for.
    fileprivate static func markFiles(in body: Element, imageNames: [String: String]) throws {
        let marked = try body.select("[\(self.fileAttribute)], [\(self.shownAttribute)]")
        for element in marked {
            try element.removeAttr(self.fileAttribute)
            try element.removeAttr(self.shownAttribute)
        }

        let pictures = try body.select("img")
        for picture in pictures {
            guard
                let contentID = self.contentID(of: picture),
                let file = imageNames[contentID]
            else {
                continue
            }
            try picture.attr(self.fileAttribute, file)
        }
    }

    /// The `Content-ID` a picture is addressed by, or nil for a picture from
    /// anywhere else. RFC 2392 writes it after `cid:`, its special characters
    /// percent-encoded.
    fileprivate static func contentID(of picture: Element) -> String? {
        let source = ((try? picture.attr("src")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.lowercased().hasPrefix("cid:") else {
            return nil
        }

        let address = String(source.dropFirst(4))
        let contentID = address.removingPercentEncoding ?? address
        return contentID.isEmpty ? nil : contentID
    }

    /// The file a picture is embedded from, where the caller wrote one for it.
    fileprivate static func file(of picture: Element) -> String? {
        guard
            let file = try? picture.attr(self.fileAttribute),
            file.isEmpty == false
        else {
            return nil
        }
        return file
    }

    /// The pictures from the mail the walk reached, in document order, with
    /// the size the HTML gives each.
    fileprivate static func shownImages(in body: Element) -> [InlineImage] {
        guard let pictures = try? body.select("img[\(self.shownAttribute)]") else {
            return []
        }

        return pictures.array().compactMap { picture in
            guard let contentID = self.contentID(of: picture) else {
                return nil
            }
            return InlineImage(
                contentID: contentID,
                width: self.declaredLength("width", of: picture),
                height: self.declaredLength("height", of: picture)
            )
        }
    }

    /// A side of a picture as the HTML gives it, in CSS pixels. The inline
    /// style wins over the attribute, as in a browser, also where it says
    /// something only the page around it can resolve.
    fileprivate static func declaredLength(_ side: String, of picture: Element) -> Int? {
        if let value = self.declarations(of: picture)[side] {
            return self.pixels(value)
        }
        return self.pixels((try? picture.attr(side)) ?? "")
    }

    /// A CSS length in pixels, or nil for nothing readable and for one that
    /// depends on the page around it, a percentage or `auto`, both of which
    /// `points` reads as nothing.
    fileprivate static func pixels(_ value: String) -> Int? {
        guard
            let points = self.points(value),
            points > 0
        else {
            return nil
        }
        return Int((points / 0.75).rounded())
    }

    /// A picture embedded from its file, its alt text as the alias where that
    /// says something about the picture (Anton's decision 1a, 2026-10-03).
    fileprivate static func embed(_ file: String, alt: String) -> String {
        guard let alias = self.alias(for: alt) else {
            return "![[\(file)]]"
        }
        return "![[\(file)|\(alias)]]"
    }

    /// The alt text on one line, or nil where it says nothing about the
    /// picture: empty, a file name, or Office's own description, which it
    /// writes in when the sender wrote none (its closing line in German or in
    /// English, measured in the archive and named by Microsoft's help on alt
    /// text). A number would set the picture's size in Obsidian, and a
    /// bracket or a pipe would break the embed.
    fileprivate static func alias(for alt: String) -> String? {
        let text = self.collapseWhitespace(alt).trimmingSpaces
        let lowercased = text.lowercased()
        let pictureExtensions = [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".tif", ".tiff", ".heic", ".svg"]
        let officeDescriptions = [
            "automatisch generierte beschreibung",
            "ki-generierte inhalte können fehlerhaft sein",
            "description automatically generated",
            "description generated with",
            "ai-generated content may be incorrect",
        ]

        guard
            text.isEmpty == false,
            pictureExtensions.contains(where: { lowercased.hasSuffix($0) }) == false,
            officeDescriptions.contains(where: { lowercased.contains($0) }) == false,
            text.wholeMatch(of: /[0-9]+(x[0-9]+)?/) == nil,
            text.contains(where: { "[]|".contains($0) }) == false
        else {
            return nil
        }
        return text
    }

    /// Whether a picture embedded from its file shows inside the element: one
    /// a browser does not hide, and no picture of an emoji, which stays text.
    fileprivate static func holdsEmbed(_ element: Element) -> Bool {
        return element.children().array().contains { child in
            guard self.isHidden(child) == false else {
                return false
            }
            let isEmbed = child.tagName() == "img" && self.file(of: child) != nil && self.isEmoji(child) == false
            return isEmbed || self.holdsEmbed(child)
        }
    }

    /// Whether a picture's alt text is nothing but emoji.
    fileprivate static func isEmoji(_ picture: Element) -> Bool {
        let alt = ((try? picture.attr("alt")) ?? "").trimmingCharacters(in: .whitespaces)
        return InvisibleCharacters.isEmoji(alt)
    }
}

// MARK: - Boxes
extension HTMLToMarkdown {

    /// The attributes the walk finds boxes by. A card that may be set apart
    /// carries the format to write it in, a button only the mark.
    fileprivate static let boxAttribute = "data-mail2md-box"
    fileprivate static let buttonAttribute = "data-mail2md-button"

    /// Marks the boxes a reader sees set apart, before the walk: a block
    /// framed on all four sides or on a background of its own, a colour that
    /// differs from the one behind it. Whether a box is a card or a button
    /// depends on what it holds, and that is decided where it is laid out.
    ///
    /// A card is the outermost box, never one inside another, and never the
    /// box holding the mail's last line, its footer (Anton's decision B,
    /// 2026-10-26). A mail that lays all its text on a panel of a colour of
    /// its own has that panel for its page, so the walk starts at the
    /// innermost element holding all of the text. A button is any box on a
    /// background of its own in light text on a darker colour.
    fileprivate static func markBoxes(in body: Element, format: OutputFormat) throws {
        let marked = try body.select("[\(self.boxAttribute)], [\(self.buttonAttribute)]")
        for element in marked {
            try element.removeAttr(self.boxAttribute)
            try element.removeAttr(self.buttonAttribute)
        }

        var page = body
        let bodyStyle = self.declarations(of: body)
        var background = self.background(of: body, style: bodyStyle) ?? Color.white
        var color = self.color(of: body, style: bodyStyle) ?? Color.black
        while true {
            let holders = page.getChildNodes().filter { self.showsText($0) }
            guard
                holders.count == 1,
                let only = holders.first as? Element
            else {
                break
            }
            page = only
            let style = self.declarations(of: only)
            background = self.background(of: only, style: style).map { $0.over(background) } ?? background
            color = self.color(of: only, style: style) ?? color
        }

        var footer = Set<ObjectIdentifier>()
        var ancestor = self.lastText(in: body)?.parent()
        while let element = ancestor {
            footer.insert(ObjectIdentifier(element))
            ancestor = element.parent()
        }

        try self.markBoxes(under: page, background: background, color: color, insideBox: false, footer: footer, format: format)
    }

    /// Columns MJML sets side by side are laid out as one, so a box inside
    /// one of them is no card either, as one inside another box is not.
    fileprivate static func markBoxes(under parent: Element, background: Color, color: Color, insideBox: Bool, footer: Set<ObjectIdentifier>, format: OutputFormat) throws {
        let insideBox = insideBox || self.holdsColumns(parent)
        let children = parent.children().array()
        for child in children {
            let style = self.declarations(of: child)
            guard self.isHidden(child, style: style) == false else {
                continue
            }

            let own = self.background(of: child, style: style).map { $0.over(background) }
            let behind = own ?? background
            let hasBackground = own.map { $0 != background } ?? false
            let isBox = self.blockTags.contains(child.tagName()) && (hasBackground || self.hasFrame(style)) && self.showsText(child)

            if isBox, insideBox == false, footer.contains(ObjectIdentifier(child)) == false {
                try child.attr(self.boxAttribute, format.rawValue)
            }
            if isBox,
               hasBackground,
               let foreground = self.textColor(in: child, inherited: color),
               foreground.luminance > behind.luminance {
                try child.attr(self.buttonAttribute, "")
            }

            let ink = self.color(of: child, style: style) ?? color
            try self.markBoxes(under: child, background: behind, color: ink, insideBox: insideBox || isBox, footer: footer, format: format)
        }
    }

    /// A box `markBoxes` marked, laid out on its own first. A card of more
    /// than one line under a title, a first line all in bold or a heading,
    /// is set apart from the text around it; a button of one line that is no
    /// link is bold; anything else is written as it would have been.
    fileprivate static func renderBox(_ element: Element, into layout: inout Layout) {
        var inner = Layout()
        self.renderEmphasized(element, into: &inner)
        let lines = inner.content.trimmedLines
        let filled = lines.filter { $0.isEmpty == false }

        if let format = OutputFormat(rawValue: (try? element.attr(self.boxAttribute)) ?? ""),
           filled.count >= 2,
           let title = self.title(of: lines[0]) {
            self.setApart(inner, lines: lines, title: title, format: format, into: &layout)
            return
        }
        if element.hasAttr(self.buttonAttribute),
           filled.count == 1,
           inner.holdsFormattedLines == false,
           self.holdsLink(element) == false {
            layout.place(inner.content) { line in
                return "**" + line.replacingOccurrences(of: "**", with: "") + "**"
            }
            return
        }
        layout.replay(inner.operations)
    }

    /// The title a card's first line gives it: the line where all of it is
    /// bold, without the markers, or a heading's text. Nil for any other line.
    fileprivate static func title(of line: String) -> String? {
        if let heading = line.wholeMatch(of: /#{1,6} (.+)/) {
            return String(heading.1)
        }
        guard
            line.count > 4,
            line.hasPrefix(self.boldMarker),
            line.hasSuffix(self.boldMarker)
        else {
            return nil
        }

        let text = line.dropFirst(2).dropLast(2)
        return text.contains(self.boldMarker) ? nil : String(text)
    }

    /// A card set apart from the text around it: in Obsidian's format a
    /// callout under its title, and in plain Markdown its lines as they are,
    /// between two rules.
    fileprivate static func setApart(_ card: Layout, lines: [String], title: String, format: OutputFormat, into layout: inout Layout) {
        switch format {
        case .obsidian:
            let body = self.headingFirstRow(Array(lines.dropFirst())).map { $0.isEmpty ? ">" : "> " + $0 }
            layout.gap(2)
            layout.writeLines(["> [!quote] " + title] + body)
            layout.gap(2)
        case .markdown:
            layout.gap(2)
            layout.rule()
            layout.gap(2)
            layout.replay(card.operations)
            layout.gap(2)
            layout.rule()
            layout.gap(2)
        }
    }

    /// A callout's body whose first block is a table under an empty header,
    /// the one Markdown needs where the mail gives none, with the table's
    /// first row in the header's place: right under the callout's title the
    /// empty header shows as an empty first row, and the title heads the
    /// table already (Anton's decision A, 2026-10-26). Any other body as it is.
    fileprivate static func headingFirstRow(_ body: [String]) -> [String] {
        guard
            let start = body.firstIndex(where: { $0.isEmpty == false }),
            body.count > start + 2,
            body[start].wholeMatch(of: /\|( +\|)+/) != nil,
            body[start + 1].wholeMatch(of: /\|(---\|)+/) != nil
        else {
            return body
        }

        var lines = body
        let separator = lines.remove(at: start + 1)
        lines.remove(at: start)
        lines.insert(separator, at: start + 1)
        return lines
    }

    /// Whether a node shows text a reader sees, more than whitespace.
    fileprivate static func showsText(_ node: Node) -> Bool {
        if let text = node as? TextNode {
            return text.getWholeText().unicodeScalars.contains { $0.properties.isWhitespace == false }
        }
        guard
            let element = node as? Element,
            self.isHidden(element) == false
        else {
            return false
        }
        return element.getChildNodes().contains { self.showsText($0) }
    }

    /// The last text a reader sees in a node.
    fileprivate static func lastText(in node: Node) -> TextNode? {
        if let text = node as? TextNode {
            return self.showsText(text) ? text : nil
        }
        guard
            let element = node as? Element,
            self.isHidden(element) == false
        else {
            return nil
        }

        let children = element.getChildNodes().reversed()
        for child in children {
            if let text = self.lastText(in: child) {
                return text
            }
        }
        return nil
    }

    /// The colour of the first text a reader sees in a node, the colour of
    /// the text around it unless an element on the way sets its own.
    fileprivate static func textColor(in node: Node, inherited: Color) -> Color? {
        if let text = node as? TextNode {
            return self.showsText(text) ? inherited : nil
        }
        guard let element = node as? Element else {
            return nil
        }
        let style = self.declarations(of: element)
        guard self.isHidden(element, style: style) == false else {
            return nil
        }

        let color = self.color(of: element, style: style) ?? inherited
        let children = element.getChildNodes()
        for child in children {
            if let found = self.textColor(in: child, inherited: color) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Columns
extension HTMLToMarkdown {

    /// The width MJML gives a column on a wide screen, in percent, read off
    /// its class, `mj-column-per-49`, a fraction with a dash for its point,
    /// `mj-column-per-33-333333333333336`. The width itself stands in a
    /// stylesheet, which this converter does not read. Nil for any other
    /// element.
    fileprivate static func columnWidth(of element: Element) -> Double? {
        let prefix = "mj-column-per-"
        let classes = ((try? element.className()) ?? "").split(separator: " ")
        for name in classes where name.hasPrefix(prefix) {
            return Double(name.dropFirst(prefix.count).replacingOccurrences(of: "-", with: "."))
        }
        return nil
    }

    /// Whether an element sets MJML columns side by side: two or more,
    /// together no wider than the screen, and nothing beside them a reader
    /// sees. Columns that each take the whole width stand one below the other.
    fileprivate static func holdsColumns(_ element: Element) -> Bool {
        let nodes = element.getChildNodes()
        let widths = nodes.compactMap { ($0 as? Element).flatMap { self.columnWidth(of: $0) } }
        guard
            widths.count >= 2,
            widths.reduce(0, +) <= 100.01
        else {
            return false
        }

        return nodes.allSatisfy { node in
            return (node as? Element).flatMap { self.columnWidth(of: $0) } != nil || self.showsText(node) == false
        }
    }

    /// Columns side by side, each laid out on its own. Where the columns
    /// showing text hold as many lines as each other, more than one, they
    /// pair up as a Markdown table (an insurer sets the old insurance beside
    /// the new one); otherwise they stand one below the other, replayed as if
    /// laid out in place.
    fileprivate static func columns(of element: Element, into layout: inout Layout) {
        var parts: [(node: Node, layout: Layout)] = []
        let children = element.getChildNodes()
        for child in children {
            var part = Layout()
            self.render(child, into: &part)
            parts.append((child, part))
        }

        let columns = parts
            .filter { ($0.node as? Element).flatMap { self.columnWidth(of: $0) } != nil }
            .map { $0.layout }
            .filter { $0.content.trimmedLines.isEmpty == false }
        guard let table = self.table(ofColumns: columns) else {
            for part in parts {
                layout.replay(part.layout.operations)
            }
            return
        }

        layout.gap(2)
        layout.writeLines(table)
        layout.gap(2)
    }

    /// The lines of the table columns of as many lines pair up into, or nil
    /// where they do not: fewer than two columns, a column holding a block
    /// Markdown marks, a single line each, or lines of different counts. The
    /// first lines are the header where each is all bold; otherwise the
    /// header stays empty, as over a table of data.
    fileprivate static func table(ofColumns columns: [Layout]) -> [String]? {
        let lines = columns.map { $0.content.trimmedLines.filter { $0.isEmpty == false } }
        guard
            columns.count >= 2,
            columns.allSatisfy({ $0.holdsFormattedLines == false }),
            let count = lines.first?.count,
            count >= 2,
            lines.allSatisfy({ $0.count == count })
        else {
            return nil
        }

        let escape = { (cell: String) in
            return cell.replacingOccurrences(of: "|", with: "\\|")
        }
        let titles = lines.map { self.title(of: $0[0]) }
        let hasHeader = titles.allSatisfy { $0 != nil }
        let header = hasHeader ? titles.map { escape($0 ?? "") } : Array(repeating: "", count: columns.count)

        var table = [self.tableRow(header), "|" + Array(repeating: "---", count: columns.count).joined(separator: "|") + "|"]
        let rows = hasHeader ? 1..<count : 0..<count
        for row in rows {
            table.append(self.tableRow(lines.map { escape($0[row]) }))
        }
        return table
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
        if let element = node as? Element, self.holdsColumns(element) {
            self.columns(of: element, into: &layout)
            return
        }

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
        guard self.isSpacer(element) == false else {
            layout.gap(2)
            return
        }

        // What an inline element's own style puts around it, see `frame(of:)`.
        let frame = self.frame(of: element)
        if let gaps = frame.gaps {
            layout.gap(gaps.top)
        }
        else if frame.spaceBefore {
            layout.space()
        }

        if element.hasAttr(self.boxAttribute) || element.hasAttr(self.buttonAttribute) {
            self.renderBox(element, into: &layout)
        }
        else {
            self.renderEmphasized(element, into: &layout)
        }

        if let gaps = frame.gaps {
            layout.gap(gaps.bottom)
        }
        else if frame.spaceAfter {
            layout.space()
        }
    }

    fileprivate static func renderTag(of element: Element, into layout: inout Layout) {
        let tag = element.tagName()
        switch tag {
        case "br":
            layout.lineBreak()
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            self.heading(element, level: level, into: &layout)
        case "a":
            self.link(element, into: &layout)
        case "img":
            self.image(element, into: &layout)
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
        case "tr":
            self.layoutRow(element, into: &layout)
        case "th":
            self.headerCell(element, into: &layout)
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

    /// Whether a block is a spacer: it holds nothing a reader sees, no text
    /// and no picture, and its style or its attribute sets a height from 3pt
    /// up. MJML spaces its sections that way, with a hair space in an empty
    /// `div`, and table layouts with an empty cell or row; a browser shows the
    /// space, a blank line here (447 such blocks in 66 of 647 archive mails,
    /// 2026-10-26, 250 of them holding a no-break space that made the line
    /// already). The word is looked for before the style is read, because
    /// every element passes here.
    fileprivate static func isSpacer(_ element: Element) -> Bool {
        let style = (try? element.attr("style")) ?? ""
        guard
            self.blockTags.contains(element.tagName()),
            style.contains("height") || element.hasAttr("height")
        else {
            return false
        }

        let declared = self.declarations(of: element)["height"] ?? ((try? element.attr("height")) ?? "")
        guard
            let height = self.points(declared),
            height >= 3
        else {
            return false
        }
        return self.showsText(element) == false && self.holdsPicture(element) == false
    }

    /// Whether a picture stands anywhere inside the element.
    fileprivate static func holdsPicture(_ element: Element) -> Bool {
        return element.children().array().contains { child in
            return child.tagName() == "img" || self.holdsPicture(child)
        }
    }

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
    ///
    /// A list whose style hides its bullets is a stack of lines to a reader
    /// and is laid out as blocks: a card sets the details of an insurance
    /// that way (3 of 647 archive mails, 2026-10-26).
    fileprivate static func list(_ element: Element, ordered: Bool, into layout: inout Layout) {
        guard self.showsMarkers(element) else {
            self.block(element, into: &layout)
            return
        }

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

    /// Whether a list shows bullets or numbers. Its style hides them with the
    /// type `none`, set on its own or in the shorthand with nothing but a
    /// position beside it; beside a type, `none` is the bullet's picture.
    fileprivate static func showsMarkers(_ list: Element) -> Bool {
        let style = self.declarations(of: list)
        if let type = style["list-style-type"] {
            return type != "none"
        }
        guard let shorthand = style["list-style"] else {
            return true
        }

        let values = shorthand.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let hidesType = values.contains("none") && values.allSatisfy { ["none", "inside", "outside"].contains($0) }
        return hidesType == false
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

    /// The markers emphasis sets its text between.
    fileprivate static let boldMarker = "**"
    fileprivate static let italicMarker = "*"

    /// An element in the emphasis it shows, each line of its text between the
    /// markers, italics inside bold. A picture looks the same with emphasis or
    /// without, so a line of nothing but pictures gets no markers, and so does
    /// a block Markdown marks, a list or a heading: markers around each of its
    /// lines would break it.
    ///
    /// Inside emphasis of its own kind, a `b` in a `strong`, an element adds
    /// nothing a reader sees and sets no markers, which would only stand
    /// doubled. Two spans of one kind that meet are joined by the layout, see
    /// `Layout.write(_:emphasis:)`.
    fileprivate static func renderEmphasized(_ element: Element, into layout: inout Layout) {
        let markers = self.markers(of: element)
        guard markers.isEmpty == false else {
            self.renderTag(of: element, into: &layout)
            return
        }

        var inner = Layout()
        self.renderTag(of: element, into: &inner)
        guard inner.holdsFormattedLines == false else {
            layout.replay(inner.operations)
            return
        }

        var content = inner.content
        for marker in markers.dropLast() {
            var wrapped = Layout()
            wrapped.emphasize(content) { line in
                return self.holdsText(line) ? marker : nil
            }
            content = wrapped.content
        }
        layout.emphasize(content) { line in
            return self.holdsText(line) ? markers.last : nil
        }
    }

    /// The markers an element sets its text between: those of the emphasis it
    /// shows, less those an element around it sets already.
    fileprivate static func markers(of element: Element) -> [String] {
        let own = self.emphasis(of: element)
        guard own.isEmpty == false else {
            return []
        }

        let around = element.parents().array().flatMap { self.emphasis(of: $0) }
        return own.filter { around.contains($0) == false }
    }

    /// The emphasis an element shows of its own, as markers, italics first.
    ///
    /// `b` and `strong` are bold, `em` and `i` italic, and any element is what
    /// its style makes it, the style winning over the tag as in a browser: an
    /// email framework sets a name or an amount in bold through the style of a
    /// `div` or a `span` (61 of 647 archive mails, 2026-10-26). Headings and
    /// header cells are bold already and laid out on their own.
    fileprivate static func emphasis(of element: Element) -> [String] {
        let tag = element.tagName()
        guard ["th", "h1", "h2", "h3", "h4", "h5", "h6"].contains(tag) == false else {
            return []
        }

        let style = self.declarations(of: element)
        var isItalic = ["em", "i"].contains(tag)
        var isBold = ["strong", "b"].contains(tag)
        if let slanted = style["font-style"].flatMap({ self.isItalic($0) }) {
            isItalic = slanted
        }
        if let heavy = style["font-weight"].flatMap({ self.isBold($0) }) {
            isBold = heavy
        }

        var markers: [String] = []
        if isItalic {
            markers.append(self.italicMarker)
        }
        if isBold {
            markers.append(self.boldMarker)
        }
        return markers
    }

    /// Whether a `font-weight` shows bold: `bold`, `bolder`, or a number from
    /// 600 up. Nil for a value that says nothing definite, `inherit` and the
    /// like, which leaves the decision to the tag.
    fileprivate static func isBold(_ weight: String) -> Bool? {
        switch weight {
        case "bold", "bolder":
            return true
        case "normal", "lighter":
            return false
        default:
            return Double(weight).map { $0 >= 600 }
        }
    }

    /// Whether a `font-style` slants the text, `italic` or `oblique` with or
    /// without an angle. Nil for a value that says nothing definite.
    fileprivate static func isItalic(_ style: String) -> Bool? {
        if style == "italic" || style.hasPrefix("oblique") {
            return true
        }
        if style == "normal" {
            return false
        }
        return nil
    }

    /// A link as `[text](href)`, its text on one line and its brackets
    /// escaped. A link whose text is its own address, give or take the scheme,
    /// a closing slash and the emphasis around it, is written as that text:
    /// Outlook links every address it prints, and the Markdown link would show
    /// it twice.
    ///
    /// A link around links, a job card or the preview of a repository, is
    /// taken apart, and its inner links keep their targets: Markdown cannot
    /// nest links, and the `[[` it wrote opens a wikilink in Obsidian.
    ///
    /// So is a link around a picture embedded from its file: Obsidian does not
    /// show an embed inside a link. The picture stays and the target goes, as
    /// it went with the picture before; in the archive 135 of 136 links around
    /// a picture held nothing else, a logo or an icon (measured 2026-10-04).
    fileprivate static func link(_ element: Element, into layout: inout Layout) {
        guard
            self.holdsLink(element) == false,
            self.holdsEmbed(element) == false
        else {
            self.renderChildren(of: element, into: &layout)
            return
        }

        let content = self.content(of: element)
        let href = self.target(of: element)
        let text = content.flattened

        guard
            href.isEmpty == false,
            text.isEmpty == false,
            self.address(text.trimmingCharacters(in: ["*"])) != self.address(href)
        else {
            layout.place(content) { line in
                return line
            }
            return
        }

        layout.place(content.onOneLine) { line in
            return "[\(self.escapingBrackets(line))](\(self.destination(href)))"
        }
    }

    /// A link's target as Markdown reads it: as it stands, or in pointy
    /// brackets where Markdown would not read it so. A space ends a target, a
    /// parenthesis without its partner ends it early or never, and a `<` at
    /// its start opens the bracketed form. Between the brackets only a line
    /// break could end it, and the target holds none (`target(of:)`), so `<`,
    /// `>` and a backslash are escaped there and nothing else. Until 1.5.0 the
    /// map links and footers of a parcel service, with a space in the query,
    /// showed as text (102 targets in 6 of 648 archive mails, 2026-10-26).
    fileprivate static func destination(_ target: String) -> String {
        let breaks = target.unicodeScalars.contains { $0 == " " || $0.value < 0x20 || $0.value == 0x7F }
        guard
            breaks == false,
            self.pairsItsParentheses(target),
            target.hasPrefix("<") == false
        else {
            let escaped = target
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "<", with: "\\<")
                .replacingOccurrences(of: ">", with: "\\>")
            return "<\(escaped)>"
        }
        return target
    }

    /// Whether every parenthesis in a text closes one before it.
    fileprivate static func pairsItsParentheses(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" {
                depth += 1
            }
            else if character == ")" {
                guard depth > 0 else {
                    return false
                }
                depth -= 1
            }
        }
        return depth == 0
    }

    /// A picture of an emoji is written as the emoji: Outlook sends an emoji
    /// typed into a message as a picture of it, and the emoji is what the
    /// reader saw.
    ///
    /// A picture from a part of the mail is marked as shown, and it is
    /// embedded where its file was named; written into the text as it is,
    /// because a name with two spaces in a row is still that file's name. Any
    /// other picture is dropped.
    fileprivate static func image(_ element: Element, into layout: inout Layout) {
        guard self.isEmoji(element) == false else {
            let alt = ((try? element.attr("alt")) ?? "").trimmingCharacters(in: .whitespaces)
            self.write(alt, into: &layout)
            return
        }
        guard self.contentID(of: element) != nil else {
            return
        }
        _ = try? element.attr(self.shownAttribute, "")

        if let file = self.file(of: element) {
            let alt = (try? element.attr("alt")) ?? ""
            layout.write(self.embed(file, alt: alt))
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

        /// Whether it holds text beside the pictures embedded in it.
        var holdsText: Bool {
            return self.lines.contains { HTMLToMarkdown.holdsText($0) }
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
    /// table itself, has two rows of cells or more, and at least one row with
    /// two filled cells. The last two tests run on the rendered cells, so a
    /// logo beside a signature, an empty cell once the image is gone, does not
    /// make a table of data. Rows without any text are left out, the spacer
    /// rows of a layout grid, and a row that spans the table is a caption, not
    /// a row of cells.
    ///
    /// A single row compares nothing, so it is layout, as in Mozilla's
    /// Readability: a bar of links, or a whole letter beside its menu, which a
    /// Markdown table squeezed into one cell (counted on 2026-10-03: 53 tables
    /// in the archive, and 35 more with a caption above their one row).
    ///
    /// Both tests look at the text alone, as if the table's pictures were not
    /// there. An embedded picture fills its cell, and a logo beside a signature
    /// would then make a table of data out of what was layout without it (one
    /// signature in the archive, 2026-10-04). Embedding pictures changes no
    /// layout.
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
                    lines: self.lines(ofCell: cell),
                    isHeader: isHeaderRow || cell.tagName() == "th",
                    span: max(1, span)
                )
            }
            if cells.contains(where: { $0.isEmpty == false }) {
                rows.append(cells)
            }
        }

        let rowsOfText = rows.filter { row in
            return row.contains { $0.holdsText } && self.isSpanning(row) == false
        }
        let holdsData = rowsOfText.count >= 2 && rowsOfText.contains { row in
            return row.filter { $0.holdsText }.count >= 2
        }
        return holdsData ? rows : nil
    }

    /// The lines of a cell of data, in the emphasis the cell's own style sets,
    /// as the total of a receipt is set bold. Its content is laid out without
    /// the cell, so the markers are set here, unless it holds a block Markdown
    /// marks.
    fileprivate static func lines(ofCell cell: Element) -> [String] {
        var layout = Layout()
        self.renderChildren(of: cell, into: &layout)
        let lines = layout.content.trimmedLines.filter { $0.isEmpty == false }

        let markers = layout.holdsFormattedLines ? [] : self.markers(of: cell)
        return lines.map { line in
            guard self.holdsText(line) else {
                return line
            }
            return markers.reduce(line) { $1 + $0 + $1 }
        }
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

    /// A row of a layout table. A browser shows its cells side by side, so
    /// where each cell but the last holds one line of text, they share it,
    /// and the last cell runs on below: a bullet beside its text, the number
    /// of a step beside its description, a bar of links. A cell that opens
    /// with a block Markdown marks, a list or a table, cannot share its line,
    /// and such a row is laid out cell after cell.
    ///
    /// Each child is laid out on its own first, to measure the cells, and a
    /// row that keeps its cells apart replays them, so it comes out exactly
    /// as if laid out in place.
    fileprivate static func layoutRow(_ row: Element, into layout: inout Layout) {
        var parts: [(node: Node, layout: Layout)] = []
        let children = row.getChildNodes()
        for child in children {
            var part = Layout()
            self.render(child, into: &part)
            parts.append((child, part))
        }

        let cells = parts
            .filter { ["td", "th"].contains(($0.node as? Element)?.tagName() ?? "") }
            .map { $0.layout }
            .filter { $0.content.trimmedLines.isEmpty == false }
        let spacing = self.spacing(of: row)

        guard let shared = self.sharedLine(of: cells) else {
            layout.gap(spacing.top)
            for part in parts {
                layout.replay(part.layout.operations)
            }
            layout.gap(spacing.bottom)
            return
        }

        layout.gap(max(spacing.top, cells.map { $0.content.gapBefore }.max() ?? 0))
        layout.write(shared.line)
        layout.writeLines(shared.rest)
        layout.gap(max(spacing.bottom, cells.map { $0.content.gapAfter }.max() ?? 0))
    }

    /// The line the cells of a layout row share and the lines the last one
    /// runs on with, or nil where they cannot share one.
    fileprivate static func sharedLine(of cells: [Layout]) -> (line: String, rest: [String])? {
        guard
            cells.count >= 2,
            let last = cells.last,
            last.opensWithText
        else {
            return nil
        }

        let others = cells.dropLast()
        let othersAreLines = others.allSatisfy { cell in
            return cell.content.trimmedLines.count == 1 && cell.holdsFormattedLines == false
        }
        guard othersAreLines else {
            return nil
        }

        let lastLines = last.content.trimmedLines
        let firstLines = others.map { $0.content.trimmedLines[0] } + [lastLines[0]]
        return (firstLines.joined(separator: " "), Array(lastLines.dropFirst()))
    }

    /// A header cell outside a table of data. A browser sets it in bold, so
    /// it is bold here too, unless its style sets a lighter weight or it holds
    /// blocks: an email framework lays out whole columns in header cells and
    /// sets their weight back in a stylesheet this converter does not read.
    fileprivate static func headerCell(_ element: Element, into layout: inout Layout) {
        let isBold = self.declarations(of: element)["font-weight"].flatMap { self.isBold($0) } ?? true
        guard
            self.holdsBlocks(element) == false,
            isBold
        else {
            self.block(element, into: &layout)
            return
        }

        let spacing = self.spacing(of: element)
        layout.gap(spacing.top)
        layout.place(self.content(of: element)) { line in
            return self.bold(line)
        }
        layout.gap(spacing.bottom)
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
        return self.isHidden(element, style: self.declarations(of: element))
    }

    /// The same, for an element whose style was read already.
    fileprivate static func isHidden(_ element: Element, style: [String: String]) -> Bool {
        if element.hasAttr("hidden") {
            return true
        }
        let skipInText = ((try? element.attr("data-skip-in-text")) ?? "").lowercased()
        if element.hasAttr("data-skip-in-text") && skipInText != "false" {
            return true
        }

        return style["display"] == "none" || style["visibility"] == "hidden"
    }

    /// The gap above and below a block, a line break (1) or a blank line (2).
    ///
    /// A blank line stands where a browser leaves visible space, from 3pt up,
    /// and margin and padding both leave it: React Email zeroes its margins
    /// and spaces its paragraphs with padding. Without a style, a `p` has the
    /// browser's margin of one line above and below, and so has a list, which
    /// is laid out as blocks where it shows no bullets; every other block has
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
        let isList = ["ul", "ol"].contains(element.tagName())
        let defaultMargin = (isParagraph && isWordParagraph == false) || isList ? 12.0 : 0.0

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

    /// What an inline element's own style puts around it.
    fileprivate struct Frame {
        /// The gaps above and below, for an element its style sets as a block.
        var gaps: (top: Int, bottom: Int)?
        var spaceBefore = false
        var spaceAfter = false
    }

    /// The frame of an element as a browser lays it out. A `display` that
    /// makes an inline element a block sets it on lines of its own, with the
    /// gaps its margins give it: a classifieds site sets the links of its
    /// footer one below the other that way. Room at a side, margin or padding
    /// from 3pt up, keeps it apart from its neighbour by a space: Wix keeps
    /// the links of its footer apart that way. Neither had anything else
    /// between the links, so they ran into each other. A block element has
    /// its spacing from `spacing(of:)` and no frame.
    fileprivate static func frame(of element: Element) -> Frame {
        let tag = element.tagName()
        guard
            self.blockTags.contains(tag) == false,
            self.structuralTags.contains(tag) == false,
            tag != "br"
        else {
            return Frame()
        }

        let style = self.declarations(of: element)
        let blockDisplays = ["block", "flex", "grid", "list-item", "table"]
        if let display = style["display"], blockDisplays.contains(display) {
            return Frame(gaps: self.spacing(of: element))
        }

        let room = self.horizontalRoom(style)
        return Frame(spaceBefore: room.left >= 3, spaceAfter: room.right >= 3)
    }

    /// The room at the left and the right of an element, margin plus
    /// padding, in points.
    fileprivate static func horizontalRoom(_ declarations: [String: String]) -> (left: Double, right: Double) {
        var left = 0.0
        var right = 0.0

        let properties = ["margin", "padding"]
        for property in properties {
            var sides = self.horizontalSides(declarations[property])
            if let value = declarations[property + "-left"] {
                sides.left = self.points(value)
            }
            if let value = declarations[property + "-right"] {
                sides.right = self.points(value)
            }
            left += sides.left ?? 0
            right += sides.right ?? 0
        }

        return (left, right)
    }

    /// Left and right of a `margin` or `padding` shorthand: one value is all
    /// four sides, two and three give both sides second, four give the right
    /// second and the left last.
    fileprivate static func horizontalSides(_ shorthand: String?) -> (left: Double?, right: Double?) {
        guard
            let values = shorthand?.split(whereSeparator: { $0.isWhitespace }).map(String.init),
            values.isEmpty == false
        else {
            return (nil, nil)
        }

        let right = self.points(values.count >= 2 ? values[1] : values[0])
        let left = values.count >= 4 ? self.points(values[3]) : right
        return (left, right)
    }

    /// The background an element paints itself, from its style or else from
    /// its `bgcolor`, or nil where the one behind it shows through: none set,
    /// a picture alone, or a colour that lets everything through.
    fileprivate static func background(of element: Element, style: [String: String]) -> Color? {
        if let value = style["background-color"] ?? style["background"] {
            let color = self.firstColor(in: value)
            return (color?.alpha ?? 0) > 0 ? color : nil
        }
        guard element.hasAttr("bgcolor") else {
            return nil
        }

        let attribute = ((try? element.attr("bgcolor")) ?? "").lowercased()
        let color = Color(css: attribute) ?? Color(css: "#" + attribute)
        return (color?.alpha ?? 0) > 0 ? color : nil
    }

    /// The first colour among the words of a `background` shorthand, past a
    /// picture's address, which may hold a colour's name.
    fileprivate static func firstColor(in value: String) -> Color? {
        guard value.contains("(") else {
            let words = value.split(whereSeparator: { $0.isWhitespace })
            return words.lazy.compactMap { Color(css: String($0)) }.first
        }

        let words = value.replacing(/url\([^)]*\)/, with: "").matches(of: /#[0-9a-f]+|rgba?\([^)]*\)|[a-z]+/)
        return words.lazy.compactMap { Color(css: String($0.output)) }.first
    }

    /// The colour an element sets its text in, from its style or else, for
    /// `font`, from its attribute; nil where it keeps the one around it.
    fileprivate static func color(of element: Element, style: [String: String]) -> Color? {
        if let value = style["color"] {
            return Color(css: value)
        }
        guard
            element.tagName() == "font",
            element.hasAttr("color")
        else {
            return nil
        }

        let attribute = ((try? element.attr("color")) ?? "").lowercased()
        return Color(css: attribute) ?? Color(css: "#" + attribute)
    }

    /// Whether a border closes an element in on all four sides, a side's own
    /// declaration winning over the shorthand.
    fileprivate static func hasFrame(_ style: [String: String]) -> Bool {
        let all = style["border"].map { self.isVisibleBorder($0) } ?? false
        let sides = ["top", "right", "bottom", "left"]
        return sides.allSatisfy { side in
            return style["border-" + side].map { self.isVisibleBorder($0) } ?? all
        }
    }

    /// Whether a `border` value draws a line: one with a style, no `none` or
    /// `hidden`, and a width above zero. Without a style CSS draws none.
    fileprivate static func isVisibleBorder(_ value: String) -> Bool {
        let values = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let styles = ["solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"]
        guard values.contains(where: { styles.contains($0) }) else {
            return false
        }
        let width = values.lazy.compactMap { self.points($0) }.first ?? 1
        return width > 0
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

    /// Whether a link shows inside the element, one a browser does not hide.
    fileprivate static func holdsLink(_ element: Element) -> Bool {
        return element.children().array().contains { child in
            guard self.isHidden(child) == false else {
                return false
            }
            return (child.tagName() == "a" && self.target(of: child).isEmpty == false) || self.holdsLink(child)
        }
    }

    /// A link's target as a browser reads it: without the whitespace at its
    /// ends, and without the tabs and line breaks the URL standard takes out
    /// of it wherever they stand.
    fileprivate static func target(of link: Element) -> String {
        let href = ((try? link.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = href.unicodeScalars
        guard scalars.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }) else {
            return href
        }
        return String(String.UnicodeScalarView(scalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }))
    }

    /// Link text with its square brackets escaped: a bracket would end the
    /// text early, and a pair at its edge opens a wikilink in Obsidian, as in
    /// `[[German]](#German)`. Code keeps its brackets, because a backslash
    /// inside code would show.
    fileprivate static func escapingBrackets(_ text: String) -> String {
        var escaped = ""
        var rest = text[...]

        while let character = rest.first {
            if character == "`" {
                let fence = rest.prefix { $0 == "`" }
                let afterFence = rest[fence.endIndex...]
                guard let close = afterFence.range(of: fence) else {
                    escaped += fence
                    rest = afterFence
                    continue
                }
                escaped += rest[..<close.upperBound]
                rest = rest[close.upperBound...]
                continue
            }

            if character == "[" || character == "]" {
                escaped += "\\"
            }
            escaped.append(character)
            rest = rest.dropFirst()
        }

        return escaped
    }

    /// The HTML with each character beyond the first 65536 that is written as
    /// its two UTF-16 halves, `&#55358;&#56598;`, written as one reference,
    /// `&#x1F916;`. The HTML standard reads each half alone as U+FFFD, and a
    /// chatbot transcript wrote its emoji that way, while the plain form of the
    /// same mail carries them. A half without its partner is left to the parser.
    fileprivate static func joiningSurrogateHalves(_ html: String) -> String {
        let reference = /&#(?:([0-9]{1,7})|[xX]([0-9A-Fa-f]{1,6}));/
        var joined = ""
        var rest = html[...]

        while let high = rest.firstMatch(of: reference) {
            joined += rest[..<high.range.lowerBound]
            rest = rest[high.range.upperBound...]

            guard
                let highHalf = self.number(decimal: high.1, hexadecimal: high.2),
                (0xD800...0xDBFF).contains(highHalf),
                let low = rest.prefixMatch(of: reference),
                let lowHalf = self.number(decimal: low.1, hexadecimal: low.2),
                (0xDC00...0xDFFF).contains(lowHalf)
            else {
                joined += high.0
                continue
            }

            let scalar = 0x10000 + ((highHalf - 0xD800) << 10) + (lowHalf - 0xDC00)
            joined += "&#x" + String(scalar, radix: 16, uppercase: true) + ";"
            rest = rest[low.range.upperBound...]
        }

        return joined + rest
    }

    /// The number a character reference stands for.
    fileprivate static func number(decimal: Substring?, hexadecimal: Substring?) -> Int? {
        if let decimal {
            return Int(decimal)
        }
        return hexadecimal.flatMap { Int($0, radix: 16) }
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

    /// The line of a header cell in bold as a whole, unless it holds nothing
    /// but pictures, which look the same either way. A header cell is bold all
    /// over, so bold inside it adds nothing and its markers go, as they go in a
    /// button. Until 1.5.0 a line that began and ended in bold counted as bold
    /// already, and a word between two bold ones stayed plain.
    fileprivate static func bold(_ text: String) -> String {
        guard self.holdsText(text) else {
            return text
        }
        return self.boldMarker + text.replacingOccurrences(of: self.boldMarker, with: "") + self.boldMarker
    }

    /// Whether a line holds text beside the pictures embedded in it.
    fileprivate static func holdsText(_ line: String) -> Bool {
        guard line.contains("![[") else {
            return line.contains { $0 != " " }
        }
        return line.replacing(/!\[\[[^\]]*\]\]/, with: "").contains { $0 != " " }
    }
}

// MARK: - Colour

/// A colour as CSS writes it, each channel from 0 to 1, with its opacity.
fileprivate struct Color: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = Color(red: 0, green: 0, blue: 0, alpha: 1)

    /// CSS's sixteen basic colours, and grey spelt with an e.
    private static let names: [String: String] = [
        "black": "000000", "silver": "c0c0c0", "gray": "808080", "grey": "808080",
        "white": "ffffff", "maroon": "800000", "red": "ff0000", "purple": "800080",
        "fuchsia": "ff00ff", "green": "008000", "lime": "00ff00", "olive": "808000",
        "yellow": "ffff00", "navy": "000080", "blue": "0000ff", "teal": "008080",
        "aqua": "00ffff", "transparent": "00000000",
    ]

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The colour a CSS value names: `#rgb` or `#rrggbb`, either with an
    /// opacity, `rgb()` or `rgba()`, or a basic name. Nil for anything else,
    /// a system colour or a variable among them.
    init?(css value: String) {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let name = Color.names[text] {
            self.init(hex: name)
            return
        }
        if text.hasPrefix("#") {
            self.init(hex: String(text.dropFirst()))
            return
        }
        guard
            text.hasPrefix("rgb"),
            let arguments = text.wholeMatch(of: /rgba?\((.*)\)/)
        else {
            return nil
        }

        let numbers = arguments.1.matches(of: /[0-9.]+%?/).map { String($0.output) }
        guard numbers.count >= 3 else {
            return nil
        }
        let channels = numbers.prefix(3).compactMap { number in
            return number.hasSuffix("%") ? Double(number.dropLast()).map { $0 / 100 } : Double(number).map { $0 / 255 }
        }
        let alpha = numbers.count >= 4 ? (numbers[3].hasSuffix("%") ? Double(numbers[3].dropLast()).map { $0 / 100 } : Double(numbers[3])) : 1
        guard
            channels.count == 3,
            let alpha
        else {
            return nil
        }
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// The colour of hexadecimal digits, three or six, with one or two more
    /// for the opacity.
    private init?(hex digits: String) {
        guard digits.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        let pairs: [String]
        switch digits.count {
        case 3, 4:
            pairs = digits.map { String([$0, $0]) }
        case 6, 8:
            pairs = stride(from: 0, to: digits.count, by: 2).map { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                return String(digits[start..<digits.index(start, offsetBy: 2)])
            }
        default:
            return nil
        }

        let values = pairs.compactMap { UInt8($0, radix: 16) }.map { Double($0) / 255 }
        self.init(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    /// The colour seen where this one lies over `background`.
    func over(_ background: Color) -> Color {
        guard self.alpha < 1 else {
            return self
        }

        let mix = { (front: Double, back: Double) in
            return front * self.alpha + back * (1 - self.alpha)
        }
        return Color(red: mix(self.red, background.red), green: mix(self.green, background.green), blue: mix(self.blue, background.blue), alpha: 1)
    }

    /// How light the colour looks, from 0 for black to 1 for white, as WCAG
    /// computes relative luminance.
    var luminance: Double {
        let linear = { (channel: Double) in
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(self.red) + 0.7152 * linear(self.green) + 0.0722 * linear(self.blue)
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
///
/// Every call is kept as an operation. What an element asks of a layout
/// depends on the element alone, never on what the layout holds, so the calls
/// one layout received can be replayed into another, with the same result as
/// laying the element out there in the first place.
fileprivate struct Layout {

    /// A call the layout received.
    enum Operation {
        case gap(Int)
        case write(String, emphasis: String?)
        case space(nonBreaking: Bool)
        case lineBreak
        case writeLines([String])
        case rule
    }

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

    private(set) var operations: [Operation] = []

    private var lines: [String] = []
    private var current = ""

    /// The current line holds something, if only a no-break space.
    private var occupied = false

    /// Anything has been written at all; a gap before that is no gap.
    private var started = false

    /// The last thing written was a line break.
    private var brokeLine = false

    /// The marker of the emphasis the last text was written in, nil where it
    /// was written plain. The current line ends with it until a space or a
    /// line break follows.
    private var closingMarker: String?

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

    /// Whether its first text was written inline, rather than as lines a
    /// block formatted itself.
    var opensWithText: Bool {
        for operation in self.operations {
            switch operation {
            case .write:
                return true
            case .writeLines, .rule:
                return false
            default:
                continue
            }
        }
        return false
    }

    /// Whether a block formatted lines of its own into it: a list, a quote, a
    /// table, a code fence, a heading or a rule.
    var holdsFormattedLines: Bool {
        return self.operations.contains { operation in
            switch operation {
            case .writeLines, .rule:
                return true
            default:
                return false
            }
        }
    }

    mutating func gap(_ size: Int) {
        self.operations.append(.gap(size))

        if self.started == false {
            self.leadingGap = max(self.leadingGap, size)
        }
        self.pendingGap = max(self.pendingGap, size)
    }

    /// Inline text, its whitespace already collapsed, set between the marker
    /// of its emphasis where it has one.
    ///
    /// Emphasis that meets emphasis of the same marker continues it: the
    /// closing marker the current line ends with is taken back, and the text
    /// goes on without an opening one. Written one after the other, the
    /// markers of two spans would meet in a run of four, which Markdown does
    /// not read as the end of one span and the start of the next, so that
    /// `**Software-****Entwicklung**` leaves asterisks standing as text.
    /// Outlook splits a bold line into spans like these wherever the
    /// formatting inside it changed.
    mutating func write(_ text: String, emphasis marker: String? = nil) {
        self.operations.append(.write(text, emphasis: marker))
        self.settle()

        var piece = Substring(text)
        if let marker {
            let continues = self.closingMarker == marker && self.current.hasSuffix(marker)
            if continues {
                self.current.removeLast(marker.count)
            }
            piece = Substring((continues ? "" : marker) + text + marker)
        }
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
        self.closingMarker = marker
    }

    /// The space between two words. At the start of a line or before a gap it
    /// is nothing, unless it is a no-break space: that one holds an otherwise
    /// empty line open.
    mutating func space(nonBreaking: Bool = false) {
        self.operations.append(.space(nonBreaking: nonBreaking))

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
        self.operations.append(.lineBreak)
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

        self.operations.append(.writeLines(block))
        self.settle()
        if self.occupied {
            self.commit()
        }
        self.lines.append(contentsOf: block)
        self.started = true
        self.brokeLine = false
    }

    /// A rule, `---`, that sets a card apart, unless one stands right above
    /// with nothing but blank lines between: two cards one below the other
    /// share the rule between them.
    mutating func rule() {
        self.operations.append(.rule)
        self.settle()
        if self.occupied {
            self.commit()
        }
        guard self.lines.last(where: { $0.isEmpty == false }) != "---" else {
            return
        }

        self.lines.append("---")
        self.started = true
        self.brokeLine = false
    }

    /// Writes content laid out on its own, each line of text passed through
    /// `transform`, with the gaps, spaces and line breaks it had at its edges.
    mutating func place(_ content: Content, transform: (String) -> String) {
        self.place(content, writeLine: { layout, line in
            layout.write(transform(line))
        })
    }

    /// Writes content laid out on its own in emphasis, each line of text
    /// between the marker `marker` gives it, none where it gives nil, with
    /// the gaps, spaces and line breaks it had at its edges.
    mutating func emphasize(_ content: Content, marker: (String) -> String?) {
        self.place(content, writeLine: { layout, line in
            layout.write(line, emphasis: marker(line))
        })
    }

    /// Writes content laid out on its own, each line of text by `writeLine`,
    /// with the gaps, spaces and line breaks it had at its edges.
    private mutating func place(_ content: Content, writeLine: (inout Layout, String) -> Void) {
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
                writeLine(&self, line)
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

    /// Makes the calls another layout received, in their order.
    mutating func replay(_ operations: [Operation]) {
        for operation in operations {
            switch operation {
            case .gap(let size):
                self.gap(size)
            case .write(let text, let marker):
                self.write(text, emphasis: marker)
            case .space(let nonBreaking):
                self.space(nonBreaking: nonBreaking)
            case .lineBreak:
                self.lineBreak()
            case .writeLines(let block):
                self.writeLines(block)
            case .rule:
                self.rule()
            }
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
