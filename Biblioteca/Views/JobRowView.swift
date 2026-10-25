import AppKit
import SwiftUI

struct JobRowView: View {
    @Environment(ConversionQueue.self) private var queue
    let job: ConversionJob

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.source.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(route == nil ? Color.orange : .secondary)
            }
            Spacer(minLength: 12)
            StatusView(status: job.status)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show Original in Finder") { reveal(job.source) }
            if case let .finished(url) = job.status {
                Button("Show Converted Book in Finder") { reveal(url) }
            }
            Button("Remove from List") { queue.remove([job.id]) }
                .disabled(job.isActive)
        }
    }

    private var route: String? { queue.routeDescription(for: job) }

    private var subtitle: String {
        guard let format = job.format else { return "Unknown format" }
        let target = queue.targetFormat
        if format == target { return "Already \(target.displayName)" }
        guard let route else {
            return "\(format.displayName) → \(target.displayName): install a converter in Settings"
        }
        return "\(format.displayName) → \(target.displayName) · \(route)"
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct StatusView: View {
    let status: ConversionJob.Status

    var body: some View {
        switch status {
        case .waiting:
            EmptyView()
        case let .converting(progress):
            if let progress {
                ProgressView(value: progress).frame(width: 90)
            } else {
                ProgressView().controlSize(.small)
            }
        case let .finished(url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help(url.path)
        case let .failed(message):
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(message)
        case .cancelled:
            Text("Stopped").foregroundStyle(.secondary)
        }
    }
}
