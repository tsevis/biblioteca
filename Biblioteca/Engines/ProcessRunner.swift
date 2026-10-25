import Foundation

/// Runs a command-line tool and waits for it without blocking a thread.
enum ProcessRunner {
    /// How much of the tool's output to keep for error messages.
    private static let logTailLength = 600

    /// Runs `executable` with `arguments`; throws `ConversionError.toolFailed` on a
    /// non-zero exit. Cancelling the calling task terminates the process.
    /// `onOutputLine` receives each line the tool prints, for progress parsing.
    static func run(
        _ executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice

        let log = OutputLog(onLine: onOutputLine)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            log.append(handle.availableData)
        }

        let box = ProcessBox(process)
        let (status, reason) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: (finished.terminationStatus, finished.terminationReason))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        log.append(pipe.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()

        let detail = String(log.text.suffix(logTailLength))
        if reason == .uncaughtSignal {
            throw ConversionError.toolCrashed(tool: executable.lastPathComponent, signal: status, detail: detail)
        }
        guard status == 0 else {
            throw ConversionError.toolFailed(tool: executable.lastPathComponent, status: status, detail: detail)
        }
    }
}

/// Lets the cancellation handler reach the process from another thread.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}

/// Collects a tool's output from the pipe's background queue.
private final class OutputLog: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var pendingLine = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    var text: String { lock.withLock { buffer } }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        let lines: [String] = lock.withLock {
            buffer += chunk
            let parts = (pendingLine + chunk).components(separatedBy: .newlines)
            pendingLine = parts.last ?? ""
            return Array(parts.dropLast())
        }
        lines.forEach { onLine?($0) }
    }
}

extension ProcessRunner {
    /// Runs the tool and returns the lines it printed.
    static func lines(of executable: URL, arguments: [String]) async throws -> [String] {
        let collector = LineCollector()
        try await run(executable, arguments: arguments) { collector.append($0) }
        return collector.lines
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []

    var lines: [String] { lock.withLock { collected } }

    func append(_ line: String) {
        lock.withLock { collected.append(line) }
    }
}
