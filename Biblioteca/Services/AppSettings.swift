import Foundation
import Observation

/// What both tabs share: the conversion settings and the converters installed.
@MainActor
@Observable
final class AppSettings {
    private(set) var tools = ToolLocator()

    var conversion: ConversionSettings {
        didSet { preferences.settings = conversion }
    }

    private let preferences: Preferences

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        conversion = preferences.settings
    }

    var converter: Converter { converter(recognizingScans: false) }

    func converter(recognizingScans: Bool) -> Converter {
        Converter(engines: Converter.availableEngines(tools: tools, settings: conversion),
                  ocr: recognizingScans ? ocr : nil,
                  metadataWriter: Converter.metadataWriter(tools: tools))
    }

    /// The recogniser for the chosen language, or nil when it needs Tesseract and Tesseract is missing.
    var ocr: OCRProcessor? {
        OCRProcessor.make(language: conversion.ocrLanguage, tesseract: tools.url(for: "tesseract"),
                          tessdata: tools.tessdataDirectory)
    }

    func refreshTools() {
        tools = ToolLocator()
    }
}
