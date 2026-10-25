import SwiftUI

struct ContentView: View {
    @Environment(ConversionQueue.self) private var queue
    @State private var selection = Set<ConversionJob.ID>()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if queue.jobs.isEmpty {
                EmptyQueueView(isTargeted: isTargeted) {
                    FilePanels.chooseBooks { queue.add($0) }
                }
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

/// The empty window: a drop target that is also one big button for choosing books.
private struct EmptyQueueView: View {
    let isTargeted: Bool
    let chooseBooks: () -> Void
    @State private var isHovering = false

    private var isHighlighted: Bool { isTargeted || isHovering }

    var body: some View {
        Button(action: chooseBooks) {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                Text("Drop books here")
                    .font(.title2.weight(.medium))
                Text("or click to choose books")
                    .font(.callout)
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                Text("PDF, EPUB, MOBI, AZW3, DjVu, FB2, CBZ, XPS, DOCX, TXT")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.06) : .clear)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.35))
                    .padding(20)
            }
            // The whole area answers clicks, not only the text and the symbol.
            .contentShape(Rectangle().inset(by: 20))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Add Books")
        .accessibilityHint("Opens a panel for choosing books, or drop books here")
    }
}
