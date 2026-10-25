import Foundation
import PDFKit

/// How PDF pages are compressed when making a DjVu.
enum DjVuEncoding: String, CaseIterable, Identifiable, Sendable {
    /// Bitonal JB2 (`cjb2`): small files, right for text and line art.
    case blackAndWhite
    /// Wavelet IW44 (`c44`): keeps colour and greys, much larger files.
    case color

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blackAndWhite: "Black & white (text)"
        case .color: "Color (images)"
        }
    }
}

/// Paths of the DjVuLibre tools; any may be missing.
struct DjVuTools: Sendable {
    let ddjvu: URL?
    let djvutxt: URL?
    let c44: URL?
    let cjb2: URL?
    let djvm: URL?
    let djvused: URL?
}

/// Reads and writes DjVu with DjVuLibre.
///
/// PDF → DjVu renders every page natively, encodes each with `cjb2` or `c44`,
/// bundles them with `djvm`, then copies the PDF's text onto the pages with
/// `djvused` so the DjVu stays searchable.
struct DjVuEngine: ConversionEngine {
    let id = EngineID.djvulibre
    let tools: DjVuTools
    let dpi: Int
    let encoding: DjVuEncoding

    private var pageEncoder: URL? {
        encoding == .blackAndWhite ? tools.cjb2 : tools.c44
    }

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        switch (source, target) {
        case (.djvu, .pdf): tools.ddjvu != nil
        case (.djvu, .txt): tools.djvutxt != nil
        case (.pdf, .djvu): pageEncoder != nil && tools.djvm != nil
        default: false
        }
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        switch (source, target, tools.ddjvu, tools.djvutxt, pageEncoder, tools.djvm) {
        case let (.djvu, .pdf, ddjvu?, _, _, _):
            progress(nil)
            try await ASCIIStaging.run(input: input, output: output) { input, output in
                try await ProcessRunner.run(ddjvu, arguments: ["-format=pdf", "-quality=85", input.path, output.path])
            }
        case let (.djvu, .txt, _, djvutxt?, _, _):
            progress(nil)
            try await ASCIIStaging.run(input: input, output: output) { input, output in
                try await ProcessRunner.run(djvutxt, arguments: [input.path, output.path])
            }
        case let (.pdf, .djvu, _, _, encoder?, djvm?):
            try await ASCIIStaging.run(input: input, output: output) { input, output in
                try await encodePDF(input, to: output, encoder: encoder, djvm: djvm, progress: progress)
            }
        default:
            throw ConversionError.unsupportedRoute(from: source, to: target)
        }
    }

    private func encodePDF(_ input: URL, to output: URL, encoder: URL, djvm: URL,
                           progress: @escaping ProgressHandler) async throws {
        guard let document = PDFDocument(url: input), document.pageCount > 0 else {
            throw ConversionError.unreadableDocument(input.lastPathComponent)
        }
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let steps = Double(document.pageCount + 1)

        var pages: [String] = []
        var textScript = ""
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let encoded = workspace.url.appendingPathComponent(String(format: "p%05d.djvu", index))
            try await encode(page, to: encoded, with: encoder, in: workspace.url)
            pages.append(encoded.path)
            textScript += textLayer(of: page, number: pages.count)
            progress(Double(index + 1) / steps)
        }
        try await ProcessRunner.run(djvm, arguments: ["-c", output.path] + pages)

        if let djvused = tools.djvused, !textScript.isEmpty {
            let script = workspace.url.appendingPathComponent("text.djvused")
            try Data((textScript + "save\n").utf8).write(to: script)
            try await ProcessRunner.run(djvused, arguments: ["-f", script.path, output.path])
        }
        progress(1)
    }

    private func encode(_ page: PDFPage, to encoded: URL, with encoder: URL, in folder: URL) async throws {
        let image = folder.appendingPathComponent("page.\(encoding == .blackAndWhite ? "pbm" : "ppm")")
        defer { try? FileManager.default.removeItem(at: image) }
        switch encoding {
        case .blackAndWhite:
            try PageRasterizer.writePBM(of: page, dpi: dpi, to: image)
            try await ProcessRunner.run(encoder, arguments: ["-dpi", String(dpi), "-lossy", image.path, encoded.path])
        case .color:
            try PageRasterizer.writePPM(of: page, dpi: dpi, to: image)
            try await ProcessRunner.run(encoder, arguments: ["-dpi", String(dpi), image.path, encoded.path])
        }
    }

    private func textLayer(of page: PDFPage, number: Int) -> String {
        let lines = PDFTextExtractor.lines(of: page)
        guard !lines.isEmpty else { return "" }
        return DjVuTextLayer.script(page: number, lines: lines,
                                    mediaBox: page.bounds(for: .mediaBox), dpi: dpi)
    }
}
