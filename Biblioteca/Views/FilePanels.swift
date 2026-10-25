import AppKit
import UniformTypeIdentifiers

/// Open panels for picking books and the output folder.
@MainActor
enum FilePanels {
    static func chooseBooks(_ completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Add Books or Folders"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = BookFormat.allCases
            .flatMap { UTType(filenameExtension: $0.fileExtension).map { [$0] } ?? [] }
            + [.pdf, .epub, .plainText, .html, .rtf, .folder]
        if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }

    static func chooseImage(_ completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Cover"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    static func chooseFolder(_ completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Save Converted Books In"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
