import AppKit
import Foundation
import PDFKit

enum MetadataError: LocalizedError, Equatable {
    case unreadableCover(String)
    case unreadablePDF(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableCover(name): "Could not read the cover image \(name)."
        case let .unreadablePDF(name): "Could not open \(name) to write its title and author."
        case let .saveFailed(name): "Could not save the title, author or cover into \(name)."
        }
    }
}

/// Reads and writes a book's title, author and cover.
///
/// PDF is handled with PDFKit and EPUB by editing its package document, both
/// natively; DjVu goes through `djvused`.
struct MetadataWriter: Sendable {
    var djvused: URL?

    /// The fields that can be written into a book of `format` on this Mac.
    func supportedFields(for format: BookFormat) -> Set<BookMetadata.Field> {
        switch format {
        case .pdf, .epub:
            return Set(BookMetadata.Field.allCases)
        case .djvu:
            return djvused == nil ? [] : [.title, .author]
        default:
            return []
        }
    }

    /// Writes the fields `format` supports; the others are left out, and the
    /// interface says so before the conversion starts.
    func apply(_ metadata: BookMetadata, to file: URL, format: BookFormat) async throws {
        let supported = supportedFields(for: format)
        let wanted = BookMetadata(title: supported.contains(.title) ? metadata.title : "",
                                  author: supported.contains(.author) ? metadata.author : "",
                                  cover: supported.contains(.cover) ? metadata.cover : nil)
        guard !wanted.isEmpty else { return }
        switch format {
        case .pdf:
            try Self.applyToPDF(wanted, file: file)
        case .djvu:
            guard let djvused else { return }
            try await ProcessRunner.run(djvused, arguments: [file.path, "-e", Self.djvusedScript(for: wanted)])
        case .epub:
            try await EPUBMetadata.write(wanted, to: file)
        default:
            return
        }
    }

    /// What the book already says about itself, to start the editor from.
    func read(_ file: URL, format: BookFormat) async -> BookMetadata {
        switch format {
        case .pdf:
            let attributes = PDFDocument(url: file)?.documentAttributes
            return BookMetadata(title: attributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "",
                                author: attributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "")
        case .epub:
            return (try? await EPUBMetadata.read(file)) ?? .empty
        default:
            return .empty
        }
    }

    // MARK: PDF

    private static func applyToPDF(_ metadata: BookMetadata, file: URL) throws {
        guard let document = PDFDocument(url: file) else {
            throw MetadataError.unreadablePDF(file.lastPathComponent)
        }
        var attributes = document.documentAttributes ?? [:]
        if !metadata.title.isEmpty { attributes[PDFDocumentAttribute.titleAttribute] = metadata.title }
        if !metadata.author.isEmpty { attributes[PDFDocumentAttribute.authorAttribute] = metadata.author }
        document.documentAttributes = attributes

        if let cover = metadata.cover {
            document.insert(try coverPage(cover, matching: document.page(at: 0)), at: 0)
        }

        // PDFKit reads pages lazily from the file, so it must not overwrite it in place.
        let staged = file.deletingLastPathComponent()
            .appendingPathComponent(".metadata-\(UUID().uuidString).pdf")
        guard document.write(to: staged) else {
            try? FileManager.default.removeItem(at: staged)
            throw MetadataError.saveFailed(file.lastPathComponent)
        }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: staged)
    }

    /// The cover image as a page the size of the book's own pages.
    private static func coverPage(_ url: URL, matching page: PDFPage?) throws -> PDFPage {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw MetadataError.unreadableCover(url.lastPathComponent)
        }
        let options: [PDFPage.ImageInitializationOption: Any] = page.map {
            [.mediaBox: $0.bounds(for: .mediaBox), .upscaleIfSmaller: true]
        } ?? [:]
        guard let cover = PDFPage(image: image, options: options) else {
            throw MetadataError.unreadableCover(url.lastPathComponent)
        }
        return cover
    }

    // MARK: Command lines

    /// A djvused script that replaces the document's title and author.
    static func djvusedScript(for metadata: BookMetadata) -> String {
        var lines = ["select", "set-meta"]
        if !metadata.title.isEmpty { lines.append("title \(djvuString(metadata.title))") }
        if !metadata.author.isEmpty { lines.append("author \(djvuString(metadata.author))") }
        lines += [".", "save", ""]
        return lines.joined(separator: "\n")
    }

    private static func djvuString(_ value: String) -> String {
        let oneLine = value.components(separatedBy: .newlines).joined(separator: " ")
        let escaped = oneLine.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
