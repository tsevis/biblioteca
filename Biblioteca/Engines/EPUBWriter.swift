import Foundation

/// A chapter of plain text for `EPUBWriter`.
struct EPUBChapter: Sendable, Equatable {
    let title: String
    let paragraphs: [String]
}

/// Writes a minimal, valid EPUB 3 from plain-text chapters.
enum EPUBWriter {
    private static let zip = URL(fileURLWithPath: "/usr/bin/zip")

    static func write(title: String, author: String?, language: String,
                      chapters: [EPUBChapter], to output: URL) async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let root = workspace.url

        let files: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", containerXML),
            ("OEBPS/content.opf", packageOPF(title: title, author: author, language: language,
                                              chapterCount: chapters.count)),
            ("OEBPS/nav.xhtml", navigationXHTML(title: title, chapters: chapters)),
        ] + chapters.enumerated().map { index, chapter in
            ("OEBPS/\(chapterFile(index))", chapterXHTML(chapter, language: language))
        }
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }

        try? FileManager.default.removeItem(at: output)
        // The EPUB spec requires `mimetype` first and uncompressed.
        try await ProcessRunner.run(zip, arguments: ["-X0q", output.path, "mimetype"], workingDirectory: root)
        try await ProcessRunner.run(zip, arguments: ["-Xr9Dq", output.path, "META-INF", "OEBPS"],
                                    workingDirectory: root)
    }

    private static func chapterFile(_ index: Int) -> String {
        String(format: "chapter%04d.xhtml", index + 1)
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static func packageOPF(title: String, author: String?, language: String,
                                   chapterCount: Int) -> String {
        let indices = 0..<chapterCount
        let manifest = indices.map {
            "    <item id=\"c\($0)\" href=\"\(chapterFile($0))\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let spine = indices.map { "    <itemref idref=\"c\($0)\"/>" }.joined(separator: "\n")
        let creator = author.map { "\n    <dc:creator>\(escape($0))</dc:creator>" } ?? ""
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
            <dc:title>\(escape(title))</dc:title>\(creator)
            <dc:language>\(escape(language))</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(manifest)
          </manifest>
          <spine>
        \(spine)
          </spine>
        </package>
        """
    }

    private static func navigationXHTML(title: String, chapters: [EPUBChapter]) -> String {
        let items = chapters.enumerated().map { index, chapter in
            "      <li><a href=\"\(chapterFile(index))\">\(escape(chapter.title))</a></li>"
        }.joined(separator: "\n")
        return xhtml(title: title, language: "", body: """
          <nav epub:type="toc" id="toc">
            <h1>\(escape(title))</h1>
            <ol>
        \(items)
            </ol>
          </nav>
        """)
    }

    private static func chapterXHTML(_ chapter: EPUBChapter, language: String) -> String {
        let paragraphs = chapter.paragraphs.map { "  <p>\(escape($0))</p>" }.joined(separator: "\n")
        return xhtml(title: chapter.title, language: language,
                     body: "  <h2>\(escape(chapter.title))</h2>\n\(paragraphs)")
    }

    private static func xhtml(title: String, language: String, body: String) -> String {
        let lang = language.isEmpty ? "" : " xml:lang=\"\(escape(language))\" lang=\"\(escape(language))\""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"\(lang)>
        <head><meta charset="UTF-8"/><title>\(escape(title))</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        let cleaned = text.unicodeScalars.filter { scalar in
            // XML 1.0 forbids most control characters, which PDF text extraction can produce.
            scalar.value >= 0x20 || scalar == "\t" || scalar == "\n"
        }
        return String(String.UnicodeScalarView(cleaned))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
