import Foundation
import Testing

@Suite("BookSearch")
struct BookSearchTests {
    private let library = [
        ConversionJob(source: URL(fileURLWithPath: "/l/Ποίηση/Σεφέρης/Ημερολόγιο Καταστρώματος.epub"),
                      relativeFolder: "Ποίηση/Σεφέρης"),
        ConversionJob(source: URL(fileURLWithPath: "/l/Design/1000 Tiles (Gordon Lang).pdf"),
                      relativeFolder: "Design"),
        ConversionJob(source: URL(fileURLWithPath: "/l/Design/100 illustrators (Steven Heller).pdf"),
                      relativeFolder: "Design"),
    ]

    private func names(_ query: String) -> [String] {
        BookSearch.filter(library, query: query).map(\.name)
    }

    @Test("Every word must match the name or folder, ignoring case and accents")
    func matchesWordsAcrossNameAndFolder() {
        #expect(names("") == library.map(\.name))
        #expect(names("  ") == library.map(\.name))
        #expect(names("σεφερης ημερολογιο") == ["Ημερολόγιο Καταστρώματος.epub"])
        #expect(names("lang design") == ["1000 Tiles (Gordon Lang).pdf"])
        #expect(names("design") == ["1000 Tiles (Gordon Lang).pdf", "100 illustrators (Steven Heller).pdf"])
        #expect(names("heller lang").isEmpty)
    }
}
