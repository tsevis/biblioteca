import Foundation
import Observation
import os

/// The list of books to convert, the chosen target, and the running batch.
@MainActor
@Observable
final class ConversionQueue {
    private static let log = Logger(subsystem: "com.tsevis.biblioteca", category: "queue")

    private(set) var jobs: [ConversionJob] = []
    private(set) var tools = ToolLocator()
    private(set) var isRunning = false

    var targetFormat: BookFormat {
        didSet { preferences.targetFormat = targetFormat }
    }
    /// nil means "next to each original".
    var outputDirectory: URL? {
        didSet { preferences.outputDirectory = outputDirectory }
    }
    var settings: ConversionSettings {
        didSet { preferences.settings = settings }
    }

    private let preferences: Preferences
    private var batch: Task<Void, Never>?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        targetFormat = preferences.targetFormat
        outputDirectory = preferences.outputDirectory
        settings = preferences.settings
    }

    private var converter: Converter {
        Converter(engines: Converter.availableEngines(tools: tools, settings: settings))
    }

    // MARK: Queue editing

    func add(_ urls: [URL]) {
        let known = Set(jobs.map(\.source.standardizedFileURL))
        let fresh = urls
            .map(\.standardizedFileURL)
            .filter { !known.contains($0) && !$0.hasDirectoryPath }
        jobs += fresh.map(ConversionJob.init(source:))
    }

    func remove(_ ids: Set<ConversionJob.ID>) {
        jobs = jobs.filter { !ids.contains($0.id) || $0.isActive }
    }

    func clearFinished() {
        jobs = jobs.filter {
            if case .finished = $0.status { return false }
            return true
        }
    }

    func refreshTools() {
        tools = ToolLocator()
    }

    // MARK: Routing

    /// The engines a job would pass through, e.g. "DjVuLibre → biblioteca", or nil if none can.
    func routeDescription(for job: ConversionJob) -> String? {
        guard let format = job.format,
              let steps = converter.route(from: format, to: targetFormat)
        else { return nil }
        return steps.map(\.engine.id.displayName).joined(separator: " → ")
    }

    var canStart: Bool {
        !isRunning && jobs.contains { $0.isPending }
    }

    // MARK: Running

    func start() {
        guard canStart else { return }
        isRunning = true
        let target = targetFormat
        let converter = converter
        let pending = jobs.filter(\.isPending).map(\.id)
        batch = Task {
            for id in pending {
                if Task.isCancelled { break }
                await run(id, to: target, with: converter)
            }
            isRunning = false
            batch = nil
        }
    }

    func cancel() {
        batch?.cancel()
    }

    private func run(_ id: ConversionJob.ID, to target: BookFormat, with converter: Converter) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard job.format != target else {
            update(id, .failed("Already a \(target.displayName) file."))
            return
        }
        update(id, .converting(progress: nil))
        let directory = outputDirectory ?? job.source.deletingLastPathComponent()
        do {
            let result = try await converter.convert(job.source, to: target, in: directory) { [weak self] fraction in
                Task { @MainActor in self?.reportProgress(id, fraction) }
            }
            update(id, .finished(result))
        } catch is CancellationError {
            update(id, .cancelled)
        } catch {
            Self.log.error("Converting \(job.source.path, privacy: .public) failed: \(error, privacy: .public)")
            update(id, Task.isCancelled ? .cancelled : .failed(error.localizedDescription))
        }
    }

    private func reportProgress(_ id: ConversionJob.ID, _ fraction: Double?) {
        guard let job = jobs.first(where: { $0.id == id }), job.isActive else { return }
        update(id, .converting(progress: fraction))
    }

    private func update(_ id: ConversionJob.ID, _ status: ConversionJob.Status) {
        jobs = jobs.map { $0.id == id ? $0.with(status: status) : $0 }
    }
}
