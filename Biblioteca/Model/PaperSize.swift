import Foundation

/// Page sizes offered for formats that have no pages of their own (EPUB, MOBI…).
enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case a4, a5, letter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a4: "A4"
        case .a5: "A5"
        case .letter: "US Letter"
        }
    }

    var layout: PageLayout {
        switch self {
        case .a4: .a4
        case .a5: .a5
        case .letter: .letter
        }
    }
}
