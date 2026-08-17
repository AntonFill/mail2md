//
//  CommandRunner.swift
//  mail2md
//
//  Created by Anton Fillmann on 17.08.2026.
//

import Foundation
@testable import mail2md

/// Launches the built `mail2md` binary for the acceptance suite: a throwaway
/// workspace on disk, the `.eml` fixtures written into it, and one subprocess
/// run per invocation.
///
/// Infrastructure rather than a test file, in its own file for the same reason
/// `EMLFixtures.swift` exists: `Mail2mdTests.swift` should read as the list of
/// contracts the command keeps, not as process plumbing.
struct CommandRunner {

    /// Creates the workspace the run happens in. Every test gets its own, so
    /// runs cannot see each other's files.
    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mail2md-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        self.workspace = url
    }

    let workspace: URL

    /// What one invocation of the command left behind.
    struct Invocation {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    /// Thrown when the built binary cannot be found, so a failure reads as
    /// "the test setup is broken" rather than "the command misbehaved".
    struct BinaryNotFound: Error, CustomStringConvertible {
        let reason: String

        var description: String {
            return "built \(Mail2md.appname) binary not found: \(self.reason)"
        }
    }
}

// MARK: - Running
extension CommandRunner {

    /// Runs the built binary with `arguments` in the workspace and collects both
    /// streams.
    ///
    /// The streams are redirected into files rather than `Pipe`s: a pipe has to
    /// be drained while the child still runs, and draining two of them one after
    /// the other can block on the one not being read. Files cannot deadlock.
    /// They live in their own subdirectory, so a test may inspect the workspace
    /// itself by name.
    ///
    /// `TZ` is pinned to UTC, because `created` renders in the reader's local
    /// zone: an unpinned zone would make the expected frontmatter depend on the
    /// machine running the tests. UTC also keeps the conversion visible, since a
    /// fixture written at `+0200` has to come out two hours earlier: a regression
    /// that rendered the sender's own offset would fail here rather than cancel out.
    ///
    /// The rest of the environment is inherited, and that is load-bearing for the
    /// coverage number: under `--enable-code-coverage` the child picks up
    /// `LLVM_PROFILE_FILE` from it and writes into the same merge pool, which is
    /// how `Mail2md.swift` is counted at all. Measured on 2026-08-17: inherited
    /// 97 % of its lines, with a hand-built environment 0 %, tests green either
    /// way. The tests do not need it; the number does.
    func run(_ arguments: [String]) throws -> Invocation {
        let streams = self.workspace.appendingPathComponent("streams")
        try FileManager.default.createDirectory(at: streams, withIntermediateDirectories: true)
        let outputURL = streams.appendingPathComponent("stdout.log")
        let errorURL = streams.appendingPathComponent("stderr.log")
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)

        let process = Process()
        process.executableURL = try self.binaryURL()
        process.arguments = arguments
        process.currentDirectoryURL = self.workspace
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        var environment = ProcessInfo.processInfo.environment
        environment["TZ"] = "UTC"
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()

        return Invocation(
            exitCode: process.terminationStatus,
            standardOutput: try String(contentsOf: outputURL, encoding: .utf8),
            standardError: try String(contentsOf: errorURL, encoding: .utf8)
        )
    }

    /// The built binary, found by walking up from this test code's own image
    /// until a directory holds an executable named like the command.
    ///
    /// The SwiftPM idiom (`Bundle.allBundles`, take the `.xctest` one) does not
    /// work here, measured on 2026-08-17: `swift test` loads the test code as a
    /// library into `swiftpm-testing-helper`, so `Bundle.main` points into the
    /// toolchain and no `.xctest` bundle is registered. Asking the dynamic linker
    /// where this very code sits holds for `swift test`, for `-c release` and
    /// inside Xcode's DerivedData, because the products directory is always the
    /// one above the test bundle.
    func binaryURL() throws -> URL {
        var image = Dl_info()

        guard dladdr(#dsohandle, &image) != 0,
            let imagePath = image.dli_fname
        else {
            throw BinaryNotFound(reason: "the dynamic linker does not know where the test code lives")
        }

        let start = URL(fileURLWithPath: String(cString: imagePath)).deletingLastPathComponent()
        var directory = start

        // …/debug/mail2mdPackageTests.xctest/Contents/MacOS is three levels below
        // the products directory; the extra steps cover a different bundle layout.
        for _ in 0..<5 {
            let candidate = directory.appendingPathComponent(Mail2md.appname)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)

            if exists, isDirectory.boolValue == false, FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }

            directory = directory.deletingLastPathComponent()
        }

        throw BinaryNotFound(reason: "no executable above \(start.path)")
    }
}

// MARK: - Files in the workspace
extension CommandRunner {

    /// Writes an inline fixture into the workspace as the `.eml` the command reads.
    func write(_ eml: String, named name: String) throws -> URL {
        let url = self.workspace.appendingPathComponent(name)
        try eml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes raw bytes into the workspace, for input that is deliberately not
    /// decodable text.
    func write(_ bytes: Data, named name: String) throws -> URL {
        let url = self.workspace.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    /// A path in the workspace, existing or not.
    func path(_ name: String) -> URL {
        return self.workspace.appendingPathComponent(name)
    }

    /// Whether the workspace holds a file of that name.
    func exists(_ name: String) -> Bool {
        return FileManager.default.fileExists(atPath: self.path(name).path)
    }

    /// The contents of a file in the workspace.
    func read(_ name: String) throws -> String {
        return try String(contentsOf: self.path(name), encoding: .utf8)
    }

    /// Drops the whole workspace. Called from a `defer` in every test.
    func removeWorkspace() {
        try? FileManager.default.removeItem(at: self.workspace)
    }
}
