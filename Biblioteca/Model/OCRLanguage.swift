import Foundation

/// The language a scanned book is written in, which picks the recogniser.
enum OCRLanguage: String, CaseIterable, Identifiable, Sendable {
    case greek, polytonicGreek, english, french, german, italian, spanish, portuguese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .greek: "Greek"
        case .polytonicGreek: "Greek (polytonic)"
        case .english: "English"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .spanish: "Spanish"
        case .portuguese: "Portuguese"
        }
    }

    /// Apple Vision's code, or nil where Vision cannot read the language.
    var visionCode: String? {
        switch self {
        case .greek, .polytonicGreek: nil
        case .english: "en-US"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .italian: "it-IT"
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        }
    }

    /// Tesseract's codes. Greek books quote English often enough to read both.
    var tesseractCode: String {
        switch self {
        case .greek: "ell+eng"
        case .polytonicGreek: "grc+ell"
        case .english: "eng"
        case .french: "fra"
        case .german: "deu"
        case .italian: "ita"
        case .spanish: "spa"
        case .portuguese: "por"
        }
    }
}
