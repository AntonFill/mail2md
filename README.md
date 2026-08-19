# mail2md

[![CI](https://github.com/AntonFill/mail2md/actions/workflows/ci.yml/badge.svg)](https://github.com/AntonFill/mail2md/actions/workflows/ci.yml)

Convert `.eml` files to Markdown with YAML frontmatter. Built for Obsidian vaults, paperless archives, and AI-ready personal data pipelines.

Part of a family of local-first CLI tools ([realdate](https://github.com/AntonFill/realdate), mail2md) that make personal data usable without it ever leaving your Mac.

## Usage

```sh
mail2md Mail.eml                         # → Mail.md
mail2md Mail.eml -o Note.md              # explicit output path
mail2md Mail.eml --force                 # overwrite output files that differ from the generated Markdown
mail2md Mail.eml --extract-attachments   # also write attachment files alongside the output
mail2md Mail.eml --attachments-dir ./att # write attachments into ./att (implies extraction)
mail2md Mail.eml --attachment-name "{date} {time} ENCL {name}"   # rename them as they are written
mail2md Mail.eml --verbose               # report what was parsed and written
mail2md --version
mail2md --help
```

**One `.eml` in, one `.md` out.** A quoted reply chain stays in a single file, exactly as the mail carried it. Splitting a thread into one note per message is a judgment call, not a parse: interleaved replies have no clean boundary, and quote separators are client- and language-specific with no RFC to lean on. A converter that guesses there produces confident garbage, so mail2md leaves that to whoever knows the context. (Earlier versions did split; it was removed in v0.9.0 for exactly this reason.)

Output is never silently overwritten: a target that already exists with identical content is skipped, one that differs aborts with an error unless you pass `--force`.

Output format:

```markdown
---
created: 2026-06-15T09:41
from: "Jane Doe <jane@example.com>"
to: "Anton Fillmann <anton@example.com>"
via:
subject: "Projektanfrage iOS"
attachments:
---

Hallo Anton,

...
```

## Attachments

By default the frontmatter names the attachments and nothing else happens to them, because a note cannot link a file that was never written.

Ask for extraction and the note starts pointing at real files. `attachments` becomes a list of wikilinks, and the body ends with the attachments themselves: images embedded two per row, documents linked. No heading and no rule, since a mail client shows its attachments below the text without announcing them.

```sh
mail2md Mail.eml --attachments-dir ./attachments \
  --attachment-name "{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}"
```

```markdown
attachments:
  - "[[2026.08.18 07.52 ENCL Foto.JPG]]"
  - "[[2026.08.18 07.52 ENCL Auftrag.pdf]]"
---

Gesendet von Outlook für iOS

|  |  |
|---|---|
| ![[2026.08.18 07.52 ENCL Foto.JPG]] |  |

[[2026.08.18 07.52 ENCL Auftrag.pdf|Auftrag.pdf]]
```

`--attachment-name` is how a naming scheme gets in without the tool having to know one. Four placeholders: `{name}` (the filename without its extension), `{ext}` (the extension, dot included), and `{date}`/`{time}`, which render the **mail's** timestamp so an attachment sorts behind the mail it came with. Those two take a `DateFormatter` pattern after a colon, `{date:yyyy.MM.dd}`, and default to `yyyy-MM-dd` and `HH-mm`. A pattern that does not place `{ext}` itself gets the extension appended, and a `/` in the result becomes `-`, so a pattern can never write outside its directory. A document that was renamed keeps the sender's own filename as the link's alias.

The note is written before the attachments, so a note that would be overwritten stops the run while the attachment directory is still untouched.

## How it compares

**The Obsidian plugins mostly view rather than convert.** MSG Handler, EML Email Viewer, Email Reader and Embed EML render the mail inside Obsidian, but the file stays an `.eml`. It never becomes a note, and one of them states outright that its content does not reach Obsidian's global search.

**The standalone converters I found write the metadata into the prose.** An H1 with the subject, then a bullet list or a table of From/To/Date, then the body. That is readable, and it is text. It is not something a vault can query: you cannot sort by `created`, filter by `from`, or list every mail that carried an attachment.

mail2md writes the metadata as YAML frontmatter, so the output is a note first and prose second. The rest of the design follows from that: timestamps in the reader's local time, so `created` sorts correctly beside your other notes, and attachment filenames as a flow list, so a query can reach them.

It is also built to be fast and unremarkable to use. A 57 KB mail with a four-deep quoted chain and an S/MIME signature converts in about 25 ms on an M1, there is nothing to configure, and nothing has to be running.

**[Postbox](https://github.com/istefox/Postbox)** is the closest alternative, and parts of it are better: it renders inline `cid:` images, keeps HTML tables, reads `.msg`, and de-duplicates by Message-ID. It is an Obsidian plugin, so it is desktop-only and Obsidian has to be open. mail2md is the better fit when the conversion should happen without Obsidian in the loop: in a shell pipeline, a cron job, a Makefile, or on a machine with no GUI.

## Status

Parses single-part, `multipart/alternative` (prefers `text/plain`) and `multipart/mixed` messages, decodes quoted-printable and base64 transfer encodings, and decodes RFC 2047 encoded-word headers. Converts html-only mails to Markdown, lists attachment filenames in the frontmatter, and optionally extracts attachment files to disk under a naming scheme of your choosing, linking them from the note (S/MIME signature parts are excluded; extracted filenames are sanitised, so a crafted header cannot write outside the target directory).

A named document that Apple Mail dispositions as `inline` rather than `attachment` still counts as an attachment, since that is how a real PDF often arrives. Inline *images* do not: a named inline image is a signature logo or a tracking pixel far more often than a file someone meant to send.

`created` is rendered in the reader's local time, not the sender's. The `Date:` header is parsed tolerantly: trailing comments like `+0000 (UTC)`, a missing weekday or seconds, and obsolete alphabetic zones are all handled, and a header that still cannot be parsed produces a warning rather than a silently empty `created`.

Bodies pass through a lossless cleanup: angle-bracket duplicates of mail and web addresses are collapsed onto their plain twin, `cid:` image references are dropped, and runs of blank lines are normalised. Quote depth (`>`) is never touched, so the structure the mail carried survives.

All diagnostics, including `--verbose` progress, go to stderr. The product is the Markdown file, so stdout carries only genuine data (today just `--version`) and `2>/dev/null` silences the tool without hiding anything else.

An input that cannot be converted exits non-zero and says why in Unix form, `mail2md: <path>: <message>`: a missing file, a directory, a file that cannot be read, or one whose bytes are not valid UTF-8. Nothing is written in those cases, so the tool is safe to use in a pipeline that checks the exit code.

JSON/text output and stdin/stdout piping are on the roadmap.

## Install

```sh
brew install antonfill/tap/mail2md
```

The formula builds from source, so Xcode 16 or newer has to be installed.

### From source

```sh
make build     # release build
make install   # installs to /usr/local/bin
swift test     # run the test suite
```

Requires Swift 6.0 or newer (Xcode 16+), built and tested against Swift 6.3. Runs on macOS 13+.

## Contributing

Issues and pull requests are welcome. The conventions are strict and written down: see `CONTRIBUTING.md` before you start, particularly the scope section on what this tool deliberately does not do.

## License

MIT. See `LICENSE`.
