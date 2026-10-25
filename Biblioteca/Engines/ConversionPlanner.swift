import Foundation

/// A single hop of a conversion: one engine, one source format, one target format.
struct ConversionStep: Sendable {
    let engine: any ConversionEngine
    let source: BookFormat
    let target: BookFormat
}

/// Chooses which engines carry a file from one format to another.
///
/// Engines are tried in the order given, so earlier engines win. When no engine
/// converts directly, the planner routes through PDF, which every engine family
/// speaks (for example DjVu → PDF with DjVuLibre, then PDF → EPUB with Calibre).
struct ConversionPlanner: Sendable {
    let engines: [any ConversionEngine]

    func plan(from source: BookFormat, to target: BookFormat) -> [ConversionStep]? {
        guard source != target else { return nil }
        if let direct = directStep(from: source, to: target) {
            return [direct]
        }
        guard source != .pdf, target != .pdf,
              let first = directStep(from: source, to: .pdf),
              let second = directStep(from: .pdf, to: target)
        else { return nil }
        return [first, second]
    }

    private func directStep(from source: BookFormat, to target: BookFormat) -> ConversionStep? {
        engines
            .first { $0.canConvert(from: source, to: target) }
            .map { ConversionStep(engine: $0, source: source, target: target) }
    }
}
