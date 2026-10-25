# Changelog

## Unreleased

- OCR: an *OCR scans* switch in each tab recognises scanned PDF and DjVu
  pages, with Apple Vision where it reads the language and Tesseract for
  Greek. Scans become searchable PDFs, DjVu files gain a text layer, and EPUB,
  MOBI or TXT are built from the recognised text. The language is chosen in
  Settings → General.
- A conversion step now runs on the engine the route planned, falling back to
  the others only if it fails; before, the first capable engine always ran.
- The splash screen's banner is a photograph of a real bookshelf
  (`documents/bookshelf.jpg`), with a deeper scrim so the type stays legible.
- Folders can be dropped or chosen; every book inside them and their
  subfolders is added. Hidden files and unknown formats are ignored.
- New Batch tab: converts books and whole folders into one output folder,
  recreating the folder structure, and skips books already converted.
- The whole empty drop area is a button that opens the book picker; it
  highlights on hover.
- VoiceOver names the splash screen's links and Continue button again,
  instead of reading every one as "About biblioteca".

## 0.1.0 — 2026-10-25

First version.

- Converts between PDF, EPUB, MOBI, AZW3, DjVu, FB2, CBZ, XPS, DOCX, RTF,
  HTML and TXT, in batches, with Calibre, DjVuLibre, MuPDF and a built-in
  PDF reader.
- Routes through PDF when no single tool converts directly; falls back to the
  next engine when one fails.
- PDF → DjVu in black and white or colour, with a searchable text layer.
- PDF → EPUB and PDF → TXT with no external tools.
- Splash screen at launch and from About biblioteca; TVD mark in the main
  window; application icon.
