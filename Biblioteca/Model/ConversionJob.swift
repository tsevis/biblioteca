import Foundation

/// One file in the queue and where its conversion stands.
struct ConversionJob: Identifiable, Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case waiting
        case converting(progress: Double?)
        case finished(URL)
        case failed(String)
        case cancelled
    }

    let id: UUID
    let source: URL
    let format: BookFormat?
    let status: Status

    init(source: URL) {
        id = UUID()
        self.source = source
        format = BookFormat(url: source)
        status = .waiting
    }

    private init(id: UUID, source: URL, format: BookFormat?, status: Status) {
        self.id = id
        self.source = source
        self.format = format
        self.status = status
    }

    func with(status: Status) -> ConversionJob {
        ConversionJob(id: id, source: source, format: format, status: status)
    }

    var name: String { source.lastPathComponent }

    var isActive: Bool {
        if case .converting = status { return true }
        return false
    }

    /// Waiting, failed and cancelled jobs are run (again) by the next Convert.
    var isPending: Bool {
        switch status {
        case .waiting, .failed, .cancelled: true
        case .converting, .finished: false
        }
    }
}
