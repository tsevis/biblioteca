import SwiftUI

/// The search field above the Batch list, with how many books it shows.
struct BatchSearchField: View {
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search books and folders", text: $queue.searchText)
                .textFieldStyle(.plain)
            if !queue.searchText.isEmpty {
                Button {
                    queue.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the search")
            }
            Text(count)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help("Only the books shown are converted")
    }

    private var count: String {
        let total = queue.jobs.count
        let shown = queue.visibleJobs.count
        return shown == total ? "\(total) books" : "\(shown) of \(total) books"
    }
}
