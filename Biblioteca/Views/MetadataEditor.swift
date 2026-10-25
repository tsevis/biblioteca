import AppKit
import SwiftUI

/// Edits the title, author and cover a book is converted with.
struct MetadataEditor: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss
    let job: ConversionJob

    @State private var title = ""
    @State private var author = ""
    @State private var cover: URL?
    @State private var original = BookMetadata.empty
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(alignment: .top, spacing: 20) {
                CoverWell(cover: $cover)
                fields
            }
            footer
        }
        .padding(20)
        .frame(width: 520)
        .task { await load() }
    }

    private var fields: some View {
        Form {
            TextField("Title", text: $title, prompt: Text(job.source.deletingPathExtension().lastPathComponent))
            TextField("Author", text: $author, prompt: Text("Unknown"))
            Text("Separate several authors with “&”. Empty fields keep what the book already has.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(isLoading)
    }

    private var footer: some View {
        HStack {
            if isLoading { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                queue.setMetadata(edited, for: job.id)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading)
        }
    }

    /// Only what differs from the original book is written.
    private var edited: BookMetadata {
        let draft = BookMetadata(title: title, author: author, cover: cover)
        return BookMetadata(title: draft.title == original.title ? "" : draft.title,
                            author: draft.author == original.author ? "" : draft.author,
                            cover: draft.cover)
    }

    /// Fields the chosen target format cannot hold.
    private var warning: String? {
        let lost = queue.unwritableFields(for: job.with(metadata: edited))
        guard !lost.isEmpty else { return nil }
        let names = lost.map(\.displayName).joined(separator: ", ")
        return "\(queue.targetFormat.displayName) output will not get the \(names). "
            + "Calibre writes e-book metadata; DjVuLibre writes DjVu titles."
    }

    private func load() async {
        original = await queue.originalMetadata(of: job)
        let start = job.metadata.filling(from: original)
        title = start.title
        author = start.author
        cover = start.cover
        isLoading = false
    }
}

/// The cover thumbnail: drop an image on it, or click to choose one.
private struct CoverWell: View {
    @Binding var cover: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: choose) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1.5, dash: cover == nil ? [5, 4] : []))
                    if let image = cover.flatMap(NSImage.init(contentsOf:)) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(3)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo").font(.title)
                            Text("Cover").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 170)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to choose a cover image, or drop one here")
            .dropDestination(for: URL.self) { urls, _ in
                guard let image = urls.first(where: FilePanels.isImage) else { return false }
                cover = image
                return true
            } isTargeted: { isTargeted = $0 }

            Button("Remove Cover") { cover = nil }
                .controlSize(.small)
                .disabled(cover == nil)
        }
    }

    private func choose() {
        FilePanels.chooseImage { cover = $0 }
    }
}
