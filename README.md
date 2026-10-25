# biblioteca

A native macOS (SwiftUI) app that converts books between PDF, EPUB, MOBI, AZW3, DjVu, FB2 and more.

## Build

```bash
xcodegen generate
xcodebuild -project Biblioteca.xcodeproj -scheme Biblioteca -configuration Release -derivedDataPath build/DerivedData build
```

Tests are hostless: they compile the engine sources directly and never launch the app.

```bash
xcodebuild test -project Biblioteca.xcodeproj -scheme Biblioteca -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

## Engines

biblioteca uses whichever converters are installed. When several can do a job, the earlier one in this list wins. When none converts directly, the route goes through PDF (e.g. DjVu → PDF → EPUB).

| Engine | Install | Conversions |
|---|---|---|
| Calibre (`ebook-convert`) | `brew install --cask calibre` | EPUB, MOBI, AZW3, FB2, DOCX, RTF, TXT, PDF ↔ each other |
| DjVuLibre (`ddjvu`, `cjb2`, `c44`, `djvm`, `djvused`, `djvutxt`) | `brew install djvulibre` | DjVu → PDF/TXT, PDF → DjVu (black & white or color, with searchable text) |
| MuPDF (`mutool`) | `brew install mupdf-tools` | EPUB, MOBI, FB2, CBZ, XPS, HTML, TXT → PDF; → TXT |
| built in (PDFKit) | — | PDF → EPUB, PDF → TXT |

If an engine fails on a step, the next installed engine that can do the same step is tried.

Limits:
- PDF → EPUB needs a text layer; scanned PDFs need OCR first.
- DjVu → PDF (and so DjVu → EPUB/MOBI) gives page images. `ddjvu` does not carry the DjVu text layer into the PDF; use DjVu → TXT for the text.
- DjVuLibre's `djvm` mangles non-ASCII file names when no UTF-8 locale is set, so the DjVu engine runs its tools on ASCII-named copies (`ASCIIStaging`).
