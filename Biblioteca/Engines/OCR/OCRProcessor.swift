import CoreGraphics
import Foundation
import PDFKit

/// Runs a recogniser over the pages of a book that have no text.
struct OCRProcessor: Sendable {
    /// Pages with fewer characters than this are treated as scans: a page
    /// number or a running head alone is not a text layer.
    static let minimumTextLength = 10

    /// Resolution pages are rendered at for recognition.
    static let defaultDPI = 300

    let recognizer: any TextRecognizer
    let dpi: Int

    /// Apple Vision where it reads the language, otherwise Tesseract; nil
    /// when the language needs Tesseract and it is not installed.
    static func make(language: OCRLanguage, tesseract: URL?, tessdata: URL? = nil) -> OCRProcessor? {
        if let code = language.visionCode {
            return OCRProcessor(recognizer: VisionRecognizer(languages: [code]), dpi: defaultDPI)
        }
        return tesseract.map {
            OCRProcessor(recognizer: TesseractRecognizer(tesseract: $0, languages: language.tesseractCode,
                                                       tessdata: tessdata),
                         dpi: defaultDPI)
        }
    }

    /// Writes a searchable copy of `input` to `output`. Returns false, and
    /// writes nothing, when every page already has text.
    func makeSearchable(_ input: URL, to output: URL, progress: @escaping ProgressHandler) async throws -> Bool {
        guard let document = PDFDocument(url: input) else {
            throw ConversionError.unreadableDocument(input.lastPathComponent)
        }
        let pageCount = max(document.pageCount, 1)
        var recognized: [Int: [TextLine]] = [:]
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            progress(Double(index) / Double(pageCount))
            guard let page = document.page(at: index), Self.needsRecognition(page) else { continue }
            let image = try PageRasterizer.image(of: page, dpi: dpi)
            recognized[index] = try await recognizer.recognize(image, pageSize: SearchablePDF.displaySize(of: page))
        }
        guard !recognized.isEmpty else { return false }
        try SearchablePDF.write(document, adding: recognized, to: output)
        progress(1)
        return true
    }

    static func needsRecognition(_ page: PDFPage) -> Bool {
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.count < minimumTextLength
    }
}
