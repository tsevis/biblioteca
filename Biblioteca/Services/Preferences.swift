import Foundation

/// Remembers the user's choices between launches.
struct Preferences: @unchecked Sendable {
    private enum Key {
        static let target = "targetFormat"
        static let outputDirectory = "outputDirectory"
        static let paper = "paperSize"
        static let djvuDPI = "djvuDPI"
        static let djvuEncoding = "djvuEncoding"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var targetFormat: BookFormat {
        get { defaults.string(forKey: Key.target).flatMap(BookFormat.init(rawValue:)) ?? .pdf }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.target) }
    }

    var outputDirectory: URL? {
        get { defaults.string(forKey: Key.outputDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        nonmutating set { defaults.set(newValue?.path, forKey: Key.outputDirectory) }
    }

    var settings: ConversionSettings {
        get {
            let paper = defaults.string(forKey: Key.paper).flatMap(PaperSize.init(rawValue:)) ?? .a4
            let dpi = defaults.integer(forKey: Key.djvuDPI)
            let validDPI = ConversionSettings.djvuDPIChoices.contains(dpi) ? dpi : 300
            let encoding = defaults.string(forKey: Key.djvuEncoding)
                .flatMap(DjVuEncoding.init(rawValue:)) ?? .blackAndWhite
            return ConversionSettings(paper: paper, djvuDPI: validDPI, djvuEncoding: encoding)
        }
        nonmutating set {
            defaults.set(newValue.paper.rawValue, forKey: Key.paper)
            defaults.set(newValue.djvuDPI, forKey: Key.djvuDPI)
            defaults.set(newValue.djvuEncoding.rawValue, forKey: Key.djvuEncoding)
        }
    }
}
