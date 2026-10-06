import Foundation

/// Runs system commands with a real timeout (the process is terminated if it
/// runs too long).
///
/// The waiting happens on a dedicated dispatch queue, never on Swift's
/// shared concurrency threads: those are few (one per core), and a command
/// that blocks one of them would stall every `await` in the app — timers,
/// main-actor hops, UI loading. Output is read as it arrives, so a child
/// process that keeps the pipe open can't block us after the command exits.
enum CommandRunner {
    struct Result: Sendable {
        var output: String
        var status: Int32
        var timedOut: Bool
    }

    private static let queue = DispatchQueue(label: "nova.commands", qos: .utility, attributes: .concurrent)

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) async -> String {
        await runWithStatus(path, arguments, timeout: timeout).output
    }

    static func runWithStatus(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: runBlocking(path, arguments, timeout: timeout)) }
        }
    }

    /// Blocking version; call only off the main thread and off Swift concurrency's threads.
    static func runBlocking(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe   // some tools (sysadminctl) print to stderr

        let output = OutputBuffer()
        let eof = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                eof.signal()
            } else {
                output.append(chunk)
            }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(output: "", status: -1, timedOut: false)
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        // Give the pipe a moment to drain; don't wait on children that keep it open.
        _ = eof.wait(timeout: .now() + 0.3)
        pipe.fileHandleForReading.readabilityHandler = nil
        let status = process.isRunning ? -1 : process.terminationStatus
        return Result(output: String(decoding: output.data, as: UTF8.self), status: status, timedOut: timedOut)
    }
}

/// Collects pipe output from the reader thread.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) { lock.lock(); storage.append(chunk); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
}
