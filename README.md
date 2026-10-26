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
mail2md Mail.eml --inline-images         # also write the pictures the mail shows and embed them in place
mail2md Mail.eml --format obsidian       # write the cards a mail sets apart as Obsidian callouts
mail2md Mail.eml --verbose               # report what was parsed and written
mail2md Mail.eml -o -                    # write the note to stdout instead of a file
cat Mail.eml | mail2md -                 # read the mail from stdin, write the note to stdout
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
cc:
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

The note links every file it writes, so a filename never holds what would break the link: `#` and `|` become `-`, in a pattern and in the sender's own filename alike, and so do the brackets of a name that holds `[[` or `]]` or ends in `]`. In Obsidian a wikilink reaches no file with such a name, and for `#` no other link does either.

The note is checked before the attachments are written and written after them: a note that would be overwritten, or a folder that takes no file, stops the run while the attachment directory is still untouched, and a note never links a file that could not be written.

## Inline images

A picture a mail shows from one of its own parts, through a `cid:` address, may be the screenshot the message is about or the logo in a signature, and nothing in the mail tells the two apart reliably: across 716 real mails, social icons were stored at 2636 × 2636 pixels and signature banners had the shape of screenshots. So mail2md does not guess. By default it leaves these pictures out of the note and names each one on stderr, with the size a browser shows it at:

```
mail2md: Mail.eml: inline images left out: image001.png 474×464, image002.png 24×24 (use --inline-images to include them)
```

`--inline-images` writes every one of them as a file, like an attachment and under the same naming pattern, and embeds it where the mail shows it. Whoever reads the note keeps what is content and deletes the rest.

```sh
mail2md Mail.eml --inline-images --attachments-dir ./attachments \
  --attachment-name "{date:yyyy.MM.dd} {time:HH.mm} ENCL {name}"
```

```markdown
attachments:
  - "[[2026.09.07 10.00 ENCL image001.png]]"
  - "[[2026.09.07 10.00 ENCL image002.png]]"
---

Hallo Anton,

hier der Ausschnitt aus dem Portal:

![[2026.09.07 10.00 ENCL image001.png]]

Gruss
Jane
![[2026.09.07 10.00 ENCL image002.png|LinkedIn]]
```

The alt text becomes the embed's alias where it says something about the picture, so not where it is empty, a file name, or the description Office writes in by itself. A link around a picture is dropped and the picture stays, because Obsidian does not show an embed inside a link; the links around pictures in that archive led from logos and icons. Embedding changes no layout: whether a table holds data is decided as if its pictures were not there, so a logo beside a signature does not turn it into one.

A picture Apple Mail places in the middle of a message arrives as a part of its own, between two pieces of text. That one counts as an attachment, listed and extracted like a document placed there.

## Cards

Some mails set their content apart in boxes: a card per person, a summary under a heading, a banner with a total. A box framed on all four sides or on a colour of its own, more than one line long and headed by a line all in bold, stands in the note between two rules, which any Markdown shows. With `--format obsidian` it becomes a callout instead, its bold line the title:

```markdown
> [!quote] Jane Doe
> 01.01.1990, female
>
> | Before: | New for 2027: |
> |---|---|
> | Insurer A | Insurer B |
> | Family doctor | Telemedicine |
>
> Premium per month CHF **250.00**
>
> **Change confirmed**
```

Only the outermost box is a card, never one inside another, and never the box holding the mail's last line, which is its footer. Inside, a one-line box in light text on a dark colour is a button and is set in bold, and columns that MJML sets side by side pair up as a table where each holds as many lines as the others.

## Pipes

`-` as the path reads the mail from stdin, and the note then goes to stdout. `-o -` sends it there for a mail read from a file too, so a script or an agent can read a mail as Markdown without a file being left behind.

```sh
cat Mail.eml | mail2md - > Note.md
mail2md Mail.eml -o - | less
mail2md - -o Note.md < Mail.eml          # from stdin into a file
```

Only the dash reads stdin. A missing path is an error even when stdin is not a terminal, because a program run by an agent or an editor can be handed a stdin that never ends, and the tool would wait there instead of saying what is missing.

The note on stdout is byte for byte the file mail2md would write, and stdout carries nothing else: the warnings and `--verbose` stay on stderr, where messages name the input `(standard input)`. A stream has nothing to compare against, so there is no conflict check and `--force` changes nothing. Attachments need a place of their own, since a note on stdout is written into no directory they could go next to: with `--extract-attachments`, `--attachment-name` or `--inline-images`, pass `--attachments-dir` too, or the command line is refused.

## How it compares

**The Obsidian plugins mostly view rather than convert.** MSG Handler, EML Email Viewer, Email Reader and Embed EML render the mail inside Obsidian, but the file stays an `.eml`. It never becomes a note, and one of them states outright that its content does not reach Obsidian's global search.

**The standalone converters I found write the metadata into the prose.** An H1 with the subject, then a bullet list or a table of From/To/Date, then the body. That is readable, and it is text. It is not something a vault can query: you cannot sort by `created`, filter by `from`, or list every mail that carried an attachment.

mail2md writes the metadata as YAML frontmatter, so the output is a note first and prose second. The rest of the design follows from that: timestamps in the reader's local time, so `created` sorts correctly beside your other notes, and attachment filenames as a flow list, so a query can reach them.

It is also built to be fast and unremarkable to use. Across 716 real mails the median conversion takes under 30 ms on an M1, there is nothing to configure, and nothing has to be running.

