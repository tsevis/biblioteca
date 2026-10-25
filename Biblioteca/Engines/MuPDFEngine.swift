import Foundation

/// Lays out reflowable books (EPUB, MOBI, FB2…) as PDF pages with MuPDF's `mutool`.
struct MuPDFEngine: ConversionEngine {
    let id = EngineID.mupdf
    let mutool: URL
    let layout: PageLayout

    private static let inputs: Set<BookFormat> = [.epub, .mobi, .fb2, .cbz, .xps, .html, .txt]

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        switch target {
        case .pdf: Self.inputs.contains(source)
        case .txt: Self.inputs.contains(source) || source == .pdf
        default: false
        }
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        let format = target == .txt ? "text" : "pdf"
        let arguments = [
            "convert",
            "-W", String(layout.widthPoints),
            "-H", String(layout.heightPoints),
            "-S", String(layout.fontSize),
            "-F", format,
            "-o", output.path,
            input.path,
        ]
        progress(nil)
        try await ProcessRunner.run(mutool, arguments: arguments)
    }
}

/// Page geometry for formats that have no fixed pages of their own.
struct PageLayout: Sendable, Equatable {
    let widthPoints: Int
    let heightPoints: Int
    let fontSize: Int

    static let a4 = PageLayout(widthPoints: 595, heightPoints: 842, fontSize: 11)
    static let a5 = PageLayout(widthPoints: 420, heightPoints: 595, fontSize: 10)
    static let letter = PageLayout(widthPoints: 612, heightPoints: 792, fontSize: 11)
}
