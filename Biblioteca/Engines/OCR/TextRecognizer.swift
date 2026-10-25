import CoreGraphics
import Foundation

/// Finds the lines of text in a rendered page image.
protocol TextRecognizer: Sendable {
    var name: String { get }
    /// Lines in the page's own coordinate space: `pageSize` units, origin at the
    /// bottom-left, as PDF and DjVu both use.
    func recognize(_ image: CGImage, pageSize: CGSize) async throws -> [TextLine]
}

/// Reads Tesseract's `tsv` output: one row per word, grouped into lines by
/// their block, paragraph and line numbers.
enum TesseractTSV {
    private struct LineKey: Hashable {
        let page, block, paragraph, line: Int
    }

    private struct Word {
        let key: LineKey
        let text: String
        let box: CGRect

        /// Only word rows (level 5) that carry text; Tesseract also lists
        /// empty words, and rows for pages, blocks, paragraphs and lines.
        init?(row: Substring) {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 12, fields[0] == "5" else { return nil }
            let numbers = fields[1...9].compactMap { Int($0) }
            let text = fields[11...].joined(separator: "\t").trimmingCharacters(in: .whitespaces)
            guard numbers.count == 9, !text.isEmpty else { return nil }
            key = LineKey(page: numbers[0], block: numbers[1], paragraph: numbers[2], line: numbers[3])
            self.text = text
            box = CGRect(x: numbers[5], y: numbers[6], width: numbers[7], height: numbers[8])
        }
    }

    /// `scale` is image pixels per page unit; Tesseract's origin is the top-left.
    static func lines(from tsv: String, imageHeight: Int, scale: CGFloat) -> [TextLine] {
        let words = tsv.split(whereSeparator: \.isNewline).dropFirst().compactMap(Word.init(row:))
        let grouped = Dictionary(grouping: words, by: \.key)
        let order = words.map(\.key).reduce(into: [LineKey]()) { keys, key in
            if keys.last != key, !keys.contains(key) { keys.append(key) }
        }
        return order.compactMap { key in
            guard let members = grouped[key], let first = members.first else { return nil }
            let box = members.dropFirst().reduce(first.box) { $0.union($1.box) }
            let flipped = CGRect(x: box.minX, y: CGFloat(imageHeight) - box.maxY,
                                 width: box.width, height: box.height)
            return TextLine(text: members.map(\.text).joined(separator: " "),
                            frame: CGRect(x: flipped.minX / scale, y: flipped.minY / scale,
                                          width: flipped.width / scale, height: flipped.height / scale))
        }
    }
}
