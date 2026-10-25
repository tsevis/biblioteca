import AppKit
import SwiftUI

struct JobRowView: View {
    @Environment(ConversionQueue.self) private var queue
    let job: ConversionJob
    @State private var isEditing = false

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
                if let metadataLine {
                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(queue.unwritableFields(for: job).isEmpty ? Color.secondary : .orange)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if job.isPending {
                Button { isEditing = true } label: {
                    Image(systemName: job.metadata.isEmpty ? "tag" : "tag.fill")
                }
                .buttonStyle(.borderless)
                .help("Edit title, author and cover")
                .accessibilityLabel("Edit Metadata")
            }
            StatusView(status: job.status)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isEditing) { MetadataEditor(job: job) }
        .contextMenu {
            Button("Edit Title, Author and Cover…") { isEditing = true }
                .disabled(!job.isPending)
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
        if format == target { return place + "Already \(target.displayName)" }
        guard let route else {
            return place + "\(format.displayName) → \(target.displayName): install a converter in Settings"
        }
        return place + "\(format.displayName) → \(target.displayName) · \(route)"
    }

    /// What will be written into the converted book, and what cannot be.
    private var metadataLine: String? {
        let metadata = job.metadata
        guard !metadata.isEmpty else { return nil }
        let parts = [metadata.title.isEmpty ? nil : "“\(metadata.title)”",
                     metadata.author.isEmpty ? nil : metadata.author,
                     metadata.cover == nil ? nil : "new cover"].compactMap { $0 }
        let lost = queue.unwritableFields(for: job)
        guard !lost.isEmpty else { return parts.joined(separator: " · ") }
        let names = lost.map(\.displayName).joined(separator: ", ")
        return parts.joined(separator: " · ") + " — no \(names) in \(queue.targetFormat.displayName)"
    }

    /// In a batch, the folder the book came from and is written back into.
    private var place: String {
        job.relativeFolder.isEmpty ? "" : "\(job.relativeFolder) · "
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
                HStack(spacing: 6) {
                    ProgressView(value: progress).frame(width: 90)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
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
        case let .skipped(reason):
            Label("Skipped", systemImage: "arrow.uturn.forward.circle")
                .foregroundStyle(.secondary)
                .help(reason)
        }
    }
}
