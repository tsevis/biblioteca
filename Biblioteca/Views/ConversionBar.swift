import SwiftUI

/// Target format, output folder and the Convert / Stop button of one tab.
struct ConversionBar: View {
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 16) {
            TsevisMark()

            Picker("Convert to", selection: $queue.targetFormat) {
                ForEach(BookFormat.outputFormats) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .fixedSize()
            .disabled(queue.isRunning)

            outputMenu
                .fixedSize()
                .help(queue.outputDirectory?.path ?? outputPlaceholder)
                .disabled(queue.isRunning)

            if queue.mode == .batch {
                Toggle("Skip converted", isOn: $queue.skipExisting)
                    .help("Leave a book alone when its converted file is already in the output folder")
                    .disabled(queue.isRunning)
            }

            Spacer()

            if queue.isRunning {
                Text("\(queue.doneCount) of \(queue.jobs.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Stop", role: .cancel) { queue.cancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button("Convert") { queue.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!queue.canStart)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var outputPlaceholder: String {
        queue.mode == .batch ? "Choose output folder" : "Next to originals"
    }

    private var outputMenu: some View {
        Menu {
            if queue.mode == .quick {
                Button("Next to Each Original") { queue.outputDirectory = nil }
            }
            Button("Choose Folder…") { FilePanels.chooseFolder { queue.outputDirectory = $0 } }
        } label: {
            Label(queue.outputDirectory?.lastPathComponent ?? outputPlaceholder,
                  systemImage: queue.outputDirectory == nil && queue.mode == .batch
                      ? "folder.badge.questionmark" : "folder")
        }
    }
}
