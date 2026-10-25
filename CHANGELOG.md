# Changelog

## 0.3.1 — 2026-10-25

- Fixed a crash when a PDF became EPUB, TXT or DjVu: on some pages PDFKit
  hands out a line whose text has a negative length (page 18 of arXiv
  2608.03575v1), and reading it killed the app. Each line's text is now cut
  from the page's text, and a broken range is skipped.

## 0.3.0 — 2026-10-25

- biblioteca stands alone: MuPDF, DjVuLibre and Tesseract with its English,
  Greek and polytonic Greek models are built into the app, which no longer
  looks for anything installed on the Mac.
- Calibre is gone, and with it AZW3. Output formats are PDF, EPUB, DjVu and
  TXT; MOBI and FB2 are still read.
- EPUB title, author and cover are written natively. DOCX and RTF become PDF
  natively, laid out on the chosen page size.

## 0.2.0 — 2026-10-25

- A progress bar for the whole run sits beside "N of M" while converting,
  and each book's bar shows its percentage.
- OCR text from a real scanned book (Karkavitsas, 1899) keeps its
  paragraphs: each page is measured on its own margins, since left and right
  pages of a scan sit at different offsets, and running heads such as
  "Θάλασσα 19" are left out. Against Project Gutenberg's transcription of
  ten pages, the polytonic setting matched 96.1% of the letters, accents
  aside.
- Batch: a search field above the list narrows a long library by book name
  and folder, ignoring case and accents. While a search is active, Convert
  takes only the books it shows.
- Title, author and cover can be set for each book before converting (the
  tag button on a row, or its context menu). PDF is written natively, the
  cover becoming the first page; EPUB, MOBI, AZW3 and FB2 need Calibre's
  `ebook-meta`, DjVu titles need DjVuLibre. A row warns when the target
  format cannot hold a field.
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
