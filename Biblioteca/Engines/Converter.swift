import Foundation

/// User-adjustable conversion options.
struct ConversionSettings: Sendable, Equatable {
    var paper: PaperSize = .a4
    var djvuDPI: Int = 300
    var djvuEncoding: DjVuEncoding = .blackAndWhite
    var ocrLanguage: OCRLanguage = .greek

    static let djvuDPIChoices = [150, 200, 300, 400, 600]

    var pageLayout: PageLayout { paper.layout }
}

/// Converts one file end to end: plans the route, runs each engine in a
/// scratch folder, and moves only a finished result next to the user's files.
struct Converter: Sendable {
    let planner: ConversionPlanner
    /// Recognises text on scanned pages before converting; nil leaves scans as they are.
    let ocr: OCRProcessor?
    let metadataWriter: MetadataWriter

    init(engines: [any ConversionEngine], ocr: OCRProcessor? = nil,
         metadataWriter: MetadataWriter = MetadataWriter()) {
        planner = ConversionPlanner(engines: engines)
        self.ocr = ocr
        self.metadataWriter = metadataWriter
    }

    /// The metadata writer, built from the tools found on this Mac.
    static func metadataWriter(tools: ToolLocator) -> MetadataWriter {
        MetadataWriter(djvused: tools.url(for: "djvused"))
    }

    /// Engines in order of preference, built from the tools found on this Mac.
    static func availableEngines(tools: ToolLocator, settings: ConversionSettings) -> [any ConversionEngine] {
        let djvuTools = DjVuTools(ddjvu: tools.url(for: "ddjvu"), djvutxt: tools.url(for: "djvutxt"),
                                  c44: tools.url(for: "c44"), cjb2: tools.url(for: "cjb2"),
                                  djvm: tools.url(for: "djvm"), djvused: tools.url(for: "djvused"))
        let djvu = DjVuEngine(tools: djvuTools, dpi: settings.djvuDPI, encoding: settings.djvuEncoding)
        let mupdf = tools.url(for: "mutool").map { MuPDFEngine(mutool: $0, layout: settings.pageLayout) }
        let candidates: [(any ConversionEngine)?] = [djvu, mupdf, NativeEngine(layout: settings.pageLayout)]
        return candidates.compactMap { $0 }
    }

    func route(from source: BookFormat, to target: BookFormat) -> [ConversionStep]? {
        planner.plan(from: source, to: target)
    }

    func convert(_ input: URL, to target: BookFormat, in directory: URL, metadata: BookMetadata = .empty,
                 progress: @escaping ProgressHandler) async throws -> URL {
        guard let source = BookFormat(url: input) else {
            throw ConversionError.unreadableDocument(input.lastPathComponent)
        }
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let baseName = input.deletingPathExtension().lastPathComponent

        var result: URL
        if let ocr, OCRRoute.recognizes(source) {
            result = try await convertRecognizing(input, from: source, to: target, ocr: ocr,
                                                  workspace: workspace.url, baseName: baseName, progress: progress)
        } else {
            guard let steps = route(from: source, to: target) else {
                throw ConversionError.unsupportedRoute(from: source, to: target)
            }
            result = try await run(steps, from: input, workspace: workspace.url, name: baseName, progress: progress)
        }

        if !metadata.isEmpty {
            // Never write into the user's original, even on a route with no steps.
            if result == input {
                let copy = try Self.scratchURL(in: workspace.url, name: baseName, fileExtension: target.fileExtension)
                try FileManager.default.copyItem(at: input, to: copy)
                result = copy
            }
            try await metadataWriter.apply(metadata, to: result, format: target)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = Self.availableURL(in: directory, baseName: baseName, fileExtension: target.fileExtension)
        try FileManager.default.moveItem(at: result, to: destination)
        return destination
    }

    /// Runs the steps one after another in `workspace`, each sharing the progress equally.
    func run(_ steps: [ConversionStep], from input: URL, workspace: URL, name: String,
             progress: @escaping ProgressHandler) async throws -> URL {
        var current = input
        for (index, step) in steps.enumerated() {
            try Task.checkCancellation()
            let next = try Self.scratchURL(in: workspace, name: name, fileExtension: step.target.fileExtension)
            let share = 1 / Double(steps.count)
            try await run(step, input: current, output: next) { fraction in
                progress(fraction.map { (Double(index) + $0) * share })
            }
            current = next
        }
        return current
    }

    /// Tries the planned engine first, then every other engine that can do the
    /// same step, so one crashing tool does not fail a book another tool can convert.
    private func run(_ step: ConversionStep, input: URL, output: URL,
                     progress: @escaping ProgressHandler) async throws {
        let capable = planner.engines.filter { $0.canConvert(from: step.source, to: step.target) }
        let candidates = capable.filter { $0.id == step.engine.id } + capable.filter { $0.id != step.engine.id }
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

    /// A file named after the book in a folder of its own, since converters
    /// take a book's title from its file name when it has no title inside.
    static func scratchURL(in workspace: URL, name: String, fileExtension: String) throws -> URL {
        let folder = workspace.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
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
