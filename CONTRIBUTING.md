# Contributing to mail2md

This is a small tool with one author and a deliberately narrow scope.

Issues and pull requests are welcome. The conventions below are strict, and they are written down so that following them is a matter of reading rather than guessing. Nothing here is a matter of taste being enforced after the fact.

## Getting started

```sh
swift build            # debug build
swift test             # the full suite
swift build -c release # must stay warning-free
make install           # installs to /usr/local/bin
```

Requires Swift 6 and macOS 13 or later. There is no formatter and no linter, on purpose (see [Layout and style](#layout-and-style)).

## What belongs in this tool

mail2md is a **deterministic converter**. It parses what the mail says and writes it out. It does not guess.

That line is worth knowing before you build something, because it is why some obvious-looking features are not here:

- **No thread splitting.** One `.eml` produces one `.md`. Cutting a quoted chain into one note per message is a judgment call: interleaved replies have no clean boundary, and quote separators are client- and language-specific with no RFC to lean on. Earlier versions did split; it was removed in v0.9.0 because the heuristic was confidently wrong often enough to be worse than nothing.
- **No boilerplate stripping.** Signatures, legal disclaimers and footers are prose without a reliable marker. Same problem as above.
- **No vault-specific knowledge.** Filenames, wikilinks, and per-message `via:` chains belong to whoever consumes the output, not to a converter that knows nothing about the target.

Judgment-heavy work belongs to the human or the LLM downstream. Mechanical work belongs here. A pull request that moves the line is welcome as a discussion first.

## Conventions

These are not negotiable, and they apply to sources and tests alike.

- **English** for code comments, identifiers, CLI text, and commit messages.
- **Explicit `self.`** for member access.
- **File header comment**, matching the existing files:
  `//  <File>.swift  //  mail2md  //  Created by <author> on DD.MM.YYYY.`
- **Group code with `// MARK: -`** and extensions, rather than one large type body.
- **Bump `static let version`** in `Mail2md.swift` with every user-visible change.

### Tests

- **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- **One test file per source file**, named after it: `BodyCleanerTests.swift` covers `BodyCleaner.swift`. A file holds more than one suite where its source does more than one job: `EMLParserTests.swift` adds `BodySelectionTests`, `InvisibleTextTests` and `AttachmentsTests`, because body selection, the invisible-character rule on a whole mail and attachment selection live in `EMLParser`; `MarkdownRendererTests.swift` adds `AttachmentBlockTests` and `FrontmatterContractTests`, because the closing attachment block and the frontmatter's key set are the renderer's; and `HTMLToMarkdownTests.swift` adds one suite per layout concern (`BlockLayoutTests`, `HiddenElementTests`, `PreformattedTextTests`, `TableTests`) plus `SenderStackTests`, one constructed snippet per sender stack with the whole expected note.
- **Shared EML fixtures live in `EMLFixtures.swift`**, not in whichever suite happened to need one first.
- **`Mail2mdTests.swift` is the acceptance suite** and the only one that leaves the process: each test launches the built binary and pins one thing a user can observe (the file that appears, an exit code, an exact stderr line, an empty stdout). Add to it when you change what the command *does*; leave parsing and rendering detail to the library suites, which are cheaper and say more precisely where a break is. Its subprocess plumbing lives in `CommandRunner.swift`, beside the suite for the same reason the fixtures do.
- **Fixtures are inline multiline strings** with explicit `\r` line endings. Those are two-character escapes inside the literal, not real carriage returns, so reindenting them is safe and a careless search-and-replace is not.
- **Never a real email.** Anonymize every address to `@example.com`, keep bodies neutral, and use no real names. This one has been broken before; see the checklist below for the one-line command that catches it.
- Cover the shapes that actually break parsers: `multipart/alternative` with a boundary, quoted-printable with multi-byte `=XX` and soft breaks, base64, RFC 2047 encoded words, a non-UTF-8 charset, a `text/plain` file attached beside the body, and a body split around an attachment. For HTML, build the snippet in the shape its sender stack really sends (Gmail, Apple Mail, Outlook, React Email), and write invisible characters as `\u{…}` escapes, so the fixture can be read.

### Output and errors

- Error style is Unix: `mail2md: <path>: <message>`.
- **Everything printed goes to stderr.** The product of this tool is the Markdown file, not the console text, so stdout stays empty: `2>/dev/null` then silences the noise and nothing else, and stdout stays free for the planned piping mode.
- All output goes through `printIf`, including unconditional messages as `printIf(true, …)`. Pass `to: .standardOutput` only for output that is genuinely data.

## Layout and style

The style was set by hand across the sources and is the reference. **When in doubt, copy the shape of the surrounding code.** Please do not run a formatter over this repo (see the note at the end of this section).

- **No `!` as a negation, anywhere.** Write the comparison out: `self.force == false`, `value.isEmpty == false`, `filter { $0.isWhitespace == false }`, and in a test `#expect(written.contains("x") == false)`. A leading `!` is one character that flips a meaning and is easy to read past.
- **No single-line bodies.** Every `if`, `guard` and `else` body goes on its own line between braces, even `return nil`. So never `guard let x else { return nil }`.
- **Always write `return` out**, including in computed properties, which therefore do not get a one-line form. Closures are exempt, because there the expression *is* the argument.
- **`catch` starts its own line**, under the closing brace of the `do` block, never cuddled as `} catch`.
- **Line length is not a limit.** A signature or a call stays on one line even at 150 characters. Breaking a line is a way to show structure, not a way to obey a number.
- **An assignment stays with its receiver.** `var text = body` on one line, the method chain indented below it. Never a break directly after the `=`.
- **Multiple conditions:** in an `if let`, following conditions line up under the first and the brace stays at the end of the last one. In a `guard` with several conditions, `guard` stands alone, the conditions are indented below it, and `else {` gets its own line.
- **Name the intermediate value** where control flow starts: the sequence a `for` loop walks, and the value an `append` receives. The loop header then reads as a loop header.
- **Column alignment in literal tables is intentional**, such as the extra space in `"UT":  "+0000"` that lines the offsets up. Keep it.
- **Build an object once, not per iteration**, such as the single `DateFormatter` before the loop in `parseDate`.

> **Why there is no formatter here.** `.swift-format` was tried and removed the same day. Three of the rules above sit in its pretty-printer and cannot be configured away: it breaks after `=` before a method chain, it cuddles `} catch`, and it collapses alignment spaces. Measured against the hand-set version it wanted to rewrite 113 lines, and still 32 at any line width. A tool that fights the author is worse than no tool.

## Before you open a pull request

Run these. The first two are the usual ones; the rest exist because each of them has caught a real mistake in this repo.

```sh
swift test                    # all tests green
swift build -c release        # must be warning-free

# Every address in the repo must be @example.com. This is the check that
# would have caught three weeks of real addresses sitting in the fixtures.
grep -rhoE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" Sources Tests | sort -u

# No leading ! as a negation.
grep -rnE '(^|[ (\[{,=&|])![A-Za-z_(]' Sources Tests | grep -v '!='
```

Two more by eye:

- Does the change alter anything a user can see? Then bump `version`.
- Does it add a fixture? Then the address check above must still come back clean.

A rule nobody checks is decoration. That is why the commands are here and not just the rules.
