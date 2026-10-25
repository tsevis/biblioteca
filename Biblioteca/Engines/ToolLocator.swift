import Foundation

/// An external command-line tool biblioteca can use, and how to install it.
struct ExternalTool: Sendable, Identifiable {
    let id: String
    let engine: EngineID
    let purpose: String
    let installCommand: String
    let url: URL?
}

/// Finds the external converters installed on this Mac.
///
/// GUI apps do not inherit the shell's PATH, so the usual Homebrew and
/// application-bundle locations are searched explicitly.
struct ToolLocator: Sendable {
    static let searchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/Applications/calibre.app/Contents/MacOS",
        NSHomeDirectory() + "/Applications/calibre.app/Contents/MacOS",
        "/usr/bin",
    ]

    private static let catalogue: [(name: String, engine: EngineID, purpose: String, install: String)] = [
        ("ebook-convert", .calibre, "EPUB, MOBI, AZW3, FB2, DOCX ↔ PDF", "brew install --cask calibre"),
        ("mutool", .mupdf, "EPUB, MOBI, FB2, CBZ, XPS → PDF", "brew install mupdf-tools"),
        ("ddjvu", .djvulibre, "DjVu → PDF", "brew install djvulibre"),
        ("cjb2", .djvulibre, "PDF → DjVu, black & white pages", "brew install djvulibre"),
        ("c44", .djvulibre, "PDF → DjVu, color pages", "brew install djvulibre"),
        ("djvm", .djvulibre, "PDF → DjVu (bundler)", "brew install djvulibre"),
        ("djvused", .djvulibre, "PDF → DjVu text layer (search)", "brew install djvulibre"),
        ("djvutxt", .djvulibre, "DjVu → TXT", "brew install djvulibre"),
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
}
