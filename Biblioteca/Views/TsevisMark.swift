import AppKit
import SwiftUI

/// The TVD logo in the bottom-left corner of the main window, linking to tsevis.com.
/// Sized like Nino and Hipparchus: two points taller than a status-bar symbol.
struct TsevisMark: View {
    @Environment(\.openURL) private var openURL

    private static let height: CGFloat = {
        let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        let configured = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        )
        return (configured?.size.height ?? 16) + 2
    }()

    var body: some View {
        Button {
            if let url = Brand.website { openURL(url) }
        } label: {
            Image(nsImage: Brand.logo)
                .resizable()
                .scaledToFit()
                .frame(height: Self.height)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("tsevis.com")
        .accessibilityLabel("Charis Tsevis — tsevis.com")
    }
}
