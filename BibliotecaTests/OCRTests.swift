import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@Suite("OCR")
struct OCRTests {
    @Test("Tesseract TSV becomes lines in page points, origin bottom-left")
    func parsesTesseractTSV() {
        let tsv = """
        level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0\t0\t1000\t2000\t-1\t
        4\t1\t1\t1\t1\t0\t100\t200\t400\t50\t-1\t
        5\t1\t1\t1\t1\t1\t100\t200\t150\t50\t95.1\tΚαλημέρα
        5\t1\t1\t1\t1\t2\t270\t205\t230\t45\t93.0\tκόσμε
        5\t1\t1\t1\t1\t3\t510\t205\t10\t45\t-1\t
        4\t1\t1\t1\t2\t0\t100\t300\t300\t40\t-1\t
        5\t1\t1\t1\t2\t1\t100\t300\t300\t40\t90\tΔεύτερη
        """
        let lines = TesseractTSV.lines(from: tsv, imageHeight: 2000, scale: 2)
        #expect(lines == [
            TextLine(text: "Καλημέρα κόσμε", frame: CGRect(x: 50, y: 875, width: 200, height: 25)),
            TextLine(text: "Δεύτερη", frame: CGRect(x: 50, y: 830, width: 150, height: 20)),
        ])
    }

    @Test("Recognised text is written invisibly where it was found, and can be read back")
    func searchablePDFKeepsTextAndPlace() throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let scan = try makePDF(in: workspace, text: nil)
        let output = workspace.url.appendingPathComponent("searchable.pdf")
        let frame = CGRect(x: 72, y: 700, width: 300, height: 18)

        try SearchablePDF.write(PDFDocument(url: scan)!, adding: [0: [TextLine(text: "Καλημέρα κόσμε", frame: frame)]],
                                to: output)

        let page = try #require(PDFDocument(url: output)?.page(at: 0))
        #expect(page.string?.contains("Καλημέρα κόσμε") == true)
        let found = try #require(page.selection(for: frame.insetBy(dx: -2, dy: -2))?.string)
        #expect(found.contains("Καλημέρα"))
    }

    @Test("A scanned PDF becomes text through OCR; pages that have text are left alone")
    func scannedPDFToText() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let recognizer = FakeRecognizer(line: "Η Οδύσσεια του Ομήρου")
        // An engine ahead of biblioteca's own that would carry the scans along as images.
        let converter = Converter(engines: [ImageCopyingEngine(), NativeEngine()],
                                  ocr: OCRProcessor(recognizer: recognizer, dpi: 72))

        let scan = try makePDF(in: workspace, text: nil)
        let text = try await converter.convert(scan, to: .txt, in: workspace.url) { _ in }
        #expect(try String(contentsOf: text, encoding: .utf8).contains("Η Οδύσσεια του Ομήρου"))
        #expect(recognizer.calls == 1)

        let typeset = try makePDF(in: workspace, text: "Already searchable text")
        _ = try await converter.convert(typeset, to: .txt, in: workspace.url) { _ in }
        #expect(recognizer.calls == 1)
    }
}

/// Converts PDF to text without reading the text layer, as a converter that keeps page images would.
private struct ImageCopyingEngine: ConversionEngine {
    let id = EngineID.calibre

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        source == .pdf && (target == .txt || target == .epub)
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        try Data("[page image]".utf8).write(to: output)
    }
}

/// Returns one fixed line per page and counts how often it was asked.
private final class FakeRecognizer: TextRecognizer, @unchecked Sendable {
    let name = "fake"
    private let line: String
    private let lock = NSLock()
    private var count = 0

    init(line: String) { self.line = line }

    var calls: Int { lock.withLock { count } }

    func recognize(_ image: CGImage, pageSize: CGSize) async throws -> [TextLine] {
        lock.withLock { count += 1 }
        return [TextLine(text: line, frame: CGRect(x: 72, y: pageSize.height - 100, width: 300, height: 16))]
    }
}

