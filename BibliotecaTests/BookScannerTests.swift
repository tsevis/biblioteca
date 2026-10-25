import Foundation
import Testing

@Suite("BookScanner")
struct BookScannerTests {
    @Test("Folders are searched to any depth; hidden and unknown files are skipped")
    func scansFolderTrees() throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let library = workspace.url.appendingPathComponent("Βιβλιοθήκη", isDirectory: true)
        for path in ["a.epub", "Ποίηση/Σεφέρης/b.MOBI", ".cache/c.pdf", "d.jpg", ".e.pdf", "Ποίηση/f.djvu"] {
            let url = library.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let loose = workspace.url.appendingPathComponent("loose.fb2")
        try Data("x".utf8).write(to: loose)

        let found = BookScanner.books(in: [library, loose])

        #expect(found.map { "\($0.relativeFolder)|\($0.url.lastPathComponent)" } == [
            "Βιβλιοθήκη|a.epub",
            "Βιβλιοθήκη/Ποίηση|f.djvu",
            "Βιβλιοθήκη/Ποίηση/Σεφέρης|b.MOBI",
            "|loose.fb2",
        ])
    }

    @Test("Converting into a folder that does not exist yet creates it")
    func createsMissingOutputFolders() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let input = workspace.url.appendingPathComponent("book.epub")
        try Data("x".utf8).write(to: input)
        let nested = workspace.url.appendingPathComponent("out/Βιβλιοθήκη/Ποίηση", isDirectory: true)

        let converter = Converter(engines: [CopyEngine()])
        let result = try await converter.convert(input, to: .pdf, in: nested) { _ in }

        #expect(result.path == nested.appendingPathComponent("book.pdf").path)
    }
}

private struct CopyEngine: ConversionEngine {
    let id = EngineID.mupdf
    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool { true }
    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        try FileManager.default.copyItem(at: input, to: output)
    }
}
