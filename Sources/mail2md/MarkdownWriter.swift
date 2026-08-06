//
//  MarkdownWriter.swift
//  mail2md
//
//  Created by Anton Fillmann on 22.07.2026.
//

import Foundation

/// Writes rendered Markdown to disk without silently discarding existing work.
///
/// Conversion is idempotent, so re-running on an unchanged mail should be a
/// no-op; a target that has diverged (hand-edited, or produced from a different
/// mail) must not be overwritten by accident. The writer compares before
/// writing: identical content is skipped, differing content is a conflict,
/// unless `force` is set.
///
/// When several files are written at once, the check is a pre-flight: if any
/// target conflicts, nothing is written, so a run never leaves a half-updated
/// set on disk.
struct MarkdownWriter {
    let force: Bool

    /// A target exists with content differing from what would be written.
    struct Conflict: Error {
        let path: String
    }

    /// A file to write: its destination and the rendered Markdown.
    struct Document {
        let url: URL
        let content: String
    }

    /// Writes all documents, skipping any whose content is already identical.
    /// Returns the URLs actually written. Throws `Conflict` (before writing
    /// anything) when a target differs and `force` is off.
    @discardableResult
    func writeAll(_ documents: [Document]) throws -> [URL] {
        if self.force == false {
            for document in documents {
                if let existing = self.existingContent(at: document.url), existing != document.content {
                    throw Conflict(path: document.url.path)
                }
            }
        }

        var written: [URL] = []
        for document in documents where self.existingContent(at: document.url) != document.content {
            try document.content.write(to: document.url, atomically: true, encoding: .utf8)
            written.append(document.url)
        }
        return written
    }

    /// The current content of `url`, or nil when it does not exist.
    private func existingContent(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
