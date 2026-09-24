//
//  ProcessRunnerTests.swift
//  VPNGuardCoreTests
//

import XCTest
@testable import VPNGuardCore

final class ProcessRunnerTests: XCTestCase {

    func testCapturesOutputAndExitCode() {
        let result = ProcessRunner.run(executable: "/bin/echo", arguments: ["hello"], timeout: 5)

        XCTAssertTrue(result.launched)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.output.trimmingCharacters(in: .whitespacesAndNewlines),
            "hello"
        )
    }

    func testReportsNonZeroExit() {
        let result = ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "exit 3"],
            timeout: 5
        )

        XCTAssertTrue(result.launched)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 3)
    }

    /// A process that outlives the timeout must be terminated instead of hanging
    /// the caller — this is the core protection against a stuck `route`/`pfctl`.
    func testTimesOutAndTerminatesSlowProcess() {
        let start = Date()
        let result = ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"], timeout: 0.3)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(result.launched)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(elapsed, 5)
    }

    func testReportsLaunchFailureForMissingExecutable() {
        let result = ProcessRunner.run(
            executable: "/nonexistent/does-not-exist",
            timeout: 2
        )

        XCTAssertFalse(result.launched)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, -1)
    }

    /// Output far larger than the pipe buffer must be drained, not deadlock.
    func testCapturesLargeOutputWithoutDeadlock() {
        let result = ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes x | head -c 200000"],
            timeout: 10
        )

        XCTAssertTrue(result.launched)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.output.count, 200000)
    }
}
