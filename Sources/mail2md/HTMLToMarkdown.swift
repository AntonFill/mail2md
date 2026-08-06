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
/// Scope is deliberately narrow: the tags that actually occur in email bodies
/// (headings, paragraphs, links, emphasis, lists, blockquotes, code). Unknown
/// tags are unwrapped (their text is kept); `script`/`style`/`head` and images
/// are dropped. The goal is readable, AI-ready Markdown, not full-fidelity
/// HTML rendering (no table layout, no CSS).
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
        } catch {
            return html
        }

        return self.normalize(self.renderChildren(of: body))
    }
}

// MARK: - Tree walking
extension HTMLToMarkdown {

    fileprivate static func renderChildren(of node: Node) -> String {
        return node.getChildNodes().map { self.render($0) }.joined()
    }

    fileprivate static func render(_ node: Node) -> String {
        if let text = node as? TextNode {
            return self.collapseWhitespace(text.getWholeText())
        }
        guard let element = node as? Element else {
            return ""  // comments, data nodes, …
        }

        let inner = self.renderChildren(of: element)

        switch element.tagName() {
        case "br":
            return "\n"
        case "p", "div", "section", "article", "header", "footer", "tr":
            return self.block(inner)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(element.tagName().dropFirst()) ?? 1
            return self.block(String(repeating: "#", count: level) + " " + inner.trimmed)
        case "strong", "b":
            return self.wrapInline(inner, with: "**")
        case "em", "i":
            return self.wrapInline(inner, with: "*")
        case "a":
            return self.link(element, inner: inner)
        case "ul":
            return self.list(element, ordered: false)
        case "ol":
            return self.list(element, ordered: true)
        case "blockquote":
            return self.block(self.quote(inner))
        case "code":
            return "`\(inner.trimmed)`"
        case "pre":
            return self.block("```\n" + inner.trimmed + "\n```")
        case "hr":
            return self.block("---")
        default:
            return inner  // span, font, table, td, li outside a list, … → unwrap
        }
    }
}

// MARK: - Element helpers
extension HTMLToMarkdown {

    fileprivate static func link(_ element: Element, inner: String) -> String {
        let href = ((try? element.attr("href")) ?? "").trimmed
        let text = inner.trimmed
        guard href.isEmpty == false, href != text, text.isEmpty == false else {
            return inner
        }
        guard href.hasPrefix("mailto:") == false || href != "mailto:\(text)" else {
            return text
        }
        return "[\(text)](\(href))"
    }

    fileprivate static func list(_ element: Element, ordered: Bool) -> String {
        var lines: [String] = []
        var index = 1

        let items = element.children().array()
        for item in items where item.tagName() == "li" {
            // Flatten each item to a single line (no nested-list indentation in v1).
            let content = self.renderChildren(of: item).trimmed.replacing(/\s*\n+\s*/, with: " ")
            guard content.isEmpty == false else {
                continue
            }
            lines.append((ordered ? "\(index). " : "- ") + content)
            index += 1
        }

        return self.block(lines.joined(separator: "\n"))
    }

    fileprivate static func quote(_ inner: String) -> String {
        return inner.trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
    }
}

// MARK: - Text helpers
extension HTMLToMarkdown {

    /// A block-level element: trimmed content followed by a blank line.
    fileprivate static func block(_ content: String) -> String {
        let trimmed = content.trimmed
        return trimmed.isEmpty ? "" : trimmed + "\n\n"
    }

    /// Wraps inline content in a marker, keeping surrounding spaces outside it.
    fileprivate static func wrapInline(_ content: String, with marker: String) -> String {
        let trimmed = content.trimmed
        guard trimmed.isEmpty == false else {
            return content
        }
        let lead = content.hasPrefix(" ") ? " " : ""
        let trail = content.hasSuffix(" ") ? " " : ""
        return lead + marker + trimmed + marker + trail
    }

    /// Collapses HTML whitespace (incl. non-breaking spaces) to single spaces.
    fileprivate static func collapseWhitespace(_ text: String) -> String {
        return text.replacingOccurrences(of: "\u{00A0}", with: " ").replacing(/\s+/, with: " ")
    }

    /// Trims horizontal whitespace per line (stray inter-block text nodes leave
    /// leading spaces) and collapses runs of blank lines.
    fileprivate static func normalize(_ markdown: String) -> String {
        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacing(/^[ \t]+/, with: "").replacing(/[ \t]+$/, with: "") }

        return lines
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: -
extension String {

    fileprivate var trimmed: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
