import Foundation

/// Which conversions read scans, and the steps that follow recognition.
enum OCRRoute {
    /// Formats that can hold page scans the recogniser can read.
    static func recognizes(_ format: BookFormat) -> Bool {
        format == .pdf || format == .djvu
    }

    /// Reflowable formats are built from the recognised text by biblioteca's
    /// own PDF reader, through EPUB: other converters would carry the page
    /// scans along as images.
    static func steps(fromSearchablePDFTo target: BookFormat, planner: ConversionPlanner) -> [ConversionStep]? {
        let native = planner.engines.filter { $0.id == .native }
        let nativePlanner = ConversionPlanner(engines: native)
        switch target {
        case .pdf:
            return []
        case .djvu:
            return planner.plan(from: .pdf, to: .djvu)
        case .epub, .txt:
            return nativePlanner.directStep(from: .pdf, to: target).map { [$0] }
        default:
            guard let toEPUB = nativePlanner.directStep(from: .pdf, to: .epub),
                  let fromEPUB = planner.directStep(from: .epub, to: target)
            else { return nil }
            return [toEPUB, fromEPUB]
        }
    }
}

extension Converter {
    /// Progress share of each phase: reaching PDF, recognising, then converting on.
    private static let phases = (toPDF: 0.1, recognition: 0.85)

    func convertRecognizing(_ input: URL, from source: BookFormat, to target: BookFormat, ocr: OCRProcessor,
                            workspace: URL, baseName: String,
                            progress: @escaping ProgressHandler) async throws -> URL {
        if source == .djvu, target == .djvu {
            return try await addDjVuText(input, ocr: ocr, workspace: workspace, baseName: baseName, progress: progress)
        }
        let toPDF = source == .pdf ? [] : try requiredSteps(from: source, to: .pdf)
        let scan = try await run(toPDF, from: input, workspace: workspace, name: baseName,
                                 progress: Self.scaled(progress, from: 0, to: Self.phases.toPDF))

        let searchable = try Self.scratchURL(in: workspace, name: baseName, fileExtension: "pdf")
        let recognized = try await ocr.makeSearchable(
            scan, to: searchable,
            progress: Self.scaled(progress, from: Self.phases.toPDF, to: Self.phases.recognition))

        if !recognized, source == .pdf, target == .pdf {
            throw ConversionError.alreadySearchable
        }
        let pdf = recognized ? searchable : scan
        let onward = recognized
            ? OCRRoute.steps(fromSearchablePDFTo: target, planner: planner)
            : (target == .pdf ? [] : planner.plan(from: .pdf, to: target))
        guard let onward else { throw ConversionError.unsupportedRoute(from: source, to: target) }
        let result = try await run(onward, from: pdf, workspace: workspace, name: baseName,
                                   progress: Self.scaled(progress, from: Self.phases.recognition, to: 1))
        // Never hand back the user's own file: the caller moves the result.
        guard result != input else { throw ConversionError.alreadySearchable }
        return result
    }

    private func addDjVuText(_ input: URL, ocr: OCRProcessor, workspace: URL, baseName: String,
                             progress: @escaping ProgressHandler) async throws -> URL {
        let tools = planner.engines.compactMap { ($0 as? DjVuEngine)?.tools }.first
        guard let recognition = tools.flatMap(DjVuRecognition.init(tools:)) else {
            throw ConversionError.unsupportedRoute(from: .djvu, to: .djvu)
        }
        let output = try Self.scratchURL(in: workspace, name: baseName, fileExtension: "djvu")
        try await recognition.addText(input, to: output, recognizer: ocr.recognizer, progress: progress)
        return output
    }

    /// The tools a book passes through, e.g. "DjVuLibre → Tesseract → biblioteca", or nil if none can.
    func routeDescription(from source: BookFormat, to target: BookFormat) -> String? {
        guard let ocr, OCRRoute.recognizes(source) else {
            return route(from: source, to: target).map { $0.map(\.engine.id.displayName).joined(separator: " → ") }
        }
        if source == .djvu, target == .djvu {
            return "\(ocr.recognizer.name) → \(EngineID.djvulibre.displayName)"
        }
        let toPDF = source == .pdf ? [] : route(from: source, to: .pdf)
        guard let toPDF, let onward = OCRRoute.steps(fromSearchablePDFTo: target, planner: planner) else { return nil }
        let names = toPDF.map(\.engine.id.displayName) + [ocr.recognizer.name] + onward.map(\.engine.id.displayName)
        return names.joined(separator: " → ")
    }

    private func requiredSteps(from source: BookFormat, to target: BookFormat) throws -> [ConversionStep] {
        guard let steps = route(from: source, to: target) else {
            throw ConversionError.unsupportedRoute(from: source, to: target)
        }
        return steps
    }

    private static func scaled(_ progress: @escaping ProgressHandler, from start: Double,
                               to end: Double) -> ProgressHandler {
        { fraction in progress(fraction.map { start + $0 * (end - start) }) }
    }
}
