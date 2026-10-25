import Foundation
import PDFKit
import Testing

@Suite("PDF line ranges")
struct PDFLineRangeTests {
    /// Page 18 of arXiv 2608.03575v1. PDFKit gives two of its lines a text
    /// range of negative length, and asking for their string kills the app.
    private static let badRanges = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/bad-line-ranges.pdf")

    @Test("A page whose lines PDFKit cannot read whole is read without crashing")
    func readsPageWithBadLineRanges() throws {
        let page = try #require(PDFDocument(url: Self.badRanges)?.page(at: 0))
        let lines = PDFTextExtractor.lines(of: page)
        #expect(lines.count > 40)
        #expect(lines.contains { $0.text.hasPrefix("Schramm limit of the rooted marked dual") })
    }
}
