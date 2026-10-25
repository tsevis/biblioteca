import SwiftUI

/// Target format, output folder and the Convert / Stop button.
struct ConversionBar: View {
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 16) {
            Picker("Convert to", selection: $queue.targetFormat) {
                ForEach(BookFormat.outputFormats) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .fixedSize()
            .disabled(queue.isRunning)

            Menu {
                Button("Next to Each Original") { queue.outputDirectory = nil }
                Button("Choose Folder…") { FilePanels.chooseFolder { queue.outputDirectory = $0 } }
            } label: {
                Label(queue.outputDirectory?.lastPathComponent ?? "Next to originals",
                      systemImage: "folder")
            }
            .fixedSize()
            .help(queue.outputDirectory?.path ?? "Converted books are saved beside the originals")
            .disabled(queue.isRunning)

            Spacer()

            if queue.isRunning {
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
}
