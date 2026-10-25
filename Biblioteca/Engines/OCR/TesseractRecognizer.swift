import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Tesseract, for the languages Apple Vision does not read, Greek among them.
struct TesseractRecognizer: TextRecognizer {
    let name = "Tesseract"
    let tesseract: URL
    /// Tesseract language codes joined by "+", for example "ell+eng".
    let languages: String

    func recognize(_ image: CGImage, pageSize: CGSize) async throws -> [TextLine] {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let png = workspace.url.appendingPathComponent("page.png")
        try Self.writePNG(image, to: png)
        let base = workspace.url.appendingPathComponent("page")
        let dpi = Int((CGFloat(image.width) / pageSize.width * 72).rounded())
        try await ProcessRunner.run(tesseract, arguments: [png.path, base.path, "-l", languages,
                                                           "--dpi", String(dpi), "tsv"]) { _ in }
        let tsv = try String(contentsOf: base.appendingPathExtension("tsv"), encoding: .utf8)
        let lines = TesseractTSV.lines(from: tsv, imageHeight: image.height,
                                       scale: CGFloat(image.height) / pageSize.height)
        return readsGreek ? lines.map { TextLine(text: GreekText.repair($0.text), frame: $0.frame) } : lines
    }

    private var readsGreek: Bool {
        languages.split(separator: "+").contains { $0 == "ell" || $0 == "grc" }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ConversionError.outputMissing(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.outputMissing(url.lastPathComponent)
        }
    }
}
