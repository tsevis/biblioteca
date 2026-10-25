import AppKit
import Foundation
import PDFKit
import Testing

@Suite("Metadata")
struct MetadataWriterTests {
    @Test("A PDF gets the new title and author, and the cover as its first page")
    func writesPDFMetadataAndCover() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let pdf = workspace.url.appendingPathComponent("book.pdf")
        let blank = PDFDocument()
        blank.insert(PDFPage(), at: 0)
        #expect(blank.write(to: pdf))
        let cover = workspace.url.appendingPathComponent("cover.png")
        try Self.redSquarePNG().write(to: cover)

        let metadata = BookMetadata(title: "Οδύσσεια", author: "Όμηρος", cover: cover)
        try await MetadataWriter().apply(metadata, to: pdf, format: .pdf)

        let result = try #require(PDFDocument(url: pdf))
        #expect(result.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Οδύσσεια")
        #expect(result.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == "Όμηρος")
        #expect(result.pageCount == 2)
        #expect(result.page(at: 0)?.bounds(for: .mediaBox) == result.page(at: 1)?.bounds(for: .mediaBox))
    }

    @Test("Quotes and backslashes in a DjVu title cannot break the djvused script")
    func escapesDjVuStrings() {
        let script = MetadataWriter.djvusedScript(for: BookMetadata(title: #"Say "hi" \ bye"#, author: "A\nB"))
        #expect(script == """
        select
        set-meta
        title "Say \\"hi\\" \\\\ bye"
        author "A B"
        .
        save

        """)
    }

    @Test("An EPUB gets the new title, authors and cover without Calibre, and reads them back")
    func writesEPUBMetadataNatively() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let epub = workspace.url.appendingPathComponent("book.epub")
        try await EPUBWriter.write(title: "Χωρίς τίτλο", author: nil, language: "el",
                                   chapters: [EPUBChapter(title: "Α", paragraphs: ["Κείμενο."])], to: epub)
        let cover = workspace.url.appendingPathComponent("cover.png")
        try Self.redSquarePNG().write(to: cover)

        let metadata = BookMetadata(title: "Λόγια της Πλώρης", author: "Ανδρέας Καρκαβίτσας & Κανείς", cover: cover)
        let writer = MetadataWriter()
        try await writer.apply(metadata, to: epub, format: .epub)

        #expect(await writer.read(epub, format: .epub)
            == BookMetadata(title: "Λόγια της Πλώρης", author: "Ανδρέας Καρκαβίτσας & Κανείς"))
        let files = try await ProcessRunner.lines(of: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", epub.path])
        #expect(files.first == "mimetype")
        #expect(files.contains { $0.hasSuffix("cover.png") })
    }

    private static func redSquarePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 60, height: 90), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
