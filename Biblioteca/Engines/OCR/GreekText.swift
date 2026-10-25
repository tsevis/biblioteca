import Foundation

/// Fixes the characters Tesseract confuses in Greek text: Latin capitals that
/// look like Greek ones ("H" for "Η") and the micro sign for "μ".
enum GreekText {
    private static let lookalikes: [Character: Character] = [
        "A": "Α", "B": "Β", "E": "Ε", "Z": "Ζ", "H": "Η", "I": "Ι", "K": "Κ", "M": "Μ",
        "N": "Ν", "O": "Ο", "P": "Ρ", "T": "Τ", "Y": "Υ", "X": "Χ", "o": "ο", "µ": "μ",
    ]
    /// A word of look-alikes alone is taken as Greek only when this short,
    /// like the article "H"; longer ones may be Latin, like "TOY".
    private static let shortWordLength = 2

    static func repair(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: false)
            .map(repair(word:))
            .joined(separator: " ")
    }

    private static func repair(word: Substring) -> String {
        let letters = word.filter(\.isLetter)
        let hasGreek = letters.contains(where: isGreek)
        let isShortLookalike = !letters.isEmpty && letters.count <= shortWordLength
            && letters.allSatisfy { lookalikes[$0] != nil }
        guard hasGreek || isShortLookalike else { return String(word) }
        return String(word.map { lookalikes[$0] ?? $0 })
    }

    private static func isGreek(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }
}
