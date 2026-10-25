import AppKit
import SwiftUI

/// The splash screen: shown over the window at every launch and again from
/// About biblioteca, as in Nino and Philon.
struct AboutView: View {
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    private static let titleSize: CGFloat = 36
    private static let subtitleSize: CGFloat = 13
    private static let artHeight: CGFloat = 220

    /// Cap height of the title down to the subtitle's baseline, so the mark is
    /// as tall as the two lines of type beside it.
    private static let logoHeight: CGFloat = {
        let title = NSFont.systemFont(ofSize: titleSize, weight: .semibold)
        let subtitle = NSFont.systemFont(ofSize: subtitleSize)
        let titleLine = title.ascender - title.descender
        return titleLine + subtitle.ascender - (title.ascender - title.capHeight)
    }()

    var body: some View {
        VStack(spacing: 0) {
            keyArt
            Text(Self.about)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 20)
            Spacer(minLength: 16)
            footer
        }
        .frame(width: 640, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var keyArt: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: Brand.splashArt)
                .resizable()
                .scaledToFill()
                .frame(height: Self.artHeight)
                .clipped()
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Image(nsImage: Brand.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: Self.logoHeight)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Brand.name)
                        .font(.system(size: Self.titleSize, weight: .semibold))
                        .tracking(-0.6)
                    Text(Brand.tagline)
                        .font(.system(size: Self.subtitleSize))
                        .opacity(0.85)
                }
                Spacer()
                Text(Brand.version)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.75)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .frame(height: Self.artHeight)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Text("Created by Charis Tsevis, with the help of Claude Code.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                link("tsevis.com", Brand.website)
                link("github.com/tsevis", Brand.github)
                Spacer()
                Button("Continue", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }

    private func link(_ label: String, _ url: URL?) -> some View {
        Button(label) { if let url { openURL(url) } }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .pointerStyle(.link)
    }

    private static let about = """
        Drop books on the window and choose what they should become. biblioteca \
        reads and writes PDF, EPUB, MOBI, AZW3, DjVu, FB2 and more, and picks the \
        best converter installed on this Mac for each book — Calibre, DjVuLibre, \
        MuPDF, or its own PDF reader — going through PDF when no single tool can \
        do the whole journey.

        Nothing leaves this machine. Originals are never changed or overwritten, \
        and a conversion that fails leaves nothing half-written behind.
        """
}

/// Blurs and disables the window's content while the splash screen is open.
struct AboutPresentation<Content: View>: View {
    let isPresented: Bool
    let dismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content
                .blur(radius: isPresented ? 8 : 0)
                .disabled(isPresented)
                .accessibilityHidden(isPresented)
            if isPresented {
                AboutOverlay(dismiss: dismiss)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }
}

private struct AboutOverlay: View {
    let dismiss: () -> Void
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            AboutView(close: dismiss)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 30, y: 10)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .accessibilityLabel("About biblioteca")
        .accessibilityAddTraits(.isModal)
    }
}
