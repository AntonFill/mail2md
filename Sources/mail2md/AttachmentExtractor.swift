//
//  AttachmentExtractor.swift
//  mail2md
//
//  Created by Anton Fillmann on 22.07.2026.
//

import Foundation
import UniformTypeIdentifiers

/// Writes the decoded bytes of attachment parts to a directory.
///
/// This is the impure, filesystem-facing counterpart to the pure parser. It
/// guards two hazards that a `filename` header can carry: path traversal
/// (`../`, absolute paths; reduced to the bare last component) and name
/// collisions between attachments (or with files already present; suffixed
/// `-1`, `-2`, … so nothing is overwritten). Parts without a usable name fall
/// back to `unnamed`, with an extension derived from the media type when the
/// system can map it.
struct AttachmentExtractor {
    let directory: URL

    /// Writes each part's decoded bytes into `directory`, returning the
    /// filenames actually written, in document order. No directory is created
    /// when there is nothing to extract.
    func extract(_ parts: [AttachmentPart]) throws -> [String] {
        guard parts.isEmpty == false else {
            return []
        }

        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        // Seed with existing entries so extraction never overwrites a file.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: self.directory.path)) ?? []
        var taken = Set(contents)
        var written: [String] = []

        for part in parts {
            let name = self.uniqueName(self.safeName(for: part), taken: &taken)
            let data = decodeToBytes(part.entity)
            try data.write(to: self.directory.appendingPathComponent(name))
            written.append(name)
        }

        return written
    }

    // MARK: -

    /// The bare, filesystem-safe filename for a part: the last path component of
    /// the header filename (defeating `../` and absolute paths), or an `unnamed`
    /// fallback with a media-type-derived extension.
    ///
    /// The component is cut from the string itself rather than through a `URL`.
    /// `URL(string:)` would parse the name as a URL, so `Rechnung #123.pdf`
    /// loses everything from the `#` on, including its extension. And
    /// `URL(fileURLWithPath:)` resolves relative paths against the process's
    /// working directory, which turns `.` or `a/..` into the name of a real
    /// directory instead of a value the guard below can reject.
    private func safeName(for part: AttachmentPart) -> String {
        if let raw = part.filename {
            let component = raw.split(separator: "/").last.map(String.init) ?? ""
            if component.isEmpty == false, component != ".", component != ".." {
                return component
            }
        }

        let name = "unnamed"
        if let ext = UTType(mimeType: part.mediaType)?.preferredFilenameExtension {
            return "\(name).\(ext)"
        }
        return name
    }

    /// Returns `base` if free, otherwise inserts a `-1`/`-2`/… suffix before the
    /// extension. Records the chosen name in `taken`.
    private func uniqueName(_ base: String, taken: inout Set<String>) -> String {
        if taken.insert(base).inserted {
            return base
        }

        let url = URL(fileURLWithPath: base)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent

        var counter = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            if taken.insert(candidate).inserted {
                return candidate
            }
            counter += 1
        }
    }
}
