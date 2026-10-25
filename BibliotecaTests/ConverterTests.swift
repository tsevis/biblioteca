import Foundation
import Testing

@Suite("Converter")
struct ConverterTests {
    @Test("Never picks the name of a file that already exists")
    func availableURLSkipsExistingFiles() throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        for name in ["Book.pdf", "Book 2.pdf"] {
            try Data("x".utf8).write(to: workspace.url.appendingPathComponent(name))
        }

        let url = Converter.availableURL(in: workspace.url, baseName: "Book", fileExtension: "pdf")

        #expect(url.lastPathComponent == "Book 3.pdf")
    }

    @Test("A failing engine leaves nothing in the output folder")
    func failedConversionLeavesNoPartialFile() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let input = workspace.url.appendingPathComponent("in.epub")
        try Data("x".utf8).write(to: input)
        let output = workspace.url.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let converter = Converter(engines: [HalfWritingEngine()])
        await #expect(throws: ConversionError.self) {
            _ = try await converter.convert(input, to: .pdf, in: output) { _ in }
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
}

@Suite("Converter fallback")
struct ConverterFallbackTests {
    @Test("When the preferred engine fails, the next engine for the same step is tried")
    func fallsBackToNextEngine() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let input = workspace.url.appendingPathComponent("book.mobi")
        try Data("x".utf8).write(to: input)

        let converter = Converter(engines: [HalfWritingEngine(), WritingEngine()])
        let result = try await converter.convert(input, to: .pdf, in: workspace.url) { _ in }

        #expect(try String(contentsOf: result, encoding: .utf8) == "complete")
    }
}

private struct WritingEngine: ConversionEngine {
    let id = EngineID.mupdf
    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool { true }
    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        try Data("complete".utf8).write(to: output)
    }
}

/// Writes part of its output, then fails, like a tool that crashes mid-book.
private struct HalfWritingEngine: ConversionEngine {
    let id = EngineID.mupdf
    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool { true }
    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        try Data("partial".utf8).write(to: output)
        throw ConversionError.toolFailed(tool: "fake", status: 1, detail: "")
    }
}

@Suite("PDFTextExtractor")
struct PDFTextExtractorTests {
    @Test("Rejoins words hyphenated across lines, Greek included")
    func rejoinsHyphenatedWords() {
        let text = "Η μετα-\nτροπή του βιβλίου\nείναι έτοιμη.\n\nA conver-\nsion test."
        #expect(PDFTextExtractor.paragraphs(in: text) == [
            "Η μετατροπή του βιβλίου είναι έτοιμη.",
            "A conversion test.",
        ])
    }

    @Test("Starts a paragraph after a short line and after a wide vertical gap")
    func breaksParagraphsFromLineGeometry() {
        // PDF coordinates: y grows upwards, so later lines have smaller y.
        func line(_ text: String, y: CGFloat, width: CGFloat) -> TextLine {
            TextLine(text: text, frame: CGRect(x: 72, y: y, width: width, height: 12))
        }
        let lines = [
            line("Κεφάλαιο 1", y: 700, width: 80),
            line("First line of a full", y: 670, width: 450),
            line("paragraph that ends here.", y: 656, width: 200),
            line("Second paragraph runs", y: 642, width: 450),
            line("to the margin.", y: 628, width: 450),
            line("Third after a gap.", y: 590, width: 450),
        ]
        #expect(PDFTextExtractor.text(of: lines) == """
        Κεφάλαιο 1

        First line of a full
        paragraph that ends here.

        Second paragraph runs
        to the margin.

        Third after a gap.
        """)
    }
}
