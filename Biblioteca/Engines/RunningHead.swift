import Foundation

/// Compares running heads as OCR reads them, slips included: "Λόγια τῆς πλώρης"
/// on one page may be "“όγια τῆς πλώρης" on the next.
enum RunningHead {
    /// Letters only, without accents or case.
    static func letters(of text: String) -> String {
        String(text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter(\.isLetter))
    }

    /// Within a few edits of each other: one in four letters may differ.
    static func isSimilar(_ first: String, _ second: String) -> Bool {
        guard !first.isEmpty, !second.isEmpty else { return false }
        return editDistance(Array(first), Array(second)) <= max(1, max(first.count, second.count) / 4)
    }

    private static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
        let start = Array(0...second.count)
        let last = first.enumerated().reduce(start) { previous, item in
            let (row, character) = item
            return second.enumerated().reduce(into: [row + 1]) { current, pair in
                let (column, other) = pair
                current.append(min(previous[column + 1] + 1, current[column] + 1,
                                   previous[column] + (character == other ? 0 : 1)))
            }
        }
        return last[second.count]
    }
}
