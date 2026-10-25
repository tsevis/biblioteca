import Foundation

/// Reports fractional progress (0...1), or nil when the engine cannot tell.
typealias ProgressHandler = @Sendable (Double?) -> Void

enum EngineID: String, Sendable, CaseIterable {
    case calibre, djvulibre, mupdf, native, tesseract

    var displayName: String {
        switch self {
        case .calibre: "Calibre"
        case .djvulibre: "DjVuLibre"
        case .mupdf: "MuPDF"
        case .native: "biblioteca"
        case .tesseract: "Tesseract"
        }
    }
}

/// One tool that turns a file of one format into another.
protocol ConversionEngine: Sendable {
    var id: EngineID { get }
    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool
    func convert(
        _ input: URL,
        to output: URL,
        from source: BookFormat,
        target: BookFormat,
        progress: @escaping ProgressHandler
    ) async throws
}

enum ConversionError: LocalizedError, Equatable {
    case unsupportedRoute(from: BookFormat, to: BookFormat)
    case unreadableDocument(String)
    case noTextLayer
    case toolFailed(tool: String, status: Int32, detail: String)
    case toolCrashed(tool: String, signal: Int32, detail: String)
    case outputMissing(String)
    case alreadySearchable

    var errorDescription: String? {
        switch self {
        case let .unsupportedRoute(from, to):
            "No installed engine can convert \(from.displayName) to \(to.displayName)."
        case let .unreadableDocument(name):
            "Could not open \(name)."
        case .noTextLayer:
            "This book has no text layer (it is probably scanned). Turn on OCR scans and convert it again."
        case let .toolFailed(tool, status, detail):
            "\(tool) failed (exit \(status)). \(detail)"
        case let .toolCrashed(tool, signal, detail):
            "\(tool) crashed (signal \(signal)). Try again. \(detail)"
        case let .outputMissing(name):
            "The converter finished but did not produce \(name)."
        case .alreadySearchable:
            "Every page already has text, so there was nothing to recognise."
        }
    }
}
