import Foundation
import PDFKit

/// One line of text on a PDF page and where it sits.
struct TextLine: Sendable, Equatable {
    let text: String
    let frame: CGRect
}

/// Pulls reflowable text out of a PDF and splits it into chapters.
///
/// Chapters follow the PDF's top-level bookmarks when it has them; otherwise
/// the book is cut every `pagesPerChapter` pages.
enum PDFTextExtractor {
    static let pagesPerChapter = 10

    static func chapters(of document: PDFDocument) -> [EPUBChapter] {
        let starts = outlineStarts(of: document)
        let ranges = starts.isEmpty
            ? stride(from: 0, to: document.pageCount, by: pagesPerChapter).map {
                (title: "Pages \($0 + 1)–\(min($0 + pagesPerChapter, document.pageCount))", first: $0)
            }
            : starts

        return ranges.enumerated().compactMap { index, start in
            let end = index + 1 < ranges.count ? ranges[index + 1].first : document.pageCount
            // Lines from consecutive pages are laid end to end, so a paragraph
            // that runs over a page break stays whole.
            let text = Self.text(ofPages: (start.first..<max(end, start.first + 1))
                .compactMap { document.page(at: $0) }
                .map(lines(of:)))
            let paragraphs = paragraphs(in: text)
            return paragraphs.isEmpty ? nil : EPUBChapter(title: start.title, paragraphs: paragraphs)
        }
    }

    /// Joins wrapped lines into paragraphs and repairs words hyphenated across lines.
    static func paragraphs(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { block in
                block
                    .replacingOccurrences(of: #"(\p{L})-\n(\p{Ll})"#, with: "$1$2", options: .regularExpression)
                    .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    /// A line ending this far short of the right margin (as a share of the column) ends its paragraph.
    private static let shortLineShare: CGFloat = 0.15
    /// A gap this many times the usual line spacing starts a new paragraph.
    private static let paragraphGapFactor: CGFloat = 1.5
    /// Running heads alternate between left and right pages, so a page's twin is two pages away.
    private static let runningHeadReach = 2

    /// A line and whether a paragraph ends after it.
    private struct MarkedLine {
        let text: String
        let endsParagraph: Bool
    }

    /// Rebuilds the paragraph breaks ("\n\n") that PDFKit's plain text loses,
    /// from where each line sits on its page. Each page is measured on its own,
    /// since the left and right pages of a scanned book sit at different offsets.
    static func text(ofPages pages: [[TextLine]]) -> String {
        let heads = runningHeads(in: pages)
        let marked = pages.enumerated().flatMap { index, page in
            markParagraphEnds(on: heads.contains(index) ? Array(page.dropFirst()) : page)
        }
        guard let first = marked.first else { return "" }
        return zip(marked, marked.dropFirst()).reduce(first.text) { text, pair in
            text + (pair.0.endsParagraph ? "\n\n" : "\n") + pair.1.text
        }
    }

    static func text(of lines: [TextLine]) -> String {
        text(ofPages: [lines])
    }

    private static func usualGap(on page: [TextLine]) -> CGFloat {
        let gaps = zip(page, page.dropFirst())
            .map { $0.frame.minY - $1.frame.minY }
            .filter { $0 > 0 }
            .sorted()
        return gaps.isEmpty ? 0 : gaps[gaps.count / 2]
    }

    private static func isParagraphGap(_ gap: CGFloat, usualGap: CGFloat) -> Bool {
        usualGap > 0 && gap > usualGap * paragraphGapFactor
    }

    private static func markParagraphEnds(on lines: [TextLine]) -> [MarkedLine] {
        let usual = usualGap(on: lines)
        let left = lines.map(\.frame.minX).min() ?? 0
        let right = lines.map(\.frame.maxX).max() ?? 0
        let shortLineEdge = right - (right - left) * shortLineShare

        return lines.enumerated().map { index, line in
            let gap = index + 1 < lines.count ? line.frame.minY - lines[index + 1].frame.minY : 0
            return MarkedLine(text: line.text, endsParagraph: line.frame.maxX < shortLineEdge
                                  || isParagraphGap(gap, usualGap: usual))
        }
    }

    /// Pages whose first line is a running head, such as "Θάλασσα 19": a page
    /// number at one end, a gap below, and the same words heading a page up to
    /// `runningHeadReach` pages away. A chapter heading like "Κεφάλαιο 1" does not repeat.
    private static func runningHeads(in pages: [[TextLine]]) -> Set<Int> {
        let candidates = pages.map(headCandidate(of:))
        return Set(candidates.indices.filter { index in
            guard let words = candidates[index] else { return false }
            let nearby = max(0, index - runningHeadReach)...min(candidates.count - 1, index + runningHeadReach)
            return nearby.contains { other in
                other != index && candidates[other].map { RunningHead.isSimilar($0, words) } == true
            }
        })
    }

    /// The first line's words without its page number, when it could be a running head.
    private static func headCandidate(of page: [TextLine]) -> String? {
        guard page.count > 1,
              page[0].text.range(of: #"^\d+\s|\s\d+$"#, options: .regularExpression) != nil,
              isParagraphGap(page[0].frame.minY - page[1].frame.minY, usualGap: usualGap(on: page))
        else { return nil }
        return RunningHead.letters(of: page[0].text)
    }

    /// The lines of a page in reading order, without bare page numbers.
    static func lines(of page: PDFPage) -> [TextLine] {
        let selection = page.selection(for: page.bounds(for: .cropBox))
        return (selection?.selectionsByLine() ?? []).compactMap { line in
            let text = (line.string ?? "").trimmingCharacters(in: .whitespaces)
            let isPageNumber = !text.isEmpty && text.allSatisfy(\.isNumber)
            guard !text.isEmpty, !isPageNumber else { return nil }
            return TextLine(text: text, frame: line.bounds(for: page))
        }
    }

    private static func outlineStarts(of document: PDFDocument) -> [(title: String, first: Int)] {
        guard let root = document.outlineRoot else { return [] }
        let entries = (0..<root.numberOfChildren).compactMap { index -> (title: String, first: Int)? in
            guard let child = root.child(at: index),
                  let page = child.destination?.page
            else { return nil }
            let pageIndex = document.index(for: page)
            return (child.label ?? "Chapter \(index + 1)", pageIndex)
        }
        let ordered = entries.sorted { $0.first < $1.first }
        guard let first = ordered.first else { return [] }
        // Keep any front matter before the first bookmark.
        return first.first > 0 ? [("Front matter", 0)] + ordered : ordered
    }
}
