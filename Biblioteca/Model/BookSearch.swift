import Foundation

/// The Batch tab's search: narrows a long list of books by name and folder.
enum BookSearch {
    /// Books whose name or folder contains every word of the query, ignoring case
    /// and accents ("σεφερης" finds "Σεφέρης"). An empty query keeps every book.
    static func filter(_ jobs: [ConversionJob], query: String) -> [ConversionJob] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return jobs }
        return jobs.filter { job in
            let haystack = job.relativeFolder + " " + job.name
            return words.allSatisfy {
                haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
