import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            EnginesSettings()
                .tabItem { Label("Engines", systemImage: "shippingbox") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Page size for EPUB, MOBI… → PDF", selection: $settings.conversion.paper) {
                ForEach(PaperSize.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("DjVu pages", selection: $settings.conversion.djvuEncoding) {
                ForEach(DjVuEncoding.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("DjVu resolution", selection: $settings.conversion.djvuDPI) {
                ForEach(ConversionSettings.djvuDPIChoices, id: \.self) { Text("\($0) dpi").tag($0) }
            }
            Text("Black & white suits text and keeps files small; color keeps pictures. Higher resolution gives sharper pages and larger files.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("OCR") {
                Picker("Language of scans", selection: $settings.conversion.ocrLanguage) {
                    ForEach(OCRLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Text(recognizerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension GeneralSettings {
    var recognizerNote: String {
        let language = settings.conversion.ocrLanguage
        guard let ocr = settings.ocr else {
            return "\(language.displayName) is read by Tesseract, which is not installed. See Engines."
        }
        return "\(language.displayName) is read by \(ocr.recognizer.name), on this Mac. "
            + "Turn on OCR scans beside Convert to use it."
    }
}

private struct EnginesSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(settings.tools.tools) { tool in
                    ToolRow(tool: tool)
                }
            } footer: {
                HStack {
                    Text("PDF → EPUB and PDF → TXT also work without any of these.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Again") { settings.refreshTools() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ToolRow: View {
    let tool: ExternalTool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: tool.url == nil ? "xmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(tool.url == nil ? Color.secondary : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tool.engine.displayName) — \(tool.id)").font(.body.monospaced())
                Text(tool.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if tool.url == nil {
                Button("Copy Install Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tool.installCommand, forType: .string)
                }
                .help(tool.installCommand)
            }
        }
    }
}