**[Postbox](https://github.com/istefox/Postbox)** is the closest alternative, and parts of it are better: it reads `.msg` and de-duplicates by Message-ID. It is an Obsidian plugin, so it is desktop-only and Obsidian has to be open. mail2md is the better fit when the conversion should happen without Obsidian in the loop: in a shell pipeline, a cron job, a Makefile, or on a machine with no GUI.

## Status

Parses single-part, `multipart/alternative` (reads the last form it can show, as RFC 2046 orders them, so the HTML one where there is one, and the plain one when the HTML shows nothing) and `multipart/mixed` messages, decodes quoted-printable and base64 transfer encodings, and decodes RFC 2047 encoded-word headers. A filename continued over several parameters or encoded in a charset of its own (RFC 2231) is read whole, as Apple Mail writes every long or non-ASCII one, and so is one with a `;` inside its quotes. Each address in `from`, `to` and `cc` is written as `Name <address>`, or as the bare address where the name only repeats it, with quotes only around a name whose comma would otherwise split the list, and a name quoted word by word, `"Muster" "AG"`, as its words. In a `multipart/mixed` message every inline text part is read in order, so text that continues after an attachment placed mid-message is kept, and an attached text file never stands in for the body. Converts HTML to Markdown, lists attachment filenames in the frontmatter, and optionally extracts attachment files to disk under a naming scheme of your choosing, linking them from the note (S/MIME signature parts are excluded; extracted filenames are sanitised, so a crafted header cannot write outside the target directory).

HTML is laid out the way a browser shows it: a table of data becomes a Markdown table, a table used for layout becomes lines of text, an element the mail hides in its own style stays out (the preview text a newsletter tucks in front of its content), and preformatted text becomes a code block. Bold and italics count where the style sets them as much as where a `b` or an `i` does, and end where a child's style sets them back, a link whose target holds a space stays a link, a list whose style hides its bullets is a stack of lines, an empty block of a set height leaves a blank line where a browser leaves space, and a card the mail sets apart stays apart (see Cards).

Invisible characters that never belong in running text are removed: the zero-width fillers behind that preview text, Unicode tag characters outside a flag, a stray zero-width space or byte order mark. Those that can belong there but also change how text reads, a zero-width joiner outside an emoji, direction marks and bidi controls, stay and are counted. Either way one line on stderr says what was found, so text a reader cannot see does not reach a vault, or a language model reading it, unnoticed.

A named document that Apple Mail dispositions as `inline` rather than `attachment` still counts as an attachment, since that is how a real PDF often arrives, and so does a picture Apple Mail places between two pieces of text. Any other inline image is no attachment but a picture the message shows in its place: left out and named, or embedded with `--inline-images` (see Inline images).

`created` is rendered in the reader's local time, not the sender's. The `Date:` header is parsed tolerantly: trailing comments like `+0000 (UTC)`, a missing weekday or seconds, and obsolete alphabetic zones are all handled, and a header that still cannot be parsed produces a warning rather than a silently empty `created`.

Bodies pass through a lossless cleanup: angle-bracket duplicates of mail and web addresses are collapsed onto their plain twin, Outlook's Safelinks wrapper of a link included, `cid:` image references are dropped with the line they leave empty, as are two things a mail system writes in rather than the sender (the banner Exchange puts above mail from a new sender, "You don't often get email from …", and a link around a quoted picture's file name, such as a social icon in an old signature), and runs of blank lines are normalised. Quote depth (`>`) is never touched, so the structure the mail carried survives.

All diagnostics, including `--verbose` progress, go to stderr. The product is the note, so stdout carries only data, the note when it is asked for there, the help and the version, and `2>/dev/null` silences the tool without hiding anything else.

A mail file that is not UTF-8, as old mail in Latin-1 often is, is read in the charsets it declares, each part in its own. Text labelled ISO-8859-1 or US-ASCII is read as Windows-1252, which is what the WHATWG Encoding Standard makes of those labels, so the curly quotes, dashes and euro sign that many mailers send under them come through as characters, not as invisible control codes.

An input that cannot be converted exits 1 and says why in Unix form, `mail2md: <path>: <message>`: a missing file, a directory, a file that cannot be read, or one whose bytes are neither valid UTF-8 nor in a charset the file declares. Nothing is written in those cases, so the tool is safe to use in a pipeline that checks the exit code. A note or an attachment that cannot be written is reported the same way. A command line the tool cannot use, such as an unknown option, a missing path or an unknown placeholder in `--attachment-name`, exits 64, the code `sysexits(3)` gives a usage error, with the usage on stderr and before any file is read.

JSON and plain-text output are on the roadmap.

## Install

```sh
brew install antonfill/tap/mail2md
```

The formula builds from source, so it needs Xcode 16 or newer, and with it macOS 14.5 or later.

### From source

```sh
make build     # release build
make install   # installs to /usr/local/bin
swift test     # run the test suite
```

Building needs Swift 6.0 or newer, which comes with Xcode 16, and Xcode 16 needs macOS 14.5 or later. CI builds the release binary with Xcode 16.0, the oldest toolchain the package declares, and runs the test suite with the current one.

## Contributing

Issues and pull requests are welcome. The conventions are strict and written down: see `CONTRIBUTING.md` before you start, particularly the scope section on what this tool deliberately does not do.

## License

MIT. See `LICENSE`.
