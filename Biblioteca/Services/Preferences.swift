import Foundation

/// Remembers the user's choices between launches.
///
/// Conversion settings are shared by both tabs; the target format, output
/// folder and skip choice are kept per tab under the given key prefix.
struct Preferences: @unchecked Sendable {
    private enum Key {
        static let target = "targetFormat"
        static let outputDirectory = "outputDirectory"
        static let skipExisting = "skipExisting"
        static let paper = "paperSize"
        static let djvuDPI = "djvuDPI"
        static let djvuEncoding = "djvuEncoding"
        static let recognizeScans = "recognizeScans"
        static let ocrLanguage = "ocrLanguage"
    }

    private let defaults: UserDefaults
    private let prefix: String

    init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    var targetFormat: BookFormat {
        get { defaults.string(forKey: prefix + Key.target).flatMap(BookFormat.init(rawValue:)) ?? .pdf }
        nonmutating set { defaults.set(newValue.rawValue, forKey: prefix + Key.target) }
    }

    var outputDirectory: URL? {
        get {
            defaults.string(forKey: prefix + Key.outputDirectory)
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        nonmutating set { defaults.set(newValue?.path, forKey: prefix + Key.outputDirectory) }
    }

    var skipExisting: Bool {
        get { defaults.object(forKey: prefix + Key.skipExisting) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: prefix + Key.skipExisting) }
    }

    /// Run OCR on books that are page scans. Off by default: it is slow.
    var recognizeScans: Bool {
        get { defaults.bool(forKey: prefix + Key.recognizeScans) }
        nonmutating set { defaults.set(newValue, forKey: prefix + Key.recognizeScans) }
    }

    var settings: ConversionSettings {
        get {
            let paper = defaults.string(forKey: Key.paper).flatMap(PaperSize.init(rawValue:)) ?? .a4
            let dpi = defaults.integer(forKey: Key.djvuDPI)
            let validDPI = ConversionSettings.djvuDPIChoices.contains(dpi) ? dpi : 300
            let encoding = defaults.string(forKey: Key.djvuEncoding)
                .flatMap(DjVuEncoding.init(rawValue:)) ?? .blackAndWhite
            let language = defaults.string(forKey: Key.ocrLanguage).flatMap(OCRLanguage.init(rawValue:)) ?? .greek
            return ConversionSettings(paper: paper, djvuDPI: validDPI, djvuEncoding: encoding, ocrLanguage: language)
        }
        nonmutating set {
            defaults.set(newValue.paper.rawValue, forKey: Key.paper)
            defaults.set(newValue.djvuDPI, forKey: Key.djvuDPI)
            defaults.set(newValue.djvuEncoding.rawValue, forKey: Key.djvuEncoding)
            defaults.set(newValue.ocrLanguage.rawValue, forKey: Key.ocrLanguage)
        }
    }
}
