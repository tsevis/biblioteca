import Foundation

/// Converts between e-book formats with Calibre's `ebook-convert`.
struct CalibreEngine: ConversionEngine {
    let id = EngineID.calibre
    let ebookConvert: URL
    let layout: PageLayout

    private static let inputs: Set<BookFormat> = [
        .epub, .mobi, .azw3, .fb2, .docx, .rtf, .txt, .html, .pdf, .cbz,
    ]
    private static let outputs: Set<BookFormat> = [
        .epub, .mobi, .azw3, .fb2, .docx, .rtf, .txt, .pdf,
    ]

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        Self.inputs.contains(source) && Self.outputs.contains(target)
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        progress(nil)
        try await ProcessRunner.run(
            ebookConvert,
            arguments: [input.path, output.path] + pdfArguments(for: target)
        ) { line in
            // ebook-convert prints lines such as "34% Converting input to HTML...".
            if let percent = Self.percent(in: line) { progress(percent) }
        }
    }

    private func pdfArguments(for target: BookFormat) -> [String] {
        guard target == .pdf else { return [] }
        return [
            "--custom-size", "\(layout.widthPoints)x\(layout.heightPoints)",
            "--unit", "point",
            "--pdf-page-numbers",
        ]
    }

    private static func percent(in line: String) -> Double? {
        guard let token = line.split(separator: "%", maxSplits: 1).first,
              let value = Double(token.trimmingCharacters(in: .whitespaces)),
              (0...100).contains(value)
        else { return nil }
        return value / 100
    }
}
