import Foundation
import Observation
import os

/// The list of books to convert, the chosen target, and the running batch.
///
/// The Convert tab (`.quick`) saves each result beside its original or into
/// one chosen folder. The Batch tab (`.batch`) always writes into an output
/// folder, recreating the folder structure the books came from, and can skip
/// books that were already converted by an earlier run.
@MainActor
@Observable
final class ConversionQueue {
    enum Mode: Sendable {
        case quick, batch
    }

    private static let log = Logger(subsystem: "com.tsevis.biblioteca", category: "queue")

    let mode: Mode
    let settings: AppSettings
    private(set) var jobs: [ConversionJob] = []
    private(set) var isRunning = false
    /// The books the running (or last) Convert took on, so its count ignores the rest.
    private(set) var runIDs: Set<ConversionJob.ID> = []

    /// Batch only: narrows the list, and Convert then takes only the books it shows.
    var searchText = ""

    var targetFormat: BookFormat {
        didSet { preferences.targetFormat = targetFormat }
    }
    /// In the Convert tab, nil means "next to each original". The Batch tab needs one.
    var outputDirectory: URL? {
        didSet { preferences.outputDirectory = outputDirectory }
    }
    /// Batch only: leave a book alone when its converted file is already in place.
    var skipExisting: Bool {
        didSet { preferences.skipExisting = skipExisting }
    }

    /// Recognise text on scanned PDF and DjVu pages before converting.
    var recognizeScans: Bool {
        didSet { preferences.recognizeScans = recognizeScans }
    }

    private let preferences: Preferences
    private var batch: Task<Void, Never>?

    init(mode: Mode, settings: AppSettings, preferences: Preferences) {
        self.mode = mode
        self.settings = settings
        self.preferences = preferences
        targetFormat = preferences.targetFormat
        outputDirectory = preferences.outputDirectory
        skipExisting = preferences.skipExisting
        recognizeScans = preferences.recognizeScans
    }

    private var converter: Converter {
        settings.converter(recognizingScans: recognizeScans && settings.ocr != nil)
    }

    // MARK: Queue editing

    /// Adds books and every book inside the given folders.
    func add(_ urls: [URL]) {
        let known = Set(jobs.map(\.source.standardizedFileURL))
        let fresh = BookScanner.books(in: urls)
            .filter { !known.contains($0.url.standardizedFileURL) }
            .map { ConversionJob(source: $0.url, relativeFolder: mode == .batch ? $0.relativeFolder : "") }
        jobs += fresh
    }

    func remove(_ ids: Set<ConversionJob.ID>) {
        jobs = jobs.filter { !ids.contains($0.id) || $0.isActive }
    }

    /// Removes converted and skipped books; failed ones stay so their errors can be read.
    func clearFinished() {
        jobs = jobs.filter {
            switch $0.status {
            case .finished, .skipped: false
            default: true
            }
        }
    }

    /// Sets the title, author and cover a waiting book is converted with.
    func setMetadata(_ metadata: BookMetadata, for id: ConversionJob.ID) {
        jobs = jobs.map { $0.id == id && $0.isPending ? $0.with(metadata: metadata) : $0 }
    }

    /// What the original book already says about its title and author.
    func originalMetadata(of job: ConversionJob) async -> BookMetadata {
        guard let format = job.format else { return .empty }
        return await settings.converter.metadataWriter.read(job.source, format: format)
    }

    /// Fields the user set that the target format cannot hold, or no tool here can write.
    func unwritableFields(for job: ConversionJob) -> [BookMetadata.Field] {
        let supported = settings.converter.metadataWriter.supportedFields(for: targetFormat)
        return BookMetadata.Field.allCases.filter { job.metadata.fields.contains($0) && !supported.contains($0) }
    }

    func clearAll() {
        guard !isRunning else { return }
        jobs = []
    }

    // MARK: Routing

    /// The engines a job would pass through, e.g. "DjVuLibre → Calibre", or nil if none can.
    func routeDescription(for job: ConversionJob) -> String? {
        guard let format = job.format else { return nil }
        return converter.routeDescription(from: format, to: targetFormat)
    }

    /// The books on screen: all of them, or in the Batch tab those matching the search.
    var visibleJobs: [ConversionJob] {
        mode == .batch ? BookSearch.filter(jobs, query: searchText) : jobs
    }

    var isSearching: Bool { mode == .batch && visibleJobs.count != jobs.count }

    /// How many books the next Convert would take on.
    var pendingVisibleCount: Int { visibleJobs.filter(\.isPending).count }

    var canStart: Bool {
        guard !isRunning, pendingVisibleCount > 0 else { return false }
        return mode == .quick || outputDirectory != nil
    }

    var doneCount: Int { jobs.filter(\.isDone).count }

    /// Books of the running Convert that are done.
    var runDoneCount: Int { jobs.filter { runIDs.contains($0.id) && $0.isDone }.count }

    // MARK: Running

    func start() {
        guard canStart else { return }
        isRunning = true
        let target = targetFormat
        let converter = converter
        let pending = visibleJobs.filter(\.isPending).map(\.id)
        runIDs = Set(pending)
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

    private func directory(for job: ConversionJob) -> URL {
        let base = outputDirectory ?? job.source.deletingLastPathComponent()
        return job.relativeFolder.isEmpty
            ? base
            : base.appendingPathComponent(job.relativeFolder, isDirectory: true)
    }

    private func run(_ id: ConversionJob.ID, to target: BookFormat, with converter: Converter) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        // A scan made searchable stays in its own format, so OCR allows PDF → PDF and DjVu → DjVu.
        let recognizes = converter.ocr != nil && OCRRoute.recognizes(target)
        guard job.format != target || recognizes else {
            update(id, .skipped("Already \(target.displayName)"))
            return
        }
        let directory = directory(for: job)
        let expected = directory
            .appendingPathComponent(job.source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(target.fileExtension)
        if mode == .batch, skipExisting, FileManager.default.fileExists(atPath: expected.path) {
            update(id, .skipped("Already converted"))
            return
        }

        update(id, .converting(progress: nil))
        do {
            let result = try await converter.convert(job.source, to: target, in: directory,
                                                     metadata: job.metadata) { [weak self] fraction in
                Task { @MainActor in self?.reportProgress(id, fraction) }
            }
            update(id, .finished(result))
        } catch is CancellationError {
            update(id, .cancelled)
        } catch ConversionError.alreadySearchable {
            update(id, .skipped("Already searchable"))
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
