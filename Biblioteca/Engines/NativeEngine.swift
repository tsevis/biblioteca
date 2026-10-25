import Foundation
import NaturalLanguage
import PDFKit

/// Conversions biblioteca performs itself, without external tools: PDF to
/// text and EPUB with PDFKit, Word and RTF to PDF with the macOS text system.
struct NativeEngine: ConversionEngine {
    let id = EngineID.native
    var layout: PageLayout = .a4

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        switch (source, target) {
        case (.pdf, .txt), (.pdf, .epub): true
        case (_, .pdf): DocumentRenderer.documentType(of: source) != nil
        default: false
        }
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        if target == .pdf, let type = DocumentRenderer.documentType(of: source) {
            progress(nil)
            try DocumentRenderer.renderPDF(of: input, type: type, layout: layout, to: output)
            progress(1)
            return
        }
        guard let document = PDFDocument(url: input) else {
            throw ConversionError.unreadableDocument(input.lastPathComponent)
        }
        progress(nil)
        let chapters = PDFTextExtractor.chapters(of: document)
        guard !chapters.isEmpty else { throw ConversionError.noTextLayer }

        switch target {
        case .txt:
            let text = chapters
                .map { $0.paragraphs.joined(separator: "\n\n") }
                .joined(separator: "\n\n\n")
            try Data(text.utf8).write(to: output)
        case .epub:
            let attributes = document.documentAttributes ?? [:]
            let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? input.deletingPathExtension().lastPathComponent
            try await EPUBWriter.write(
                title: title,
                author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
                language: Self.language(of: chapters),
                chapters: chapters,
                to: output
            )
        default:
            throw ConversionError.unsupportedRoute(from: source, to: target)
        }
        progress(1)
    }

    /// Guesses the book's language from its first few paragraphs.
    private static func language(of chapters: [EPUBChapter]) -> String {
        let sample = chapters.flatMap(\.paragraphs).prefix(20).joined(separator: " ")
        return NLLanguageRecognizer.dominantLanguage(for: sample)?.rawValue ?? "und"
    }
}
