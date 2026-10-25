import Foundation

/// Title, author and cover the user chose for a book before converting it.
/// An empty field means "keep what the book already has".
struct BookMetadata: Sendable, Equatable {
    enum Field: String, Sendable, CaseIterable {
        case title, author, cover

        var displayName: String {
            switch self {
            case .title: "title"
            case .author: "author"
            case .cover: "cover"
            }
        }
    }

    static let empty = BookMetadata()

    let title: String
    /// Several authors are separated with "&".
    let author: String
    let cover: URL?

    init(title: String = "", author: String = "", cover: URL? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cover = cover
    }

    /// The fields the user actually set.
    var fields: Set<Field> {
        var set = Set<Field>()
        if !title.isEmpty { set.insert(.title) }
        if !author.isEmpty { set.insert(.author) }
        if cover != nil { set.insert(.cover) }
        return set
    }

    var isEmpty: Bool { fields.isEmpty }

    /// Fills the fields left empty here from `other`.
    func filling(from other: BookMetadata) -> BookMetadata {
        BookMetadata(title: title.isEmpty ? other.title : title,
                     author: author.isEmpty ? other.author : author,
                     cover: cover ?? other.cover)
    }
}
