import SwiftUI

struct ContentView: View {
    @Environment(ConversionQueue.self) private var queue
    @State private var selection = Set<ConversionJob.ID>()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if queue.jobs.isEmpty {
                EmptyQueueView(isTargeted: isTargeted)
            } else {
                List(queue.jobs, selection: $selection) { job in
                    JobRowView(job: job)
                }
                .onDeleteCommand { queue.remove(selection) }
            }
            Divider()
            ConversionBar()
        }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    FilePanels.chooseBooks { queue.add($0) }
                } label: {
                    Label("Add Books", systemImage: "plus")
                }
                Button {
                    queue.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "checkmark.circle.badge.xmark")
                }
                .disabled(!queue.jobs.contains { if case .finished = $0.status { true } else { false } })
            }
        }
    }
}

private struct EmptyQueueView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop books here")
                .font(.title2.weight(.medium))
            Text("PDF, EPUB, MOBI, AZW3, DjVu, FB2, CBZ, XPS, DOCX, TXT")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(20)
        }
    }
}
