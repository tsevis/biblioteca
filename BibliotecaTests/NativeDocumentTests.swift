import AppKit
import Foundation
import PDFKit
import Testing

@Suite("Word and RTF documents")
struct NativeDocumentTests {
    @Test("DOCX and RTF become paged PDF with their Greek text, without Calibre",
          arguments: [BookFormat.docx, .rtf])
    func documentToPDF(format: BookFormat) async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let paragraph = "Ἡ θάλασσα ἦταν ἥσυχη κι ὁ γέρος κάθονταν στὴν πλώρη σιωπηλός. "
        let text = NSAttributedString(string: String(repeating: paragraph, count: 400),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let type: NSAttributedString.DocumentType = format == .docx ? .officeOpenXML : .rtf
        let source = workspace.url.appendingPathComponent("book.\(format.fileExtension)")
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
            .write(to: source)
        let output = workspace.url.appendingPathComponent("book.pdf")

        try await NativeEngine().convert(source, to: output, from: format, target: .pdf) { _ in }

        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount > 1)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
        #expect(pdf.string?.contains("θάλασσα ἦταν ἥσυχη") == true)
    }
}
