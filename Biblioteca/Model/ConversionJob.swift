import Foundation

/// One file in the queue and where its conversion stands.
struct ConversionJob: Identifiable, Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case waiting
        case converting(progress: Double?)
        case finished(URL)
        case failed(String)
        case cancelled
        /// Not converted, on purpose: already in the target format, or already converted.
        case skipped(String)
    }

    let id: UUID
    let source: URL
    let format: BookFormat?
    /// The folder, relative to the output folder, that a batch writes this book into.
    let relativeFolder: String
    let status: Status

    init(source: URL, relativeFolder: String = "") {
        id = UUID()
        self.source = source
        format = BookFormat(url: source)
        self.relativeFolder = relativeFolder
        status = .waiting
    }

    private init(id: UUID, source: URL, format: BookFormat?, relativeFolder: String, status: Status) {
        self.id = id
        self.source = source
        self.format = format
        self.relativeFolder = relativeFolder
        self.status = status
    }

    func with(status: Status) -> ConversionJob {
        ConversionJob(id: id, source: source, format: format, relativeFolder: relativeFolder, status: status)
    }

    var name: String { source.lastPathComponent }

    var isDone: Bool {
        switch status {
        case .finished, .failed, .skipped, .cancelled: true
        case .waiting, .converting: false
        }
    }

    var isActive: Bool {
        if case .converting = status { return true }
        return false
    }

    /// Waiting, failed and cancelled jobs are run (again) by the next Convert.
    var isPending: Bool {
        switch status {
        case .waiting, .failed, .cancelled: true
        case .converting, .finished, .skipped: false
        }
    }
}
