import Foundation

/// User-adjustable conversion options.
struct ConversionSettings: Sendable, Equatable {
    var paper: PaperSize = .a4
    var djvuDPI: Int = 300
    var djvuEncoding: DjVuEncoding = .blackAndWhite

    static let djvuDPIChoices = [150, 200, 300, 400, 600]

    var pageLayout: PageLayout { paper.layout }
}

/// Converts one file end to end: plans the route, runs each engine in a
/// scratch folder, and moves only a finished result next to the user's files.
struct Converter: Sendable {
    let planner: ConversionPlanner

    init(engines: [any ConversionEngine]) {
        planner = ConversionPlanner(engines: engines)
    }

    /// Engines in order of preference, built from the tools found on this Mac.
    static func availableEngines(tools: ToolLocator, settings: ConversionSettings) -> [any ConversionEngine] {
        let calibre = tools.url(for: "ebook-convert").map {
            CalibreEngine(ebookConvert: $0, layout: settings.pageLayout)
        }
        let djvuTools = DjVuTools(ddjvu: tools.url(for: "ddjvu"), djvutxt: tools.url(for: "djvutxt"),
                                  c44: tools.url(for: "c44"), cjb2: tools.url(for: "cjb2"),
                                  djvm: tools.url(for: "djvm"), djvused: tools.url(for: "djvused"))
        let djvu = DjVuEngine(tools: djvuTools, dpi: settings.djvuDPI, encoding: settings.djvuEncoding)
        let mupdf = tools.url(for: "mutool").map { MuPDFEngine(mutool: $0, layout: settings.pageLayout) }
        let candidates: [(any ConversionEngine)?] = [calibre, djvu, mupdf, NativeEngine()]
        return candidates.compactMap { $0 }
    }

    func route(from source: BookFormat, to target: BookFormat) -> [ConversionStep]? {
        planner.plan(from: source, to: target)
    }

    func convert(_ input: URL, to target: BookFormat, in directory: URL,
                 progress: @escaping ProgressHandler) async throws -> URL {
        guard let source = BookFormat(url: input) else {
            throw ConversionError.unreadableDocument(input.lastPathComponent)
        }
        guard let steps = route(from: source, to: target) else {
            throw ConversionError.unsupportedRoute(from: source, to: target)
        }

        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let baseName = input.deletingPathExtension().lastPathComponent

        var current = input
        for (index, step) in steps.enumerated() {
            try Task.checkCancellation()
            let next = workspace.url.appendingPathComponent("\(index)-\(baseName).\(step.target.fileExtension)")
            let share = 1 / Double(steps.count)
            try await run(step, input: current, output: next) { fraction in
                progress(fraction.map { (Double(index) + $0) * share })
            }
            current = next
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = Self.availableURL(in: directory, baseName: baseName, fileExtension: target.fileExtension)
        try FileManager.default.moveItem(at: current, to: destination)
        return destination
    }

    /// Tries the planned engine first, then every other engine that can do the
    /// same step, so one crashing tool does not fail a book another tool can convert.
    private func run(_ step: ConversionStep, input: URL, output: URL,
                     progress: @escaping ProgressHandler) async throws {
        let candidates = planner.engines.filter { $0.canConvert(from: step.source, to: step.target) }
        var firstError: Error?
        for engine in candidates {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: output)
            do {
                try await engine.convert(input, to: output, from: step.source, target: step.target,
                                         progress: progress)
                guard Self.isNonEmptyFile(output) else {
                    // Text extractors succeed with an empty file when a book is only page images.
                    throw step.target == .txt
                        ? ConversionError.noTextLayer
                        : ConversionError.outputMissing(output.lastPathComponent)
                }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstError = firstError ?? error
            }
        }
        throw firstError ?? ConversionError.unsupportedRoute(from: step.source, to: step.target)
    }

    /// `name.ext`, or `name 2.ext`, `name 3.ext`… so an existing file is never overwritten.
    static func availableURL(in directory: URL, baseName: String, fileExtension: String,
                             fileManager: FileManager = .default) -> URL {
        let candidates = sequence(first: 1) { $0 + 1 }.lazy.map { number in
            directory.appendingPathComponent(number == 1 ? baseName : "\(baseName) \(number)")
                .appendingPathExtension(fileExtension)
        }
        return candidates.first { !fileManager.fileExists(atPath: $0.path) }!
    }

    private static func isNonEmptyFile(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return size > 0
    }
}
