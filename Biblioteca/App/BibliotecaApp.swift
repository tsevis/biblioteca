import AppKit
import SwiftUI

@main
struct BibliotecaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var queue = ConversionQueue()

    var body: some Scene {
        Window("biblioteca", id: "main") {
            ContentView()
                .environment(queue)
                .frame(minWidth: 560, minHeight: 380)
                .onAppear { appDelegate.queue = queue }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Books…") { FilePanels.chooseBooks { queue.add($0) } }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(queue)
        }
    }
}

/// Receives books opened from Finder ("Open With" or a drop on the Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var queue: ConversionQueue? {
        didSet { flushPending() }
    }
    @MainActor private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            pending += urls
            flushPending()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor private func flushPending() {
        guard let queue, !pending.isEmpty else { return }
        queue.add(pending)
        pending = []
    }
}
