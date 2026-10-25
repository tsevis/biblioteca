import CoreGraphics
import Foundation
import ImageIO

/// Adds a recognised text layer to a scanned DjVu, keeping its pages as they are.
///
/// Each page is rendered at its own full resolution with `ddjvu`, so the
/// recognised boxes are already in DjVu's pixel space, origin bottom-left;
/// `djvused` then writes them onto the pages.
struct DjVuRecognition: Sendable {
    let ddjvu: URL
    let djvused: URL
    let djvutxt: URL

    init?(tools: DjVuTools) {
        guard let ddjvu = tools.ddjvu, let djvused = tools.djvused, let djvutxt = tools.djvutxt else { return nil }
        (self.ddjvu, self.djvused, self.djvutxt) = (ddjvu, djvused, djvutxt)
    }

    /// Writes a searchable copy of `input` to `output`. Throws
    /// `alreadySearchable` when the DjVu already has text.
    func addText(_ input: URL, to output: URL, recognizer: any TextRecognizer,
                 progress: @escaping ProgressHandler) async throws {
        try await ASCIIStaging.run(input: input, output: output) { input, output in
            let workspace = try TemporaryDirectory()
            defer { workspace.remove() }
            guard try await !hasText(input, in: workspace.url) else { throw ConversionError.alreadySearchable }

            let sizes = try await pageSizes(of: input)
            var script = ""
            for (index, size) in sizes.enumerated() {
                try Task.checkCancellation()
                progress(Double(index) / Double(max(sizes.count, 1)))
                let image = try await render(page: index + 1, of: input, size: size, in: workspace.url)
                let lines = try await recognizer.recognize(image, pageSize: size)
                guard !lines.isEmpty else { continue }
                // At 72 dpi the script's points-to-pixels scale is one: the boxes are pixels already.
                script += DjVuTextLayer.script(page: index + 1, lines: lines,
                                               mediaBox: CGRect(origin: .zero, size: size), dpi: 72)
            }
            guard !script.isEmpty else { throw ConversionError.noTextLayer }

            let scriptURL = workspace.url.appendingPathComponent("text.djvused")
            try Data((script + "save\n").utf8).write(to: scriptURL)
            try FileManager.default.copyItem(at: input, to: output)
            try await ProcessRunner.run(djvused, arguments: ["-f", scriptURL.path, output.path])
            progress(1)
        }
    }

    private func hasText(_ input: URL, in folder: URL) async throws -> Bool {
        let text = folder.appendingPathComponent("existing.txt")
        try await ProcessRunner.run(djvutxt, arguments: [input.path, text.path])
        let content = (try? String(contentsOf: text, encoding: .utf8)) ?? ""
        return content.trimmingCharacters(in: .whitespacesAndNewlines).count >= OCRProcessor.minimumTextLength
    }

    /// Page sizes in pixels, from `djvused`'s "width=2479 height=3508" lines.
    private func pageSizes(of input: URL) async throws -> [CGSize] {
        let count = try await ProcessRunner.lines(of: djvused, arguments: ["-e", "n", input.path])
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.first ?? 0
        guard count > 0 else { throw ConversionError.unreadableDocument(input.lastPathComponent) }
        let commands = (1...count).map { "select \($0); size" }.joined(separator: "; ")
        let sizes = try await ProcessRunner.lines(of: djvused, arguments: ["-e", commands, input.path])
            .compactMap(Self.size(from:))
        guard sizes.count == count else { throw ConversionError.unreadableDocument(input.lastPathComponent) }
        return sizes
    }

    static func size(from line: String) -> CGSize? {
        let values = Dictionary(line.split(separator: " ").compactMap { pair -> (String, Int)? in
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { return nil }
            return (String(parts[0]), value)
        }, uniquingKeysWith: { first, _ in first })
        guard let width = values["width"], let height = values["height"] else { return nil }
        return CGSize(width: width, height: height)
    }

    private func render(page: Int, of input: URL, size: CGSize, in folder: URL) async throws -> CGImage {
        let tiff = folder.appendingPathComponent("page.tif")
        defer { try? FileManager.default.removeItem(at: tiff) }
        try await ProcessRunner.run(ddjvu, arguments: ["-format=tiff", "-page=\(page)",
                                                       "-size=\(Int(size.width))x\(Int(size.height))",
                                                       input.path, tiff.path])
        guard let source = CGImageSourceCreateWithURL(tiff as CFURL, nil),
              // Decoded now: images load lazily, and the file is deleted on return.
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw ConversionError.unreadableDocument("page \(page)") }
        return image
    }
}
