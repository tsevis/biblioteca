import Foundation
import Testing

/// An engine that converts exactly the pairs it is given and does nothing else.
private struct FakeEngine: ConversionEngine {
    let id: EngineID
    let pairs: Set<String>

    init(_ id: EngineID, _ pairs: [(BookFormat, BookFormat)]) {
        self.id = id
        self.pairs = Set(pairs.map { "\($0.0.rawValue)>\($0.1.rawValue)" })
    }

    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool {
        pairs.contains("\(source.rawValue)>\(target.rawValue)")
    }

    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {}
}

private func describe(_ steps: [ConversionStep]?) -> [String]? {
    steps?.map { "\($0.engine.id.rawValue):\($0.source.rawValue)>\($0.target.rawValue)" }
}

@Suite("ConversionPlanner")
struct ConversionPlannerTests {
    @Test("Earlier engines win when several convert directly")
    func prefersEarlierEngine() {
        let planner = ConversionPlanner(engines: [
            FakeEngine(.calibre, [(.epub, .pdf)]),
            FakeEngine(.mupdf, [(.epub, .pdf)]),
        ])
        #expect(describe(planner.plan(from: .epub, to: .pdf)) == ["calibre:epub>pdf"])
    }

    @Test("Routes through PDF when no engine converts directly")
    func chainsThroughPDF() {
        let planner = ConversionPlanner(engines: [
            FakeEngine(.djvulibre, [(.djvu, .pdf)]),
            FakeEngine(.native, [(.pdf, .epub)]),
        ])
        #expect(describe(planner.plan(from: .djvu, to: .epub))
            == ["djvulibre:djvu>pdf", "native:pdf>epub"])
    }

    @Test("Returns nil when either half of the PDF route is missing")
    func noRouteWithoutBothHalves() {
        let planner = ConversionPlanner(engines: [FakeEngine(.djvulibre, [(.djvu, .pdf)])])
        #expect(planner.plan(from: .djvu, to: .epub) == nil)
    }

    @Test("Converting a format to itself is not a plan")
    func sameFormatHasNoPlan() {
        let planner = ConversionPlanner(engines: [FakeEngine(.mupdf, [(.pdf, .pdf)])])
        #expect(planner.plan(from: .pdf, to: .pdf) == nil)
    }
}
