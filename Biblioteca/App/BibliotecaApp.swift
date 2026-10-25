import AppKit
import SwiftUI

@main
struct BibliotecaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var queue = ConversionQueue()
    /// The splash screen, shown at every launch and again from About biblioteca.
    @State private var isAboutPresented = true

    var body: some Scene {
        Window("biblioteca", id: "main") {
            AboutPresentation(isPresented: isAboutPresented, dismiss: { isAboutPresented = false }) {
                ContentView()
            }
            .environment(queue)
            .frame(minWidth: 720, minHeight: 540)
            .onAppear { appDelegate.queue = queue }
        }
        .commands {
            // Replaces the standard About panel with the splash screen.
            CommandGroup(replacing: .appInfo) {
                Button("About biblioteca") { isAboutPresented = true }
            }
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