/// A one-page A4 PDF: blank like a scan without a text layer, or carrying `text`.
private func makePDF(in workspace: TemporaryDirectory, text: String?) throws -> URL {
    let url = workspace.url.appendingPathComponent("\(UUID().uuidString).pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 0.95, alpha: 1))
    context.fill(CGRect(x: 60, y: 60, width: 475, height: 722))
    if let text {
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return url
}

@Suite("OCR text layer")
struct OCRTextLayerTests {
    @Test("Lines of recognised text read back as one paragraph, not one per line")
    func recognisedLinesFormParagraphs() throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let scan = try makePDF(in: workspace, text: nil)
        let output = workspace.url.appendingPathComponent("searchable.pdf")
        let lines = ["Η βιβλιοθήκη της πόλης άνοιγε κάθε πρωί", "στις οκτώ και οι αναγνώστες έφταναν",
                     "νωρίς για να βρουν θέση."].enumerated().map { index, text in
            TextLine(text: text, frame: CGRect(x: 72, y: 700 - CGFloat(index) * 16, width: index == 2 ? 150 : 380,
                                               height: 11))
        }
        try SearchablePDF.write(PDFDocument(url: scan)!, adding: [0: lines], to: output)

        let chapters = PDFTextExtractor.chapters(of: try #require(PDFDocument(url: output)))
        #expect(chapters.flatMap(\.paragraphs).count == 1)
    }
}

@Suite("Greek OCR repair")
struct GreekRepairTests {
    @Test("Latin look-alikes and the micro sign become Greek; real Latin words stay", arguments: [
        ("H βιβλιοθήκη µε μαύρο", "Η βιβλιοθήκη με μαύρο"),
        ("ΚΕΦAΛΑΙΟ 1", "ΚΕΦΑΛΑΙΟ 1"),
        ("Tο iPhone και το Linux", "Το iPhone και το Linux"),
    ])
    func repairsGreek(input: String, expected: String) {
        #expect(GreekText.repair(input) == expected)
    }
}

@Suite("Scanned page layout")
struct ScannedPageLayoutTests {
    /// Lines as wide as the 1899 test scan's (237 pt), the last one short.
    private func page(left: CGFloat, head: String?) -> [TextLine] {
        let body = [("Ἡ θάλασσα ἦταν ἥσυχη κι ὁ", 237), ("γέρος κάθονταν στὴν πλώρη", 237),
                    ("σιωπηλός.", 60)].enumerated().map { index, line in
            TextLine(text: line.0, frame: CGRect(x: left, y: 417 - CGFloat(index) * 14,
                                                 width: CGFloat(line.1), height: 9))
        }
        let heading = head.map { [TextLine(text: $0, frame: CGRect(x: left + 100, y: 449, width: 130, height: 5))] }
        return (heading ?? []) + body
    }

    @Test("Left and right pages are measured on their own margins")
    func marginsPerPage() {
        // The scan's left pages start 42 pt further right than its right pages.
        let text = PDFTextExtractor.text(ofPages: [page(left: 26, head: nil), page(left: 68, head: nil)])
        #expect(PDFTextExtractor.paragraphs(in: text).count == 2)
    }

    @Test("Running heads that repeat with page numbers are left out, OCR slips and all")
    func runningHeads() {
        // As read from the 1899 scan: the book's title on left pages, the story's on right ones.
        let heads = ["Θάλασσα 19", "20 Λόγια τῆς πλώρης", "Θάλασσα 21", "22 “όγια τῆς πλώρης", "Θαλασσα 23"]
        let text = PDFTextExtractor.text(ofPages: heads.enumerated().map { page(left: $0 % 2 == 0 ? 26 : 68, head: $1) })
        #expect(heads.allSatisfy { !text.contains($0) })
        #expect(PDFTextExtractor.paragraphs(in: text).count == heads.count)
    }

    @Test("A chapter heading with a number is kept")
    func chapterHeadingKept() {
        // Chapters at least three pages long; two pages apart, headings look like running heads.
        let pages = [page(left: 26, head: "Κεφάλαιο 1"), page(left: 68, head: nil), page(left: 26, head: nil),
                     page(left: 68, head: "Κεφάλαιο 2")]
        let text = PDFTextExtractor.text(ofPages: pages)
        #expect(text.contains("Κεφάλαιο 1") && text.contains("Κεφάλαιο 2"))
    }
}
