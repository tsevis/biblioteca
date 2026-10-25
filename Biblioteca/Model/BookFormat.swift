import Foundation

/// A book or document format that biblioteca can read or write.
enum BookFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, epub, mobi, djvu, fb2, cbz, xps, txt, docx, rtf, html

    var id: String { rawValue }

    /// File extensions that map onto each format. The first one is used for output.
    private static let extensionTable: [BookFormat: [String]] = [
        .pdf: ["pdf"],
        .epub: ["epub"],
        .mobi: ["mobi", "prc", "azw"],
        .djvu: ["djvu", "djv"],
        .fb2: ["fb2"],
        .cbz: ["cbz"],
        .xps: ["xps", "oxps"],
        .txt: ["txt"],
        .docx: ["docx"],
        .rtf: ["rtf"],
        .html: ["html", "htm", "xhtml"],
    ]

    /// Formats offered as conversion targets in the interface.
    static let outputFormats: [BookFormat] = [.pdf, .epub, .djvu, .txt]

    init?(fileExtension: String) {
        let ext = fileExtension.lowercased()
        guard let match = Self.extensionTable.first(where: { $0.value.contains(ext) }) else {
            return nil
        }
        self = match.key
    }

    init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    var fileExtension: String {
        Self.extensionTable[self]?.first ?? rawValue
    }

    var displayName: String {
        switch self {
        case .djvu: "DjVu"
        default: rawValue.uppercased()
        }
    }
}
