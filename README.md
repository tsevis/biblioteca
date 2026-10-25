# biblioteca

<img src="documents/icon.png" width="128" align="right" alt="biblioteca's icon: a shelf of coloured book spines on deep blue, the last volume leaning on the others.">

A native macOS app that converts books between **PDF, EPUB, MOBI, DjVu,
FB2** and more. Everything it needs is inside the app: nothing to install. Drop books on the window, choose what they should become, and
press Convert.

**Version 0.2.0.** SwiftUI, macOS 15 or later. See [CHANGELOG.md](CHANGELOG.md).

---

## What it does

- **Two tabs.** *Convert* is for everyday conversions: drop books or folders
  on the window or the Dock icon, click the empty window to choose them, use
  *Open With* in Finder, or press ⌘O. *Batch* is for whole libraries: add
  books and folders, and every book in them and their subfolders is
  converted into one output folder that keeps the same folder structure.
  Books already converted by an earlier run, and books already in the target
  format, are skipped. A search field above the Batch list narrows it by
  name and folder, and Convert then takes only the books shown. Each book
  shows its route
  (e.g. `DjVu → EPUB · DjVuLibre → built in`), its progress and its result.
- **Never touches the originals.** Results go beside each original or into a
  folder you choose. An existing file is never overwritten: the new one becomes
  `Book 2.pdf`. A conversion that fails or is stopped leaves nothing behind.
- **Stands alone.** MuPDF, DjVuLibre and Tesseract (with its English, Greek
  and polytonic Greek models) are copied into the app when it is built, so it
  runs on a Mac with nothing installed. Each book is routed through them and
  biblioteca's own converters, going through PDF when no single tool can do
  the whole job. If one tool fails on a step, the next one that can do the same
  step is tried.
- **Reads PDFs itself.** PDF → EPUB and PDF → TXT work with nothing installed:
  PDFKit extracts the text and paragraphs are rebuilt from where each line sits
  on the page, with words hyphenated across lines joined again.
- **Makes searchable DjVu.** PDF → DjVu encodes pages in black and white (small
  files, right for text) or in colour, and copies the PDF's text into the DjVu.
- **Reads scans (OCR).** With *OCR scans* on, scanned PDF and DjVu pages are
  recognised on this Mac: Apple Vision for the languages it reads, Tesseract
  for Greek, which Vision does not. A scanned PDF becomes a searchable PDF
  that looks the same, a scanned DjVu gains a text layer, and either can
  become EPUB, DjVu or TXT, built from the recognised text rather
  than page pictures. Pages that already have text are left alone.
- **Stays on this Mac.** Nothing is uploaded anywhere.

## Engines

Reads PDF, EPUB, MOBI, DjVu, FB2, CBZ, XPS, HTML, TXT, DOCX and RTF; writes
PDF, EPUB, DjVu and TXT. AZW3 is not supported. Settings → Engines lists the
tools; all of them come inside the app. When several engines can do a job,
the one higher in this table wins.

| Engine | Licence | Conversions |
|---|---|---|
| DjVuLibre (`ddjvu`, `cjb2`, `c44`, `djvm`, `djvused`, `djvutxt`) | GPL 2 | DjVu → PDF/TXT; PDF → DjVu; DjVu title and author |
| MuPDF (`mutool`) | AGPL 3 | EPUB, MOBI, FB2, CBZ, XPS, HTML, TXT → PDF; → TXT |
| built in (PDFKit, TextKit) | — | PDF → EPUB, PDF → TXT; DOCX, RTF → PDF; EPUB and PDF title, author, cover |
| Apple Vision | — | OCR in English, French, German, Italian, Spanish, Portuguese |
| Tesseract (`tesseract`) | Apache 2 | OCR in Greek, monotonic and polytonic |

Because MuPDF is AGPL and DjVuLibre GPL, a copy of biblioteca given to anyone
else must come with an offer of those tools' source code.

## Settings

- **Page size** (A4, A5, US Letter) for books that have no pages of their own,
  such as EPUB or MOBI, when they become PDF.
- **DjVu pages**: *Black & white* (default, for text) or *Color* (keeps
  pictures). On a page of plain text at 300 dpi, black and white came to about
  9 KB and colour to about 1.4 MB.
- **DjVu resolution**: 150 to 600 dpi.
- **Language of scans** for OCR, which picks the recogniser. Greek is read
  together with English, since Greek books often quote it. *OCR scans* itself
  is switched on per tab, beside Convert.

## Limits

- PDF → EPUB needs a text layer. With *OCR scans* off, a scanned PDF fails
  with a message saying so instead of producing an empty book.
- DjVu → PDF, and therefore DjVu → EPUB, gives page images unless
  *OCR scans* is on: `ddjvu` does not carry a DjVu's text into the PDF, so
  with OCR the pages are recognised again.
- OCR rebuilds paragraphs, not layout: tables, columns and footnotes come out
  as running text. Tesseract's Greek model sometimes puts polytonic accents
  into monotonic text ("φῶς" for "φως").
- A page's first line is dropped as a running head when it carries a page
  number and nearly the same words head a page up to two pages away. A
  numbered chapter heading on a chapter shorter than three pages is dropped
  with it.
- The first Apple Vision recognition can be slow: a one-page book took 109 s
  the first time on the development Mac, and under 3 s afterwards.
- Without a UTF-8 locale, as in any app launched from Finder, DjVuLibre's
  `djvm` mangles non-ASCII file names. The DjVu engine therefore runs its tools
  on ASCII-named copies, and the result keeps its real name.

## Building

Needs Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and, on the
build Mac only, the tools that get bundled:

```bash
brew install xcodegen mupdf-tools djvulibre tesseract tesseract-lang
```

The Xcode project is generated from `project.yml` and is not checked in. A
build phase (`Scripts/bundle-tools.py`) copies the tools, the libraries they
load and the OCR models into the app, rewrites their load paths and signs
them; the Debug app came to 60 MB.

```bash
xcodegen generate
xcodebuild -project Biblioteca.xcodeproj -scheme Biblioteca -configuration Release -derivedDataPath build/DerivedData build
```

The app is at `build/DerivedData/Build/Products/Release/biblioteca.app`.

Tests are hostless: the core sources are compiled into the test bundle, so a
test run never launches the app or opens a window.

```bash
xcodebuild test -project Biblioteca.xcodeproj -scheme Biblioteca -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

The icon is drawn, and the splash-screen banner cropped from
`documents/bookshelf.jpg`, by `Scripts/make-icon.py` (Python 3 with Pillow):

```bash
python3 Scripts/make-icon.py
```

## Layout

| Folder | Contents |
|---|---|
| `Biblioteca/Model` | Formats, jobs, paper sizes |
| `Biblioteca/Engines` | The converters, the route planner, process running |
| `Biblioteca/Engines/OCR` | Recognisers, searchable PDF, DjVu text from scans |
| `Biblioteca/Services` | The conversion queue and saved preferences |
| `Biblioteca/Views` | Window, splash screen, settings, the TVD mark |
| `Biblioteca/Resources` | Icon, splash art, logo, Info.plist |
| `BibliotecaTests` | Swift Testing suites |
| `Scripts` | Icon and artwork generator |

---

Created by Charis Tsevis, with the help of Claude Code.
[tsevis.com](https://tsevis.com) · [github.com/tsevis](https://github.com/tsevis)
