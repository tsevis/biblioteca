import Foundation

/// Runs tools that mangle non-ASCII file names on ASCII-named copies.
///
/// Without a UTF-8 locale (the normal case for a GUI app), DjVuLibre's `djvm`
/// writes "Βιβλίο.djvu" as "ÎÎ¹Î²Î»Î¯Î¿.djvu". Inside `body` the input is a copy
/// and the output a scratch file, both with ASCII paths; the result is then
/// moved to `output`.
enum ASCIIStaging {
    static func run<Result: Sendable>(
        input: URL,
        output: URL,
        body: (_ input: URL, _ output: URL) async throws -> Result
    ) async throws -> Result {
        let workspace = try TemporaryDirectory()
        defer { workspace.remove() }
        let stagedInput = workspace.url.appendingPathComponent("input.\(asciiExtension(of: input))")
        let stagedOutput = workspace.url.appendingPathComponent("output.\(asciiExtension(of: output))")
        // A clone on APFS, so even large books cost no time or space.
        try FileManager.default.copyItem(at: input, to: stagedInput)

        let result = try await body(stagedInput, stagedOutput)

        if FileManager.default.fileExists(atPath: stagedOutput.path) {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: stagedOutput, to: output)
        }
        return result
    }

    private static func asciiExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && ext.unicodeScalars.allSatisfy(\.isASCII) ? ext : "bin"
    }
}
