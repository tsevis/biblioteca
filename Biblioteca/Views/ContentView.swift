import SwiftUI

/// The two ways of working, chosen in the toolbar.
enum MainTab: String, CaseIterable, Identifiable {
    case convert, batch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .batch: "Batch"
        }
    }
}

struct ContentView: View {
    let quick: ConversionQueue
    let batch: ConversionQueue
    @AppStorage("selectedTab") private var tab: MainTab = .convert

    var body: some View {
        QueueView()
            .environment(tab == .convert ? quick : batch)
            .id(tab)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $tab) {
                        ForEach(MainTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Convert: quick conversions. Batch: whole folders into one output folder.")
                }
            }
    }
}

/// One tab: its list of books (or the drop area when empty) and its bottom bar.
private struct QueueView: View {
    @Environment(ConversionQueue.self) private var queue
    @State private var selection = Set<ConversionJob.ID>()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if queue.jobs.isEmpty {
                EmptyQueueView(mode: queue.mode, isTargeted: isTargeted) {
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
                    Label("Add Books or Folders", systemImage: "plus")
                }
                Button {
                    queue.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "checkmark.circle.badge.xmark")
                }
                .disabled(queue.doneCount == 0)
            }
        }
    }
}

/// The empty tab: a drop target that is also one big button for choosing books.
private struct EmptyQueueView: View {
    let mode: ConversionQueue.Mode
    let isTargeted: Bool
    let chooseBooks: () -> Void
    @State private var isHovering = false

    private var isHighlighted: Bool { isTargeted || isHovering }

    var body: some View {
        Button(action: chooseBooks) {
            VStack(spacing: 14) {
                Image(systemName: mode == .batch ? "folder" : "books.vertical")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                Text("Drop books or folders here")
                    .font(.title2.weight(.medium))
                Text("or click to choose them")
                    .font(.callout)
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 40)
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
        .accessibilityLabel("Add Books or Folders")
        .accessibilityHint("Opens a panel for choosing books or folders, or drop them here")
    }

    private var detail: String {
        switch mode {
        case .quick:
            "PDF, EPUB, MOBI, AZW3, DjVu, FB2, CBZ, XPS, DOCX, TXT — folders are searched for books."
        case .batch:
            "Every book in the folders and their subfolders is converted into one output folder, "
                + "keeping the same folder structure."
        }
    }
}
