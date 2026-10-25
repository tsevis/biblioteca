import Foundation

/// A book found among dropped or chosen items.
struct ScannedBook: Sendable, Equatable {
    let url: URL
    /// Where the book sits relative to the folder it was found in, starting
    /// with that folder's own name ("Library/Poetry"); empty for a loose file.
    let relativeFolder: String
}

/// Turns dropped files and folders into the list of books inside them.
enum BookScanner {
    /// Loose book files are kept as they are; folders are searched to any depth,
    /// skipping hidden files and the insides of packages. Within a folder, its own
    /// books come before those of its subfolders.
    static func books(in items: [URL], fileManager: FileManager = .default) -> [ScannedBook] {
        items.flatMap { item -> [ScannedBook] in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) else { return [] }
            if !isDirectory.boolValue {
                return BookFormat(url: item) == nil ? [] : [ScannedBook(url: item, relativeFolder: "")]
            }
            return books(inFolder: item, fileManager: fileManager)
        }
    }

    private static func books(inFolder root: URL, fileManager: FileManager) -> [ScannedBook] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        let found = walker.compactMap { $0 as? URL }.compactMap { url -> ScannedBook? in
            guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true,
                  BookFormat(url: url) != nil
            else { return nil }
            let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            let inside = folder.dropFirst(rootComponents.count)
            let relative = ([root.lastPathComponent] + inside).joined(separator: "/")
            return ScannedBook(url: url, relativeFolder: relative)
        }
        return found.sorted { lhs, rhs in
            lhs.relativeFolder == rhs.relativeFolder
                ? lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
                : lhs.relativeFolder.localizedStandardCompare(rhs.relativeFolder) == .orderedAscending
        }
    }
}
