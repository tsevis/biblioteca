import AppKit
import Foundation

/// Lays out Word and RTF documents as PDF pages with the text system macOS
/// itself uses, so no converter needs to be installed for them.
enum DocumentRenderer {
    /// Page margin on every side, in points (2 cm).
    private static let margin: CGFloat = 56.7

    static func documentType(of format: BookFormat) -> NSAttributedString.DocumentType? {
        switch format {
        case .docx: .officeOpenXML
        case .rtf: .rtf
        default: nil
        }
    }

    static func renderPDF(of input: URL, type: NSAttributedString.DocumentType, layout: PageLayout,
                          to output: URL) throws {
        let text = try NSAttributedString(url: input, options: [.documentType: type], documentAttributes: nil)
        guard text.length > 0 else { throw ConversionError.unreadableDocument(input.lastPathComponent) }

        let page = CGSize(width: layout.widthPoints, height: layout.heightPoints)
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let ranges = paginate(manager, frame: CGSize(width: page.width - 2 * margin, height: page.height - 2 * margin))

        var box = CGRect(origin: .zero, size: page)
        guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else {
            throw ConversionError.outputMissing(output.lastPathComponent)
        }
        for range in ranges {
            context.beginPDFPage(nil)
            draw(range, of: manager, in: context, pageHeight: page.height)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// Adds page-sized text containers until all the text is laid out, and
    /// returns the glyphs on each page.
    private static func paginate(_ manager: NSLayoutManager, frame: CGSize) -> [NSRange] {
        var ranges: [NSRange] = []
        while ranges.last.map(NSMaxRange) ?? 0 < manager.numberOfGlyphs {
            let container = NSTextContainer(size: frame)
            manager.addTextContainer(container)
            let range = manager.glyphRange(for: container)
            // Something taller than a page cannot be placed; stop rather than add empty pages for ever.
            guard range.length > 0 else { break }
            ranges.append(range)
        }
        return ranges
    }

    /// AppKit draws top-down, so the PDF page is flipped for it.
    private static func draw(_ range: NSRange, of manager: NSLayoutManager, in context: CGContext,
                             pageHeight: CGFloat) {
        context.saveGState()
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let origin = CGPoint(x: margin, y: margin)
        manager.drawBackground(forGlyphRange: range, at: origin)
        manager.drawGlyphs(forGlyphRange: range, at: origin)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}
