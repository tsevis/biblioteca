import CoreGraphics
import Foundation
import Vision

/// Apple's on-device text recognition, for the languages it reads.
struct VisionRecognizer: TextRecognizer {
    let name = "Apple Vision"
    /// BCP 47 codes, for example "en-US".
    let languages: [String]

    func recognize(_ image: CGImage, pageSize: CGSize) async throws -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            // Vision's boxes are normalised with the origin at the bottom-left, as the page's.
            return TextLine(text: text, frame: observation.boundingBox.toImageCoordinates(pageSize, origin: .lowerLeft))
        }
    }
}
