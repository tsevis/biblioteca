import AppKit

/// The app's artwork and identity: the TVD mark, the splash key art and the version.
enum Brand {
    static let name = "biblioteca"
    static let tagline = "Converts books between PDF, EPUB, MOBI, DjVu and more."
    static let website = URL(string: "https://tsevis.com")
    static let github = URL(string: "https://github.com/tsevis")

    /// Loaded by URL so a missing file shows up as an empty image here, not as a
    /// silently blank asset lookup somewhere in a view.
    static let logo = resource("TVDLogo", "pdf")
    static let splashArt = resource("SplashArt", "jpg")

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    private static func resource(_ name: String, _ ext: String) -> NSImage {
        Bundle.main.url(forResource: name, withExtension: ext)
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    }
}
