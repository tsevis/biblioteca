import Foundation
import UniformTypeIdentifiers

/// Reads and writes an EPUB's title, authors and cover by editing its package
/// document (the OPF), with the `zip` and `unzip` every Mac has.
enum EPUBMetadata {
    private static let zip = URL(fileURLWithPath: "/usr/bin/zip")
    private static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
    private static let dublinCore = "http://purl.org/dc/elements/1.1/"
    private static let coverID = "biblioteca-cover"
    /// Several authors are written as one `dc:creator` each and read back joined with this.
    static let authorSeparator = " & "

    static func read(_ epub: URL) async throws -> BookMetadata {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let package = try await Package(unpacking: epub, into: workspace.url)
        let title = package.metadataElements(named: "title").first?.stringValue ?? ""
        let authors = package.metadataElements(named: "creator").compactMap(\.stringValue)
        return BookMetadata(title: title, author: authors.joined(separator: authorSeparator))
    }

    static func write(_ metadata: BookMetadata, to epub: URL) async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let root = workspace.url.appendingPathComponent("book", isDirectory: true)
        let package = try await Package(unpacking: epub, into: root)

        if !metadata.title.isEmpty {
            package.replaceMetadata(named: "title", with: [metadata.title])
        }
        if !metadata.author.isEmpty {
            let authors = metadata.author.components(separatedBy: "&")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            package.replaceMetadata(named: "creator", with: authors)
        }
        if let cover = metadata.cover {
            try package.setCover(cover)
        }
        try package.save()
        try await repack(root, to: epub, in: workspace.url)
    }

    /// The EPUB spec requires `mimetype` first and uncompressed.
    private static func repack(_ root: URL, to epub: URL, in workspace: URL) async throws {
        let staged = workspace.appendingPathComponent("repacked.epub")
        try await ProcessRunner.run(zip, arguments: ["-X0q", staged.path, "mimetype"], workingDirectory: root)
        let rest = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "mimetype" }
        try await ProcessRunner.run(zip, arguments: ["-Xr9Dq", staged.path] + rest, workingDirectory: root)
        _ = try FileManager.default.replaceItemAt(epub, withItemAt: staged)
    }

    /// An unpacked EPUB and its parsed package document.
    private final class Package {
        let opf: URL
        let document: XMLDocument

        init(unpacking epub: URL, into folder: URL) async throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await ProcessRunner.run(EPUBMetadata.unzip, arguments: ["-qo", epub.path, "-d", folder.path])
            let container = try XMLDocument(contentsOf: folder.appendingPathComponent("META-INF/container.xml"))
            guard let path = try container.nodes(forXPath: "//*[local-name()='rootfile']/@full-path").first?.stringValue
            else { throw ConversionError.unreadableDocument(epub.lastPathComponent) }
            opf = folder.appendingPathComponent(path)
            document = try XMLDocument(contentsOf: opf)
        }

        private func element(_ localName: String) -> XMLElement? {
            try? document.nodes(forXPath: "//*[local-name()='\(localName)']").first as? XMLElement
        }

        func metadataElements(named name: String) -> [XMLElement] {
            (element("metadata")?.children ?? []).compactMap { $0 as? XMLElement }
                .filter { $0.localName == name && $0.uri == EPUBMetadata.dublinCore }
        }

        func replaceMetadata(named name: String, with values: [String]) {
            guard let metadata = element("metadata") else { return }
            let existing = metadataElements(named: name)
            let position = existing.first?.index ?? metadata.childCount
            existing.reversed().forEach { metadata.removeChild(at: $0.index) }
            for (offset, value) in values.enumerated() {
                let element = XMLElement(name: "dc:\(name)", uri: EPUBMetadata.dublinCore)
                element.stringValue = value
                metadata.insertChild(element, at: min(position + offset, metadata.childCount))
            }
        }

        /// Copies the image next to the OPF and marks it as the cover, the
        /// EPUB 3 way (`cover-image`) and the EPUB 2 way (`<meta name="cover">`).
        func setCover(_ image: URL) throws {
            guard let manifest = element("manifest"), let metadata = element("metadata") else { return }
            let ext = image.pathExtension.lowercased()
            let fileName = "\(EPUBMetadata.coverID).\(ext)"
            let destination = opf.deletingLastPathComponent().appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: image, to: destination)

            for item in manifest.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                if item.attribute(forName: "id")?.stringValue == EPUBMetadata.coverID {
                    manifest.removeChild(at: item.index)
                } else if let properties = item.attribute(forName: "properties") {
                    let kept = (properties.stringValue ?? "").split(separator: " ")
                        .filter { $0 != "cover-image" }.joined(separator: " ")
                    if kept.isEmpty { item.removeAttribute(forName: "properties") } else { properties.stringValue = kept }
                }
            }
            let mediaType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg"
            manifest.addChild(Self.element("item", ["id": EPUBMetadata.coverID, "href": fileName,
                                                     "media-type": mediaType, "properties": "cover-image"]))

            let oldMeta = metadata.children?.compactMap { $0 as? XMLElement }
                .filter { $0.localName == "meta" && $0.attribute(forName: "name")?.stringValue == "cover" } ?? []
            oldMeta.reversed().forEach { metadata.removeChild(at: $0.index) }
            metadata.addChild(Self.element("meta", ["name": "cover", "content": EPUBMetadata.coverID]))
        }

        private static func element(_ name: String, _ attributes: [String: String]) -> XMLElement {
            let element = XMLElement(name: name)
            element.setAttributesWith(attributes)
            return element
        }

        func save() throws {
            try document.xmlData(options: [.nodeCompactEmptyElement]).write(to: opf)
        }
    }
}
