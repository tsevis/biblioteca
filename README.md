# biblioteca

<img src="documents/icon.png" width="128" align="right" alt="biblioteca's icon: a shelf of coloured book spines on deep blue, the last volume leaning on the others.">

A native macOS app that converts books between **PDF, EPUB, MOBI, AZW3, DjVu,
FB2** and more. Drop books on the window, choose what they should become, and
press Convert.

**Version 0.1.0.** SwiftUI, macOS 15 or later. See [CHANGELOG.md](CHANGELOG.md).

---

## What it does

- **Converts in batches.** Drop files on the window or the Dock icon, click
  the empty window to choose them, use *Open With* in Finder, or press ⌘O. Each book shows its route
  (e.g. `DjVu → EPUB · DjVuLibre → Calibre`), its progress and its result.
- **Never touches the originals.** Results go beside each original or into a
  folder you choose. An existing file is never overwritten: the new one becomes
  `Book 2.pdf`. A conversion that fails or is stopped leaves nothing behind.
- **Uses the best tool installed.** biblioteca has no converter of its own for
  most formats. It finds Calibre, DjVuLibre and MuPDF on this Mac and routes
  each book through them, going through PDF when no single tool can do the
  whole job. If one tool fails on a step, the next one that can do the same
  step is tried.
- **Reads PDFs itself.** PDF → EPUB and PDF → TXT work with nothing installed:
  PDFKit extracts the text and paragraphs are rebuilt from where each line sits
  on the page, with words hyphenated across lines joined again.
- **Makes searchable DjVu.** PDF → DjVu encodes pages in black and white (small
  files, right for text) or in colour, and copies the PDF's text into the DjVu.
- **Stays on this Mac.** Nothing is uploaded anywhere.

## Engines

Settings → Engines shows which tools are installed and copies the install
command for any that are missing. When several engines can do a job, the one
higher in this table wins.

| Engine | Install | Conversions |
|---|---|---|
| Calibre (`ebook-convert`) | `brew install --cask calibre` | EPUB, MOBI, AZW3, FB2, DOCX, RTF, TXT, HTML, PDF to each other |
| DjVuLibre (`ddjvu`, `cjb2`, `c44`, `djvm`, `djvused`, `djvutxt`) | `brew install djvulibre` | DjVu → PDF/TXT; PDF → DjVu |
| MuPDF (`mutool`) | `brew install mupdf-tools` | EPUB, MOBI, FB2, CBZ, XPS, HTML, TXT → PDF; → TXT |
| built in (PDFKit) | — | PDF → EPUB, PDF → TXT |

## Settings

- **Page size** (A4, A5, US Letter) for books that have no pages of their own,
  such as EPUB or MOBI, when they become PDF.
- **DjVu pages**: *Black & white* (default, for text) or *Color* (keeps
  pictures). On a page of plain text at 300 dpi, black and white came to about
  9 KB and colour to about 1.4 MB.
- **DjVu resolution**: 150 to 600 dpi.

## Limits

- PDF → EPUB needs a text layer. Scanned PDFs need OCR first; biblioteca says
  so instead of producing an empty book.
- DjVu → PDF, and therefore DjVu → EPUB or MOBI, gives page images: `ddjvu`
  does not carry a DjVu's text into the PDF. DjVu → TXT gives the text.
- Without a UTF-8 locale, as in any app launched from Finder, DjVuLibre's
  `djvm` mangles non-ASCII file names. The DjVu engine therefore runs its tools
  on ASCII-named copies, and the result keeps its real name.

## Building

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project is generated from `project.yml`
and is not checked in.

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

The icon and the splash-screen art are drawn by `Scripts/make-icon.py`
(Python 3 with Pillow):

```bash
python3 Scripts/make-icon.py
```

## Layout

| Folder | Contents |
|---|---|
| `Biblioteca/Model` | Formats, jobs, paper sizes |
| `Biblioteca/Engines` | The converters, the route planner, process running |
| `Biblioteca/Services` | The conversion queue and saved preferences |
| `Biblioteca/Views` | Window, splash screen, settings, the TVD mark |
| `Biblioteca/Resources` | Icon, splash art, logo, Info.plist |
| `BibliotecaTests` | Swift Testing suites |
| `Scripts` | Icon and artwork generator |

---

Created by Charis Tsevis, with the help of Claude Code.
[tsevis.com](https://tsevis.com) · [github.com/tsevis](https://github.com/tsevis)
