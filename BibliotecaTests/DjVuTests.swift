import Foundation
import Testing

@Suite("DjVu")
struct DjVuTests {
    @Test("Text layer scales PDF points to DjVu pixels and escapes quotes")
    func textLayerScript() {
        let lines = [TextLine(text: #"Ο "τίτλος" \ 1"#, frame: CGRect(x: 72, y: 700, width: 144, height: 12))]
        let script = DjVuTextLayer.script(page: 3, lines: lines,
                                          mediaBox: CGRect(x: 0, y: 0, width: 612, height: 792), dpi: 144)
        #expect(script == """
        select 3
        set-txt
        (page 0 0 1224 1584
         (line 144 1400 432 1424 "Ο \\"τίτλος\\" \\\\ 1"))
        .

        """)
    }

    @Test("An empty text result is reported as a missing text layer")
    func emptyTextMeansNoTextLayer() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let input = workspace.url.appendingPathComponent("scan.djvu")
        try Data("x".utf8).write(to: input)

        let converter = Converter(engines: [EmptyOutputEngine()])
        await #expect(throws: ConversionError.noTextLayer) {
            _ = try await converter.convert(input, to: .txt, in: workspace.url) { _ in }
        }
    }
}

/// Succeeds but writes nothing, as `djvutxt` does for a scanned book.
private struct EmptyOutputEngine: ConversionEngine {
    let id = EngineID.djvulibre
    func canConvert(from source: BookFormat, to target: BookFormat) -> Bool { true }
    func convert(_ input: URL, to output: URL, from source: BookFormat, target: BookFormat,
                 progress: @escaping ProgressHandler) async throws {
        try Data().write(to: output)
    }
}

@Suite("ASCIIStaging")
struct ASCIIStagingTests {
    @Test("Tools see only ASCII paths, and the result lands at the Greek name")
    func toolsSeeOnlyASCIIPaths() async throws {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let folder = workspace.url.appendingPathComponent("Βιβλία", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = folder.appendingPathComponent("Οδύσσεια.pdf")
        try Data("in".utf8).write(to: input)
        let output = folder.appendingPathComponent("Οδύσσεια.djvu")

        let seen = try await ASCIIStaging.run(input: input, output: output) { stagedIn, stagedOut in
            try Data("out".utf8).write(to: stagedOut)
            return [stagedIn.path, stagedOut.path]
        }

        #expect(seen.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
        #expect(try String(contentsOf: output, encoding: .utf8) == "out")
    }
}
