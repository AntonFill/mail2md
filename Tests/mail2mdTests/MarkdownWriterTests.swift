//
//  MarkdownWriterTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 05.08.2026.
//

import Foundation
import Testing
@testable import mail2md

struct MarkdownWriterTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mail2md-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The code of the Cocoa error `body` throws, nil where it throws none.
    private func code(_ body: () throws -> Void) -> CocoaError.Code? {
        do {
            try body()
            return nil
        }
        catch let error as CocoaError {
            return error.code
        }
        catch {
            return nil
        }
    }

    @Test func writesNewFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.md")
        let b = dir.appendingPathComponent("b.md")

        let written = try MarkdownWriter(force: false).writeAll([
            .init(url: a, content: "Alpha"), .init(url: b, content: "Beta"),
        ])

        #expect(Set(written) == [a, b])
        #expect(try String(contentsOf: a, encoding: .utf8) == "Alpha")
        #expect(try String(contentsOf: b, encoding: .utf8) == "Beta")
    }

    @Test func skipsIdenticalContent() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.md")
        try "Alpha".write(to: a, atomically: true, encoding: .utf8)

        // Identical target is neither rewritten nor reported as written.
        let written = try MarkdownWriter(force: false).writeAll([.init(url: a, content: "Alpha")])

        #expect(written.isEmpty)
        #expect(try String(contentsOf: a, encoding: .utf8) == "Alpha")
    }

    @Test func conflictAbortsBeforeWritingAnything() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let new = dir.appendingPathComponent("new.md")
        let existing = dir.appendingPathComponent("existing.md")
        try "old".write(to: existing, atomically: true, encoding: .utf8)

        // The batch has a fresh file and a diverging one; the pre-flight must
        // stop the whole write, so the fresh file is never created.
        #expect(throws: MarkdownWriter.Conflict.self) {
            try MarkdownWriter(force: false).writeAll([
                .init(url: new, content: "fresh"), .init(url: existing, content: "changed"),
            ])
        }
        #expect(FileManager.default.fileExists(atPath: new.path) == false)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "old")
    }

    /// The check says what writing would run into, and writes nothing.
    @Test func checkFindsAConflictWithoutWriting() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = dir.appendingPathComponent("existing.md")
        try "old".write(to: existing, atomically: true, encoding: .utf8)

        #expect(throws: MarkdownWriter.Conflict.self) {
            try MarkdownWriter(force: false).check([.init(url: existing, content: "changed")])
        }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "old")
        try MarkdownWriter(force: true).check([.init(url: existing, content: "changed")])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "old")
    }

    /// A folder that is missing or that may not be written to takes no file,
    /// unless the file is there already as it would be written.
    @Test func checkRefusesAFolderThatTakesNoFile() throws {
        let dir = try makeTempDirectory()
        let locked = dir.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        let same = locked.appendingPathComponent("same.md")
        try "same".write(to: same, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let writer = MarkdownWriter(force: false)

        // The error says why, under --verbose.
        #expect(self.code { try writer.check([.init(url: locked.appendingPathComponent("new.md"), content: "new")]) } == .fileWriteNoPermission)
        #expect(self.code { try writer.check([.init(url: dir.appendingPathComponent("missing/new.md"), content: "new")]) } == .fileNoSuchFile)
        try writer.check([.init(url: same, content: "same")])
        try writer.check([.init(url: dir.appendingPathComponent("new.md"), content: "new")])
        #expect(FileManager.default.fileExists(atPath: locked.appendingPathComponent("new.md").path) == false)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.md").path) == false)
    }

    @Test func forceOverwritesDivergingFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.md")
        try "old".write(to: a, atomically: true, encoding: .utf8)

        let written = try MarkdownWriter(force: true).writeAll([.init(url: a, content: "new")])

        #expect(written == [a])
        #expect(try String(contentsOf: a, encoding: .utf8) == "new")
    }
}
