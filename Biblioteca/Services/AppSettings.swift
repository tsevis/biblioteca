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

    var converter: Converter {
        Converter(engines: Converter.availableEngines(tools: tools, settings: conversion))
    }

    func refreshTools() {
        tools = ToolLocator()
    }
}
