//
//  ProcessRunner.swift
//  VPNGuard
//
//  Subprocess execution with a hard timeout. Kept in Shared so it can be
//  unit-tested and reused by both the app and the privileged helper.
//

import Foundation
import Darwin

struct ProcessResult: Equatable {
    /// False when the executable could not be launched at all.
    let launched: Bool
    let exitCode: Int32
    /// Merged stdout and stderr.
    let output: String
    /// True when the process exceeded the timeout and was terminated.
    let timedOut: Bool
}

enum ProcessRunner {

    /// Runs an executable synchronously, capturing merged stdout/stderr, and
    /// terminates it if it exceeds `timeout`. Callers can therefore never block
    /// indefinitely on a stuck child (which is what happens to `route`/`pfctl`
    /// after the machine wakes with broken DNS or networking).
    static func run(
        executable: String,
        arguments: [String] = [],
        timeout: TimeInterval
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain the pipe on a background queue so the child cannot block writing
        // into a full pipe buffer (which would look like a hang).
        let buffer = OutputBuffer()
        let readerDone = DispatchSemaphore(value: 0)
        let readQueue = DispatchQueue(label: "by.home.VPNGuard.ProcessRunner.read")
        readQueue.async {
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break } // EOF
                buffer.append(chunk)
            }
            readerDone.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            // Closing our copy of the write end lets the reader hit EOF.
            try? pipe.fileHandleForWriting.close()
            readerDone.wait()
            return ProcessResult(launched: false, exitCode: -1, output: "", timedOut: false)
        }

        // The child holds its own descriptor; close ours so EOF is observed when
        // the child exits (otherwise availableData would block forever).
        try? pipe.fileHandleForWriting.close()

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }

        readerDone.wait()
        let output = String(data: buffer.value, encoding: .utf8) ?? ""

        return ProcessResult(
            launched: true,
            exitCode: process.terminationStatus,
            output: output,
            timedOut: timedOut
        )
    }
}

/// Thread-safe byte accumulator for a process pipe.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
