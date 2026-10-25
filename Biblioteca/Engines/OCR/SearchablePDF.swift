import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Rewrites a PDF with recognised text laid invisibly over its pages, so the
/// scan still looks the same but can be searched, selected and extracted.
enum SearchablePDF {
    /// Glyph size as a share of the recognised line's height, leaving room for
    /// ascenders and descenders inside the box.
    private static let fontShare: CGFloat = 0.8
    /// Baseline height as a share of the line's height, above the descenders.
    private static let baselineShare: CGFloat = 0.2
    private static let fontName = "Helvetica"
    private static let creator = "biblioteca"

    /// `lines` maps page indexes to text in that page's displayed space,
    /// origin bottom-left. Pages without lines are copied as they are.
    static func write(_ document: PDFDocument, adding lines: [Int: [TextLine]], to url: URL) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, info(of: document) as CFDictionary) else {
            throw ConversionError.outputMissing(url.lastPathComponent)
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var box = CGRect(origin: .zero, size: displaySize(of: page))
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            // Drawn as a reader sees it: PDFKit turns the page by its rotation.
            page.draw(with: .mediaBox, to: context)
            for line in lines[index] ?? [] {
                drawInvisibly(line, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        try copyOutline(of: document, into: url)
    }

    /// The page as a reader sees it: rotation swaps width and height.
    static func displaySize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        return page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
    }

    private static func info(of document: PDFDocument) -> [CFString: Any] {
        let attributes = document.documentAttributes ?? [:]
        let pairs: [(CFString, PDFDocumentAttribute)] = [(kCGPDFContextTitle, .titleAttribute),
                                                         (kCGPDFContextAuthor, .authorAttribute),
                                                         (kCGPDFContextSubject, .subjectAttribute)]
        let copied = pairs.compactMap { key, attribute in
            (attributes[attribute] as? String).map { (key, $0 as Any) }
        }
        return Dictionary(copied, uniquingKeysWith: { first, _ in first })
            .merging([kCGPDFContextCreator: creator]) { current, _ in current }
    }

    /// One line of text, stretched to the width it occupies on the scan. The
    /// stretch is in the font itself, so every glyph advance scales with it and
    /// readers still see the gaps between words.
    private static func drawInvisibly(_ line: TextLine, in context: CGContext) {
        let size = max(line.frame.height * fontShare, 1)
        let natural = CTLineGetTypographicBounds(makeLine(line.text, font: CTFontCreateWithName(fontName as CFString, size, nil)),
                                                 nil, nil, nil)
        guard natural > 0, line.frame.width > 0 else { return }
        var stretch = CGAffineTransform(scaleX: line.frame.width / CGFloat(natural), y: 1)
        let ctLine = makeLine(line.text, font: CTFontCreateWithName(fontName as CFString, size, &stretch))

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: line.frame.minX, y: line.frame.minY + line.frame.height * baselineShare)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }

    private static func makeLine(_ text: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text,
                                                            attributes: [.init(kCTFontAttributeName as String): font]))
    }

    /// A Core Graphics context writes pages only, so the table of contents is
    /// rebuilt on the new pages, which keep the same order.
    private static func copyOutline(of original: PDFDocument, into url: URL) throws {
        guard let outline = original.outlineRoot, outline.numberOfChildren > 0 else { return }
        guard let rewritten = PDFDocument(url: url) else {
            throw ConversionError.unreadableDocument(url.lastPathComponent)
        }
        rewritten.outlineRoot = copy(outline, from: original, to: rewritten)
        guard rewritten.write(to: url) else {
            throw ConversionError.outputMissing(url.lastPathComponent)
        }
    }

    private static func copy(_ node: PDFOutline, from original: PDFDocument, to target: PDFDocument) -> PDFOutline {
        let copy = PDFOutline()
        copy.label = node.label
        copy.isOpen = node.isOpen
        if let destination = node.destination, let page = destination.page {
            let index = original.index(for: page)
            if let newPage = target.page(at: index) {
                copy.destination = PDFDestination(page: newPage, at: destination.point)
            }
        }
        for childIndex in 0..<node.numberOfChildren {
            guard let child = node.child(at: childIndex) else { continue }
            copy.insertChild(self.copy(child, from: original, to: target), at: copy.numberOfChildren)
        }
        return copy
    }
}
