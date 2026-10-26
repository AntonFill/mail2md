//
//  MarkdownWriter.swift
//  mail2md
//
//  Created by Anton Fillmann on 22.07.2026.
//

import Foundation

/// Writes rendered Markdown to disk without silently discarding existing work,
/// or to stdout.
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
    /// Returns the URLs actually written. Throws what `check` finds before
    /// writing anything, `Conflict` when a target differs and `force` is off.
    @discardableResult
    func writeAll(_ documents: [Document]) throws -> [URL] {
        try self.check(documents)

        var written: [URL] = []
        for document in documents where self.existingContent(at: document.url) != document.content {
            try document.content.write(to: document.url, atomically: true, encoding: .utf8)
            written.append(document.url)
        }
        return written
    }

    /// Throws what writing the documents would run into, without writing any:
    /// `Conflict` for a target that differs, unless `force` is set, and the
    /// error of a folder that takes no file, one that is missing or that may
    /// not be written to. A target that holds its content already needs no
    /// write and passes.
    ///
    /// A run that writes files besides the note, the attachments it links,
    /// checks the note first, so that what would stop the note stops the run
    /// before anything lands on disk.
    func check(_ documents: [Document]) throws {
        if self.force == false {
            for document in documents {
                if let existing = self.existingContent(at: document.url), existing != document.content {
                    throw Conflict(path: document.url.path)
                }
            }
        }

        // A file is written to a temporary name beside it and moved into
        // place, so what it takes is a folder that can be written to.
        for document in documents where self.existingContent(at: document.url) != document.content {
            let folder = document.url.deletingLastPathComponent().path
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: document.url.path])
            }
            guard FileManager.default.isWritableFile(atPath: folder) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: document.url.path])
            }
        }
    }

    /// Writes the Markdown to stdout, byte for byte what a file would hold.
    ///
    /// A stream has nothing to compare against: there is no conflict, and
    /// `force` changes nothing. The acceptance suite pins the bytes, since a
    /// test in process cannot read its own stdout.
    func writeToStandardOutput(_ content: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data(content.utf8))
    }

    /// The current content of `url`, or nil when it does not exist.
    private func existingContent(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
