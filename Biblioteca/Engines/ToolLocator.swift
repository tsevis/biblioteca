import Foundation

/// An external command-line tool biblioteca can use, and how to install it.
struct ExternalTool: Sendable, Identifiable {
    let id: String
    let engine: EngineID
    let purpose: String
    let installCommand: String
    let url: URL?

    /// Shipped inside biblioteca.app rather than installed on this Mac.
    var isBundled: Bool {
        url?.path.hasPrefix(ToolLocator.bundledBin.path) == true
    }
}

/// Finds the command-line tools biblioteca runs.
///
/// They ship inside the app (Contents/Helpers and Resources/tessdata, filled by Scripts/bundle-tools.py
/// at build time), so biblioteca needs nothing installed. Homebrew's folders
/// are searched after, for builds without the bundled tools such as tests.
struct ToolLocator: Sendable {
    static let bundledHelpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
    static let bundledBin = bundledHelpers.appendingPathComponent("bin", isDirectory: true)

    static let searchDirectories: [String] = [
        bundledBin.path,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    private static let catalogue: [(name: String, engine: EngineID, purpose: String, install: String)] = [
        ("mutool", .mupdf, "EPUB, MOBI, FB2, CBZ, XPS → PDF", "brew install mupdf-tools"),
        ("ddjvu", .djvulibre, "DjVu → PDF", "brew install djvulibre"),
        ("cjb2", .djvulibre, "PDF → DjVu, black & white pages", "brew install djvulibre"),
        ("c44", .djvulibre, "PDF → DjVu, color pages", "brew install djvulibre"),
        ("djvm", .djvulibre, "PDF → DjVu (bundler)", "brew install djvulibre"),
        ("djvused", .djvulibre, "PDF → DjVu text layer (search)", "brew install djvulibre"),
        ("djvutxt", .djvulibre, "DjVu → TXT", "brew install djvulibre"),
        ("tesseract", .tesseract, "OCR for Greek, which Apple Vision cannot read",
         "brew install tesseract tesseract-lang"),
    ]

    let tools: [ExternalTool]

    init(directories: [String] = ToolLocator.searchDirectories,
         fileManager: FileManager = .default) {
        tools = Self.catalogue.map { entry in
            let found = directories
                .map { URL(fileURLWithPath: $0).appendingPathComponent(entry.name) }
                .first { fileManager.isExecutableFile(atPath: $0.path) }
            return ExternalTool(id: entry.name, engine: entry.engine, purpose: entry.purpose,
                                installCommand: entry.install, url: found)
        }
    }

    func url(for name: String) -> URL? {
        tools.first { $0.id == name }?.url
    }

    /// Tesseract's language models shipped with the app, or nil to let
    /// Tesseract use its own installed ones.
    var tessdataDirectory: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/tessdata", isDirectory: true)
        return url(for: "tesseract")?.path.hasPrefix(Self.bundledBin.path) == true ? bundled : nil
    }
}
